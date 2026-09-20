import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import 'chapter_persistence.dart';
import '../manga_processing/data/processing_repository.dart';
import '../manga_processing/domain/page_analysis.dart';
import '../manga_processing/domain/region_edits.dart';

enum ChapterPageStatus { pending, processing, completed, failed }

class ChapterPage {
  ChapterPage(this.file);
  final File file;
  String get name => file.uri.pathSegments.last;
  ChapterPageStatus status = ChapterPageStatus.pending;
  PageAnalysis? analysis;
  PageEdits edits = PageEdits();
  SourceFingerprint? fingerprint;
  bool restoredFromCache = false;
  String? error;
  Duration? duration;
}

int naturalCompare(String a, String b) {
  final tokens = RegExp(r'\d+|\D+');
  final left = tokens
      .allMatches(a.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  final right = tokens
      .allMatches(b.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i], y = right[i];
    final xn = BigInt.tryParse(x), yn = BigInt.tryParse(y);
    int result;
    if (xn != null && yn != null) {
      result = xn.compareTo(yn);
      if (result == 0) result = x.length.compareTo(y.length);
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result;
  }
  final length = left.length.compareTo(right.length);
  return length != 0 ? length : a.compareTo(b);
}

bool isChapterImage(String name) =>
    RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(name);

List<File> orderedChapterFiles(Iterable<File> files) =>
    files.where((file) => isChapterImage(file.path)).toList()..sort(
      (a, b) => naturalCompare(
        a.path.split(Platform.pathSeparator).last,
        b.path.split(Platform.pathSeparator).last,
      ),
    );

String formatDuration(Duration value) {
  final seconds = value.inSeconds.clamp(0, 99999999);
  final s = (seconds % 60).toString().padLeft(2, '0');
  final m = ((seconds ~/ 60) % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${(seconds ~/ 3600).toString().padLeft(2, '0')}:$m:$s'
      : '$m:$s';
}

class ChapterController extends ChangeNotifier {
  ChapterController(
    this.repository, {
    Stopwatch Function()? stopwatchFactory,
    this.persistence,
  }) : _stopwatchFactory = stopwatchFactory ?? Stopwatch.new;

  final ProcessingRepository repository;
  ChapterPersistenceRepository? persistence;
  String? cacheWarning;
  String? saveError;
  bool _cacheWritable = true;
  Timer? _saveDebounce;
  ChapterPage? _debouncedPage;
  bool _disposed = false;
  final Set<ChapterPage> _boxPreviewPages = {};
  Future<void> _saveTail = Future.value();
  final Stopwatch Function() _stopwatchFactory;
  List<ChapterPage> pages = [];
  final List<Duration> _successfulDurations = [];
  String? directoryPath;
  String? error;
  int selectedPageIndex = 0;
  String? selectedRegionId;
  bool processing = false;
  bool stopRequested = false;
  Duration chapterElapsed = Duration.zero;
  Duration pageElapsed = Duration.zero;
  Stopwatch? _chapterWatch;
  Stopwatch? _pageWatch;
  Timer? _ticker;
  Future<void>? _activePage;
  int _generation = 0;

  ChapterPage? get selectedPage =>
      pages.isEmpty ? null : pages[selectedPageIndex];
  PageAnalysis? get analysis => selectedPage?.analysis;
  DetectedRegion? get selectedRegion {
    for (final region in analysis?.regions ?? <DetectedRegion>[]) {
      if (region.id == selectedRegionId) return region;
    }
    return null;
  }

  void setTranslation(String id, String? text) {
    if (analysis?.regions.any((region) => region.id == id) != true) return;
    selectedPage!.edits.setTranslation(id, text);
    _scheduleSave(selectedPage!);
    notifyListeners();
  }

  String? setBox(String id, RegionBox box, {bool persist = true}) {
    final result = analysis;
    if (result == null || !result.regions.any((region) => region.id == id)) {
      return 'Region is unavailable.';
    }
    final error = validateRegionBox(box, result);
    if (error != null) return error;
    selectedPage!.edits.setBox(id, box);
    if (persist) {
      _scheduleSave(selectedPage!, immediate: true);
    } else {
      if (_debouncedPage == selectedPage) {
        _saveDebounce?.cancel();
        _saveDebounce = null;
        _debouncedPage = null;
      }
      _boxPreviewPages.add(selectedPage!);
    }
    notifyListeners();
    return null;
  }

  void commitBoxPreview(ChapterPage page) {
    if (_boxPreviewPages.remove(page)) _scheduleSave(page, immediate: true);
  }

  void resetBox(String id) {
    selectedPage?.edits.setBox(id, null);
    if (selectedPage != null) _scheduleSave(selectedPage!, immediate: true);
    notifyListeners();
  }

  String get name => directoryPath == null
      ? ''
      : Directory(
          directoryPath!,
        ).uri.pathSegments.where((s) => s.isNotEmpty).last;
  int get completedCount =>
      pages.where((p) => p.status == ChapterPageStatus.completed).length;
  int get settledCount => pages
      .where(
        (p) =>
            p.status == ChapterPageStatus.completed ||
            p.status == ChapterPageStatus.failed,
      )
      .length;
  int get pendingCount =>
      pages.where((p) => p.status == ChapterPageStatus.pending).length;
  int get currentPageIndex =>
      pages.indexWhere((p) => p.status == ChapterPageStatus.processing);
  Duration? get averageDuration {
    if (_successfulDurations.isEmpty) return null;
    final recent = _successfulDurations.skip(
      (_successfulDurations.length - 5).clamp(0, _successfulDurations.length),
    );
    final total = recent.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: total ~/ recent.length);
  }

  Duration? get pageRemaining {
    final average = averageDuration;
    if (average == null || currentPageIndex < 0) return null;
    return Duration(
      milliseconds: (average.inMilliseconds - pageElapsed.inMilliseconds).clamp(
        0,
        average.inMilliseconds,
      ),
    );
  }

  Duration? get estimatedRemaining {
    final average = averageDuration;
    if (average == null) return null;
    final current = currentPageIndex >= 0 ? pageRemaining!.inMilliseconds : 0;
    return Duration(
      milliseconds: average.inMilliseconds * pendingCount + current,
    );
  }

  Duration? get estimatedTotal =>
      estimatedRemaining == null ? null : chapterElapsed + estimatedRemaining!;

  Future<void> open(String path) async {
    stopRequested = true;
    await _activePage;
    await flushSaves();
    _generation++;
    _stopTimer();
    processing = false;
    final files = orderedChapterFiles(
      Directory(path).listSync(followLinks: false).whereType<File>(),
    );
    pages = files.map(ChapterPage.new).toList();
    _successfulDurations.clear();
    directoryPath = path;
    selectedPageIndex = 0;
    selectedRegionId = null;
    chapterElapsed = Duration.zero;
    pageElapsed = Duration.zero;
    error = pages.isEmpty ? 'No supported images in this folder.' : null;
    saveError = null;
    cacheWarning = null;
    _cacheWritable = true;
    if (persistence != null && pages.isNotEmpty) {
      final loaded = await persistence!.load(path);
      cacheWarning = loaded.warning;
      _cacheWritable = loaded.writable;
      for (final page in pages) {
        final saved = loaded.pages[page.name];
        if (saved == null) continue;
        try {
          final current = await fingerprintFile(page.file);
          if (current.sha256Hash != saved.fingerprint.sha256Hash) {
            cacheWarning =
                'Some source pages changed; stale analysis was not restored.';
            continue;
          }
          page.fingerprint = current;
          page.analysis = saved.analysis;
          page.edits = saved.edits;
          page.duration = saved.duration;
          page.status = ChapterPageStatus.completed;
          page.restoredFromCache = true;
          if (page.duration != null) _successfulDurations.add(page.duration!);
        } catch (_) {
          cacheWarning = 'Some cached pages could not be validated.';
        }
      }
    }
    stopRequested = false;
    notifyListeners();
  }

  void selectPage(int index) {
    if (index < 0 || index >= pages.length) return;
    if (selectedPage != null) commitBoxPreview(selectedPage!);
    selectedPageIndex = index;
    selectedRegionId = null;
    notifyListeners();
  }

  void selectRegion(String id) {
    if (analysis?.regions.any((r) => r.id == id) != true) return;
    selectedRegionId = id;
    notifyListeners();
  }

  void requestStop() {
    stopRequested = true;
    notifyListeners();
  }

  Future<void> stopAndWait() async {
    requestStop();
    await _activePage;
    await flushSaves();
  }

  Future<void> processPending() async {
    if (processing || pages.isEmpty || pendingCount == 0) return;
    processing = true;
    stopRequested = false;
    final generation = _generation;
    _chapterWatch = _stopwatchFactory()..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    try {
      for (
        var i = 0;
        i < pages.length && !stopRequested && generation == _generation;
        i++
      ) {
        if (pages[i].status == ChapterPageStatus.pending) {
          _activePage = _processPage(i, generation);
          await _activePage;
          _activePage = null;
        }
      }
    } finally {
      if (generation == _generation) {
        _stopTimer();
        processing = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryPage(int index) async {
    if (processing ||
        index < 0 ||
        index >= pages.length ||
        pages[index].status != ChapterPageStatus.failed) {
      return;
    }
    processing = true;
    stopRequested = false;
    final generation = _generation;
    _chapterWatch = _stopwatchFactory()..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    try {
      _activePage = _processPage(index, generation);
      await _activePage;
      _activePage = null;
    } finally {
      if (generation == _generation) {
        _stopTimer();
        processing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _processPage(int index, int generation) async {
    final page = pages[index];
    page.status = ChapterPageStatus.processing;
    page.error = null;
    page.analysis = null;
    page.edits = PageEdits();
    page.fingerprint = null;
    page.restoredFromCache = false;
    page.duration = null;
    pageElapsed = Duration.zero;
    _pageWatch = _stopwatchFactory()..start();
    notifyListeners();
    try {
      final bytes = await page.file.readAsBytes();
      final uploadedHash = sha256.convert(bytes).toString();
      final result = await repository.analyze(page.name, bytes);
      if (generation != _generation) return;
      final current = await fingerprintFile(page.file);
      if (current.sha256Hash != uploadedHash) {
        throw StateError(
          'Source image changed during processing. Retry this page.',
        );
      }
      page.fingerprint = current;
      page.analysis = result;
      page.status = ChapterPageStatus.completed;
    } catch (e) {
      if (generation != _generation) return;
      page.error = e.toString();
      page.status = ChapterPageStatus.failed;
    } finally {
      if (generation == _generation) {
        page.duration = _pageWatch!.elapsed;
        if (page.status == ChapterPageStatus.completed) {
          _successfulDurations.add(page.duration!);
        }
        _pageWatch!.stop();
        pageElapsed = Duration.zero;
        notifyListeners();
        if (page.status == ChapterPageStatus.completed) {
          await _queueSave(page);
        }
      }
    }
  }

  void _tick() {
    chapterElapsed += _chapterWatch?.elapsed ?? Duration.zero;
    _chapterWatch?.reset();
    pageElapsed = _pageWatch?.elapsed ?? Duration.zero;
    notifyListeners();
  }

  void _scheduleSave(ChapterPage page, {bool immediate = false}) {
    final previous = _debouncedPage;
    if (_saveDebounce?.isActive == true &&
        previous != null &&
        previous != page) {
      unawaited(_queueSave(previous));
    }
    _saveDebounce?.cancel();
    _debouncedPage = null;
    if (immediate) {
      unawaited(_queueSave(page));
    } else {
      _debouncedPage = page;
      _saveDebounce = Timer(const Duration(milliseconds: 700), () {
        _debouncedPage = null;
        unawaited(_queueSave(page));
      });
    }
  }

  Future<void> _queueSave(ChapterPage page) {
    final source = directoryPath;
    final service = persistence;
    if (!_cacheWritable ||
        source == null ||
        service == null ||
        page.status != ChapterPageStatus.completed ||
        page.analysis == null ||
        page.fingerprint == null) {
      return Future.value();
    }
    final fingerprint = page.fingerprint!;
    final result = page.analysis!;
    final savedEdits = page.edits.copy();
    final duration = page.duration;
    _saveTail = _saveTail.then((_) async {
      try {
        await service.savePage(
          source,
          PersistedPage(
            name: page.name,
            fingerprint: fingerprint,
            analysis: result,
            edits: savedEdits,
            duration: duration,
          ),
        );
        saveError = null;
      } catch (error) {
        saveError = 'Could not save chapter changes: $error';
      }
      if (!_disposed) notifyListeners();
    });
    return _saveTail;
  }

  Future<void> flushSaves() async {
    for (final page in _boxPreviewPages.toList()) {
      commitBoxPreview(page);
    }
    final timer = _saveDebounce;
    final page = _debouncedPage;
    _saveDebounce = null;
    _debouncedPage = null;
    if (timer?.isActive == true && page != null) {
      timer!.cancel();
      await _queueSave(page);
    }
    await _saveTail;
  }

  @visibleForTesting
  void tickForTest() => _tick();

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    chapterElapsed += _chapterWatch?.elapsed ?? Duration.zero;
    _chapterWatch?.stop();
    _chapterWatch = null;
    _pageWatch?.stop();
    _pageWatch = null;
    pageElapsed = Duration.zero;
  }

  @override
  void dispose() {
    _generation++;
    unawaited(flushSaves());
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}

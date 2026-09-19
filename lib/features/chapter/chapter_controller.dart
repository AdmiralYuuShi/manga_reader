import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../manga_processing/data/processing_repository.dart';
import '../manga_processing/domain/page_analysis.dart';

enum ChapterPageStatus { pending, processing, completed, failed }

class ChapterPage {
  ChapterPage(this.file);
  final File file;
  String get name => file.uri.pathSegments.last;
  ChapterPageStatus status = ChapterPageStatus.pending;
  PageAnalysis? analysis;
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
  ChapterController(this.repository, {Stopwatch Function()? stopwatchFactory})
    : _stopwatchFactory = stopwatchFactory ?? Stopwatch.new;

  final ProcessingRepository repository;
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
    stopRequested = false;
    notifyListeners();
  }

  void selectPage(int index) {
    if (index < 0 || index >= pages.length) return;
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
  }

  Future<void> processPending() async {
    if (processing || pages.isEmpty) return;
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
    page.duration = null;
    pageElapsed = Duration.zero;
    _pageWatch = _stopwatchFactory()..start();
    notifyListeners();
    try {
      final bytes = await page.file.readAsBytes();
      final result = await repository.analyze(page.name, bytes);
      if (generation != _generation) return;
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
      }
    }
  }

  void _tick() {
    chapterElapsed += _chapterWatch?.elapsed ?? Duration.zero;
    _chapterWatch?.reset();
    pageElapsed = _pageWatch?.elapsed ?? Duration.zero;
    notifyListeners();
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
    _stopTimer();
    super.dispose();
  }
}

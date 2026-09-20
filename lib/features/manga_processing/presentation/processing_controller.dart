import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../chapter/chapter_persistence.dart';
import '../data/processing_repository.dart';
import '../domain/page_analysis.dart';
import '../domain/region_edits.dart';

enum ProcessingStatus { initial, processing, success, failure }

class ProcessingController extends ChangeNotifier {
  ProcessingController(this.repository);

  final ProcessingRepository repository;
  Uint8List? imageBytes;
  String? filename;
  PageAnalysis? analysis;
  PageEdits edits = PageEdits();
  ChapterPersistenceRepository? persistence;
  File? sourceFile;
  SourceFingerprint? sourceFingerprint;
  bool restoredFromCache = false;
  String? cacheWarning;
  String? saveError;
  bool _cacheWritable = true;
  Timer? _saveDebounce;
  Future<void> _saveTail = Future.value();
  bool _disposed = false;
  bool _boxPreviewDirty = false;
  String? error;
  ProcessingStatus status = ProcessingStatus.initial;
  String? selectedRegionId;
  int _selectionVersion = 0;

  DetectedRegion? get selectedRegion {
    final regions = analysis?.regions;
    if (regions == null || selectedRegionId == null) return null;
    for (final region in regions) {
      if (region.id == selectedRegionId) return region;
    }
    return null;
  }

  void selectRegion(String id) {
    if (analysis?.regions.any((region) => region.id == id) != true) return;
    selectedRegionId = id;
    notifyListeners();
  }

  void selectImage(String name, Uint8List bytes) {
    commitBoxPreview();
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _selectionVersion++;
    sourceFile = null;
    sourceFingerprint = null;
    restoredFromCache = false;
    cacheWarning = null;
    saveError = null;
    _cacheWritable = true;
    filename = name;
    imageBytes = bytes;
    analysis = null;
    edits = PageEdits();
    selectedRegionId = null;
    error = null;
    status = ProcessingStatus.initial;
    notifyListeners();
  }

  Future<void> openImageFile(String path, Uint8List bytes) async {
    await flushSaves();
    final file = File(path);
    selectImage(p.basename(path), bytes);
    sourceFile = file;
    final service = persistence;
    if (service == null) return;
    final version = _selectionVersion;
    final loaded = await service.load(p.dirname(path));
    if (version != _selectionVersion) return;
    _cacheWritable = loaded.writable;
    cacheWarning = loaded.warning;
    final saved = loaded.pages[p.basename(path)];
    if (saved != null) {
      try {
        final current = await fingerprintFile(file);
        if (version != _selectionVersion) return;
        if (current.sha256Hash == saved.fingerprint.sha256Hash &&
            current.sha256Hash == sha256.convert(bytes).toString()) {
          sourceFingerprint = current;
          analysis = saved.analysis;
          edits = saved.edits;
          status = ProcessingStatus.success;
          restoredFromCache = true;
        } else {
          cacheWarning =
              'Source image changed; stale analysis was not restored.';
        }
      } catch (_) {
        cacheWarning = 'Cached image could not be validated.';
      }
    }
    notifyListeners();
  }

  Future<void> detect() async {
    final name = filename;
    final bytes = imageBytes;
    if (name == null ||
        bytes == null ||
        status == ProcessingStatus.processing) {
      return;
    }
    status = ProcessingStatus.processing;
    analysis = null;
    selectedRegionId = null;
    final version = _selectionVersion;
    error = null;
    notifyListeners();
    try {
      final result = await repository.analyze(name, bytes);
      if (version != _selectionVersion) return;
      if (sourceFile != null && persistence != null) {
        final current = await fingerprintFile(sourceFile!);
        if (version != _selectionVersion) return;
        if (current.sha256Hash != sha256.convert(bytes).toString()) {
          throw StateError(
            'Source image changed during processing. Reopen it.',
          );
        }
        sourceFingerprint = current;
      }
      analysis = result;
      edits = PageEdits();
      restoredFromCache = false;
      status = ProcessingStatus.success;
      await _queueSave();
    } catch (exception) {
      if (version != _selectionVersion) return;
      error = exception.toString();
      status = ProcessingStatus.failure;
    }
    notifyListeners();
  }

  void setTranslation(String id, String? text) {
    if (analysis?.regions.any((region) => region.id == id) != true) return;
    edits.setTranslation(id, text);
    _scheduleSave();
    notifyListeners();
  }

  String? setBox(String id, RegionBox box, {bool persist = true}) {
    final result = analysis;
    if (result == null || !result.regions.any((region) => region.id == id)) {
      return 'Region is unavailable.';
    }
    final error = validateRegionBox(box, result);
    if (error != null) return error;
    edits.setBox(id, box);
    if (persist) {
      _scheduleSave(immediate: true);
    } else {
      _saveDebounce?.cancel();
      _saveDebounce = null;
      _boxPreviewDirty = true;
    }
    notifyListeners();
    return null;
  }

  void commitBoxPreview() {
    if (!_boxPreviewDirty) return;
    _boxPreviewDirty = false;
    _scheduleSave(immediate: true);
  }

  void resetBox(String id) {
    edits.setBox(id, null);
    _scheduleSave(immediate: true);
    notifyListeners();
  }

  void _scheduleSave({bool immediate = false}) {
    _saveDebounce?.cancel();
    if (immediate) {
      unawaited(_queueSave());
    } else {
      _saveDebounce = Timer(const Duration(milliseconds: 700), () {
        unawaited(_queueSave());
      });
    }
  }

  Future<void> _queueSave() {
    final file = sourceFile;
    final service = persistence;
    if (!_cacheWritable ||
        file == null ||
        service == null ||
        status != ProcessingStatus.success ||
        analysis == null ||
        sourceFingerprint == null) {
      return Future.value();
    }
    final directory = p.dirname(file.path);
    final name = p.basename(file.path);
    final fingerprint = sourceFingerprint!;
    final result = analysis!;
    final savedEdits = edits.copy();
    _saveTail = _saveTail.then((_) async {
      try {
        await service.savePage(
          directory,
          PersistedPage(
            name: name,
            fingerprint: fingerprint,
            analysis: result,
            edits: savedEdits,
          ),
        );
        saveError = null;
      } catch (error) {
        saveError = 'Could not save image changes: $error';
      }
      if (!_disposed) notifyListeners();
    });
    return _saveTail;
  }

  Future<void> flushSaves() async {
    commitBoxPreview();
    final timer = _saveDebounce;
    _saveDebounce = null;
    if (timer?.isActive == true) {
      timer!.cancel();
      await _queueSave();
    }
    await _saveTail;
  }

  @override
  void dispose() {
    unawaited(flushSaves());
    _disposed = true;
    super.dispose();
  }
}

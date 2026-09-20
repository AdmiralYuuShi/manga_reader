import 'package:flutter/foundation.dart';

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
    _selectionVersion++;
    filename = name;
    imageBytes = bytes;
    analysis = null;
    edits = PageEdits();
    selectedRegionId = null;
    error = null;
    status = ProcessingStatus.initial;
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
      analysis = result;
      edits = PageEdits();
      status = ProcessingStatus.success;
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
    notifyListeners();
  }

  String? setBox(String id, RegionBox box) {
    final result = analysis;
    if (result == null || !result.regions.any((region) => region.id == id)) {
      return 'Region is unavailable.';
    }
    final error = validateRegionBox(box, result);
    if (error != null) return error;
    edits.setBox(id, box);
    notifyListeners();
    return null;
  }

  void resetBox(String id) {
    edits.setBox(id, null);
    notifyListeners();
  }
}

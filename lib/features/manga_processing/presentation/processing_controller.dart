import 'package:flutter/foundation.dart';

import '../data/processing_repository.dart';
import '../domain/page_analysis.dart';

enum ProcessingStatus { initial, processing, success, failure }

class ProcessingController extends ChangeNotifier {
  ProcessingController(this.repository);

  final ProcessingRepository repository;
  Uint8List? imageBytes;
  String? filename;
  PageAnalysis? analysis;
  String? error;
  ProcessingStatus status = ProcessingStatus.initial;
  int _selectionVersion = 0;

  void selectImage(String name, Uint8List bytes) {
    _selectionVersion++;
    filename = name;
    imageBytes = bytes;
    analysis = null;
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
    final version = _selectionVersion;
    error = null;
    notifyListeners();
    try {
      final result = await repository.analyze(name, bytes);
      if (version != _selectionVersion) return;
      analysis = result;
      status = ProcessingStatus.success;
    } catch (exception) {
      if (version != _selectionVersion) return;
      error = exception.toString();
      status = ProcessingStatus.failure;
    }
    notifyListeners();
  }
}

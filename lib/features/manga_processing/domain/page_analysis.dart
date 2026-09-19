class DetectedRegion {
  const DetectedRegion({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.sourceLanguage,
    this.sourceText,
    this.errorCode,
  });

  final String id;
  final int x;
  final int y;
  final int width;
  final int height;
  final String? sourceLanguage;
  final String? sourceText;
  final String? errorCode;
}

class PageAnalysis {
  const PageAnalysis({
    required this.width,
    required this.height,
    required this.regions,
  });

  final int width;
  final int height;
  final List<DetectedRegion> regions;
}

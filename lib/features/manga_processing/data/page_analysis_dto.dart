import '../domain/page_analysis.dart';

PageAnalysis parsePageAnalysis(Map<String, dynamic> json) {
  final page = json['page'] as Map<String, dynamic>;
  final regions = json['regions'] as List<dynamic>;
  return PageAnalysis(
    width: page['width'] as int,
    height: page['height'] as int,
    regions: regions.map((value) {
      final region = value as Map<String, dynamic>;
      final box = region['bbox'] as Map<String, dynamic>;
      return DetectedRegion(
        id: region['id'] as String,
        x: box['x'] as int,
        y: box['y'] as int,
        width: box['width'] as int,
        height: box['height'] as int,
        sourceLanguage: region['source_language'] as String?,
        sourceText: region['source_text'] as String?,
        errorCode:
            (region['error'] as Map<String, dynamic>?)?['code'] as String?,
        targetLanguage: region['target_language'] as String?,
        translatedText: region['translated_text'] as String?,
        translationErrorCode:
            (region['translation_error'] as Map<String, dynamic>?)?['code']
                as String?,
      );
    }).toList(),
  );
}

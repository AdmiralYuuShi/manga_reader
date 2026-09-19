import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/manga_processing/data/page_analysis_dto.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/region_geometry.dart';

void main() {
  test('parses detection response', () {
    final result = parsePageAnalysis({
      'page': {'width': 1600, 'height': 2400},
      'regions': [
        {
          'id': 'region_001',
          'bbox': {'x': 100, 'y': 200, 'width': 300, 'height': 400},
          'source_language': 'ja',
          'source_text': '今日は学校に行くの？',
          'error': null,
        },
      ],
      'processing': {'detection_ms': 10, 'total_ms': 11},
    });
    expect(result.width, 1600);
    expect(result.regions.single.height, 400);
    expect(result.regions.single.sourceText, '今日は学校に行くの？');
    expect(result.regions.single.sourceLanguage, 'ja');
  });

  test('maps original pixels through BoxFit.contain letterboxing', () {
    const region = DetectedRegion(
      id: 'r',
      x: 100,
      y: 200,
      width: 300,
      height: 400,
    );
    final rect = displayRectForRegion(
      region,
      const Size(1600, 2400),
      const Size(800, 800),
    );
    expect(rect.left, closeTo(166.67, 0.01));
    expect(rect.top, closeTo(66.67, 0.01));
    expect(rect.width, closeTo(100, 0.01));
    expect(rect.height, closeTo(133.33, 0.01));
  });

  test('parses region OCR failure', () {
    final result = parsePageAnalysis({
      'page': {'width': 10, 'height': 10},
      'regions': [
        {
          'id': 'region_002',
          'bbox': {'x': 1, 'y': 1, 'width': 2, 'height': 2},
          'source_language': 'ja',
          'source_text': null,
          'error': {'code': 'OCR_FAILED'},
        },
      ],
    });
    expect(result.regions.single.sourceText, isNull);
    expect(result.regions.single.errorCode, 'OCR_FAILED');
  });
}

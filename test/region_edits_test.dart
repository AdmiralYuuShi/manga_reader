import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/domain/region_edits.dart';
import 'package:manga_translator/features/manga_processing/presentation/processing_controller.dart';

class ReplacementRepository extends ProcessingRepository {
  ReplacementRepository(this.result)
    : super(ProcessingRemoteDataSource(ApiClient()));
  final PageAnalysis result;
  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) async =>
      result;
}

void main() {
  const region = DetectedRegion(
    id: 'r',
    x: 10,
    y: 20,
    width: 30,
    height: 40,
    sourceText: '日本語',
    translatedText: 'Machine',
  );
  const analysis = PageAnalysis(width: 100, height: 120, regions: [region]);

  test(
    'translation overrides preserve generated text, including empty edits',
    () {
      final edits = PageEdits();
      expect(edits.effectiveTranslation(region), 'Machine');
      edits.setTranslation(region.id, 'Edited');
      expect(edits.effectiveTranslation(region), 'Edited');
      expect(region.translatedText, 'Machine');
      edits.setTranslation(region.id, '');
      expect(edits.effectiveTranslation(region), '');
      expect(edits.hasEdits, isTrue);
      edits.setBox(region.id, const RegionBox(0, 0, 50, 50));
      edits.setTranslation(region.id, null);
      expect(edits.effectiveTranslation(region), 'Machine');
      expect(edits.effectiveBox(region), const RegionBox(0, 0, 50, 50));
      edits.setBox(region.id, null);
      expect(edits.hasEdits, isFalse);
    },
  );

  test('geometry overrides preserve detector box and reset independently', () {
    final edits = PageEdits();
    expect(edits.effectiveBox(region), const RegionBox(10, 20, 30, 40));
    edits.setTranslation(region.id, 'Edited');
    edits.setBox(region.id, const RegionBox(0, 0, 100, 120));
    expect(edits.effectiveBox(region), const RegionBox(0, 0, 100, 120));
    expect(RegionBox.detector(region), const RegionBox(10, 20, 30, 40));
    edits.setBox(region.id, null);
    expect(edits.effectiveBox(region), RegionBox.detector(region));
    expect(edits.effectiveTranslation(region), 'Edited');
  });

  test('geometry validation accepts edges and rejects invalid values', () {
    expect(
      validateRegionBox(const RegionBox(0, 0, 100, 120), analysis),
      isNull,
    );
    expect(
      validateRegionBox(const RegionBox(-1, 0, 1, 1), analysis),
      contains('X'),
    );
    expect(
      validateRegionBox(const RegionBox(0, -1, 1, 1), analysis),
      contains('Y'),
    );
    expect(
      validateRegionBox(const RegionBox(0, 0, 0, 1), analysis),
      contains('Width'),
    );
    expect(
      validateRegionBox(const RegionBox(0, 0, 1, 0), analysis),
      contains('Height'),
    );
    expect(
      validateRegionBox(const RegionBox(99, 0, 2, 1), analysis),
      contains('width'),
    );
    expect(
      validateRegionBox(const RegionBox(0, 119, 1, 2), analysis),
      contains('height'),
    );
    expect(validateRegionBox(const RegionBox(99, 119, 1, 1), analysis), isNull);
  });

  test('successful reanalysis and new image clear single-page edits', () async {
    final controller = ProcessingController(ReplacementRepository(analysis));
    addTearDown(controller.dispose);
    controller.selectImage('one.png', Uint8List.fromList([1]));
    controller.analysis = analysis;
    controller.setTranslation('r', 'Edited');
    await controller.detect();
    expect(controller.edits.hasEdits, isFalse);
    controller.setTranslation('r', 'Again');
    controller.selectImage('two.png', Uint8List.fromList([2]));
    expect(controller.edits.hasEdits, isFalse);
  });
}

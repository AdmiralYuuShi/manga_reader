import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/processing_controller.dart';
import 'package:manga_translator/features/manga_processing/presentation/translation_region_overlay.dart';
import 'package:manga_translator/main.dart';

class FakeRepository extends ProcessingRepository {
  FakeRepository(this.result) : super(ProcessingRemoteDataSource(ApiClient()));
  final Future<PageAnalysis> result;

  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) => result;
}

void main() {
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlqS28AAAAASUVORK5CYII=',
  );

  testWidgets('shows loading and Japanese text for selected region', (
    tester,
  ) async {
    final pending = Completer<PageAnalysis>();
    final controller = ProcessingController(FakeRepository(pending.future));
    controller.selectImage('page.png', Uint8List.fromList(image));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.tap(find.text('Analyze Page'));
    await tester.pump();
    expect(
      find.text('Detecting, recognizing, and translating text...'),
      findsOneWidget,
    );
    pending.complete(
      const PageAnalysis(
        width: 1,
        height: 1,
        regions: [
          DetectedRegion(
            id: 'region_001',
            x: 0,
            y: 0,
            width: 1,
            height: 1,
            sourceLanguage: 'ja',
            targetLanguage: 'id',
            translatedText: 'Hari ini pergi ke sekolah?',
            sourceText: '今日は学校に行くの？',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('region_001')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('translation-text-region_001')),
      findsOneWidget,
    );
    expect(find.text('1 regions detected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('region_001')));
    await tester.pump();
    expect(find.text('Selected Region: region_001'), findsOneWidget);
    expect(find.text('Indonesian:'), findsOneWidget);
    expect(find.text('Hari ini pergi ke sekolah?'), findsNWidgets(2));
    expect(find.text('今日は学校に行くの？'), findsOneWidget);
  });

  testWidgets(
    'overlay controls preserve selection and image changes clear overlays',
    (tester) async {
      final controller = ProcessingController(
        FakeRepository(
          Future.value(
            const PageAnalysis(
              width: 1,
              height: 1,
              regions: [
                DetectedRegion(
                  id: 'region_001',
                  x: 0,
                  y: 0,
                  width: 1,
                  height: 1,
                  sourceText: 'Japanese',
                  translatedText: 'Indonesian',
                ),
              ],
            ),
          ),
        ),
      );
      controller.selectImage('page.png', Uint8List.fromList(image));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.tap(find.text('Analyze Page'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('region_001')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-region_001')),
        findsOneWidget,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-region_001')),
        findsNothing,
      );
      expect(controller.selectedRegionId, 'region_001');
      expect(
        tester
            .widget<TranslationRegionOverlay>(
              find.byType(TranslationRegionOverlay),
            )
            .showDetectionBox,
        isTrue,
      );
      await tester.ensureVisible(find.byType(Switch).last);
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(
        tester
            .widget<TranslationRegionOverlay>(
              find.byType(TranslationRegionOverlay),
            )
            .showDetectionBox,
        isFalse,
      );
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-region_001')),
        findsOneWidget,
      );
      expect(controller.selectedRegionId, 'region_001');
      final rerun = controller.detect();
      expect(controller.analysis, isNull);
      await rerun;
      await tester.pump();
      controller.selectImage('next.png', Uint8List.fromList(image));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-region_001')),
        findsNothing,
      );
      expect(controller.selectedRegionId, isNull);
    },
  );

  testWidgets('shows detection error and permits retry', (tester) async {
    final pending = Completer<PageAnalysis>();
    final controller = ProcessingController(FakeRepository(pending.future));
    controller.selectImage('page.png', Uint8List.fromList(image));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.tap(find.text('Analyze Page'));
    pending.completeError(StateError('failed'));
    await tester.pump();
    expect(find.textContaining('Detection failed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Analyze Page'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('shows empty OCR result after selecting a region', (
    tester,
  ) async {
    final controller = ProcessingController(
      FakeRepository(
        Future.value(
          const PageAnalysis(
            width: 1,
            height: 1,
            regions: [
              DetectedRegion(
                id: 'region_001',
                x: 0,
                y: 0,
                width: 1,
                height: 1,
                sourceText: '',
              ),
            ],
          ),
        ),
      ),
    );
    controller.selectImage('page.png', Uint8List.fromList(image));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.tap(find.text('Analyze Page'));
    await tester.pump();
    controller.selectRegion('region_001');
    await tester.pump();
    expect(find.text('No text recognized'), findsOneWidget);
  });

  testWidgets('shows region OCR error', (tester) async {
    final controller = ProcessingController(
      FakeRepository(
        Future.value(
          const PageAnalysis(
            width: 1,
            height: 1,
            regions: [
              DetectedRegion(
                id: 'region_001',
                x: 0,
                y: 0,
                width: 1,
                height: 1,
                errorCode: 'OCR_FAILED',
              ),
            ],
          ),
        ),
      ),
    );
    controller.selectImage('page.png', Uint8List.fromList(image));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.tap(find.text('Analyze Page'));
    await tester.pump();
    controller.selectRegion('region_001');
    await tester.pump();
    expect(find.textContaining('OCR failed for this region'), findsOneWidget);
  });
}

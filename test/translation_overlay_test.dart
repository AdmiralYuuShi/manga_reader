import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/region_geometry.dart';
import 'package:manga_translator/features/manga_processing/presentation/translation_overlay_layout.dart';
import 'package:manga_translator/features/manga_processing/presentation/translation_region_overlay.dart';

void main() {
  const translated = DetectedRegion(
    id: 'r1',
    x: 100,
    y: 200,
    width: 300,
    height: 400,
    sourceText: 'Japanese',
    translatedText: 'Halo dunia',
  );

  testWidgets('font fitting is bounded and shrinks for long text', (
    tester,
  ) async {
    const style = TextStyle(height: 1.1);
    final shortSize = overlayFontSize(
      'Halo',
      const Size(180, 70),
      style,
      TextDirection.ltr,
    );
    final longSize = overlayFontSize(
      'Ini adalah terjemahan yang sangat panjang dan harus dibungkus '
      'menjadi banyak baris',
      const Size(180, 70),
      style,
      TextDirection.ltr,
    );
    expect(shortSize, maximumOverlayFontSize);
    expect(
      longSize,
      inInclusiveRange(minimumOverlayFontSize, maximumOverlayFontSize),
    );
    expect(longSize, lessThan(shortSize));
    expect(
      overlayFontSize(
        'unfit long text',
        const Size(1, 1),
        style,
        TextDirection.ltr,
      ),
      minimumOverlayFontSize,
    );
  });

  test('portrait and landscape mapping uses the canonical transform', () {
    final portrait = displayRectForRegion(
      translated,
      const Size(1600, 2400),
      const Size(800, 800),
    );
    expect(portrait.left, closeTo(166.67, 0.01));
    expect(portrait.top, closeTo(66.67, 0.01));
    final landscape = displayRectForRegion(
      translated,
      const Size(2400, 1600),
      const Size(800, 800),
    );
    expect(landscape.left, closeTo(33.33, 0.01));
    expect(landscape.top, closeTo(200, 0.01));
    expect(landscape.width, closeTo(100, 0.01));
  });

  Future<void> pumpOverlay(
    WidgetTester tester,
    DetectedRegion region, {
    bool showTranslation = true,
    bool showDetectionBox = true,
    Rect rect = const Rect.fromLTWH(20, 30, 180, 100),
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: Stack(
              children: [
                TranslationRegionOverlay(
                  region: region,
                  rect: rect,
                  imageRect: const Rect.fromLTWH(0, 0, 300, 200),
                  obstacles: const [],
                  selected: false,
                  showTranslation: showTranslation,
                  showDetectionBox: showDetectionBox,
                  onTap: onTap ?? () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('translation renders at the supplied mapped rectangle', (
    tester,
  ) async {
    await pumpOverlay(tester, translated);
    expect(find.byKey(const ValueKey('translation-text-r1')), findsOneWidget);
    final box = find.byKey(const ValueKey('r1'));
    expect(tester.getTopLeft(box), const Offset(20, 30));
    expect(tester.getSize(box), const Size(180, 100));
  });

  testWidgets(
    'expanded area selects the original region while detector box stays put',
    (tester) async {
      var taps = 0;
      const detector = Rect.fromLTWH(80, 80, 80, 34);
      const region = DetectedRegion(
        id: 'expanded',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        sourceText: 'Japanese',
        translatedText: 'Awalnya, itu berasal dari tempat yang jauh.',
      );
      await pumpOverlay(tester, region, rect: detector, onTap: () => taps++);
      final overlay = tester.getRect(find.byKey(const ValueKey('expanded')));
      final debugBox = tester.getRect(
        find.byKey(const ValueKey('detector-box-expanded')),
      );
      expect(overlay.width, greaterThan(detector.width));
      expect(debugBox, detector);
      final outsideOriginal = Offset(overlay.left + 1, detector.center.dy);
      expect(outsideOriginal.dx, lessThan(detector.left));
      await tester.tapAt(outsideOriginal);
      expect(taps, 1);
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('translation-text-expanded')),
      );
      expect(text.overflow, TextOverflow.clip);
      await pumpOverlay(tester, region, rect: detector, showTranslation: false);
      expect(tester.getRect(find.byKey(const ValueKey('expanded'))), detector);
      expect(
        find.byKey(const ValueKey('translation-text-expanded')),
        findsNothing,
      );
      await pumpOverlay(tester, region, rect: detector);
      expect(
        tester.getRect(find.byKey(const ValueKey('expanded'))).width,
        greaterThan(detector.width),
      );
    },
  );

  testWidgets('resizing viewer recalculates translated rectangle', (
    tester,
  ) async {
    const resizeRegion = DetectedRegion(
      id: 'r1',
      x: 100,
      y: 200,
      width: 300,
      height: 400,
      sourceText: 'Japanese',
      translatedText:
          'Awalnya, itu berasal dari tempat yang sangat jauh '
          'dan mereka tidak tahu apa yang akan terjadi.',
    );
    Future<void> pumpViewer(Size canvas) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: canvas.width,
              height: canvas.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Stack(
                    children: [
                      TranslationRegionOverlay(
                        region: resizeRegion,
                        rect: displayRectForRegion(
                          resizeRegion,
                          const Size(1600, 2400),
                          size,
                        ),
                        imageRect: displayRectForImage(
                          const Size(1600, 2400),
                          size,
                        ),
                        obstacles: const [],
                        selected: false,
                        showTranslation: true,
                        showDetectionBox: false,
                        onTap: () {},
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    await pumpViewer(const Size(400, 400));
    final first = tester.getRect(find.byKey(const ValueKey('r1')));
    await pumpViewer(const Size(600, 400));
    final second = tester.getRect(find.byKey(const ValueKey('r1')));
    expect(second.left, greaterThan(first.left));
    expect(second.width, closeTo(first.width, 0.01));
    await pumpViewer(const Size(600, 550));
    final third = tester.getRect(find.byKey(const ValueKey('r1')));
    expect(third.width, greaterThan(second.width));
  });

  testWidgets('missing, empty, and failed translations are hidden', (
    tester,
  ) async {
    for (final region in [
      const DetectedRegion(
        id: 'a',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        sourceText: 'Japanese',
      ),
      const DetectedRegion(
        id: 'b',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        sourceText: 'Japanese',
        translatedText: '  ',
      ),
      const DetectedRegion(
        id: 'c',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        sourceText: 'Japanese',
        translatedText: 'Wrong',
        translationErrorCode: 'TRANSLATION_FAILED',
      ),
      const DetectedRegion(
        id: 'd',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        translatedText: 'Wrong',
        errorCode: 'OCR_FAILED',
      ),
    ]) {
      await pumpOverlay(tester, region);
      expect(
        find.byKey(ValueKey('translation-text-${region.id}')),
        findsNothing,
      );
    }
  });

  testWidgets('tiny and overflowing regions remain selectable', (tester) async {
    var taps = 0;
    await pumpOverlay(
      tester,
      translated,
      rect: const Rect.fromLTWH(20, 30, 20, 20),
      onTap: () => taps++,
    );
    expect(find.byKey(const ValueKey('translation-text-r1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('r1')));
    expect(taps, 1);
    await pumpOverlay(
      tester,
      const DetectedRegion(
        id: 'long',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        sourceText: 'Japanese',
        translatedText:
            'A very long translation that cannot fit in this region',
      ),
      rect: const Rect.fromLTWH(20, 30, 40, 25),
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('translation-text-long')),
    );
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.style!.fontSize, minimumOverlayFontSize);
  });
}

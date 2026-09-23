import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/region_geometry.dart';
import 'package:manga_translator/features/manga_processing/presentation/translation_overlay_layout.dart';
import 'package:manga_translator/features/manga_processing/presentation/translation_region_overlay.dart';
import 'package:manga_translator/features/settings/manga_overlay_font.dart';

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
    Rect? translationRect,
    String? editedTranslatedText,
    MangaOverlayFont overlayFont = MangaOverlayFont.defaultFont,
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
                  translationRect: translationRect,
                  editedTranslatedText: editedTranslatedText,
                  overlayFont: overlayFont,
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

  void expectCompleteFit(WidgetTester tester, String id, String expected) {
    final rendered = tester.widget<Text>(
      find.byKey(ValueKey('translation-text-$id')),
    );
    final bounds = tester.getRect(find.byKey(ValueKey(id)));
    expect(rendered.data, expected);
    expect(rendered.maxLines, isNull);
    expect(rendered.overflow, isNull);
    final painter = TextPainter(
      text: TextSpan(text: expected, style: rendered.style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width - 12);
    expect(painter.height, lessThanOrEqualTo(bounds.height - 12));
    expect(
      painter.computeLineMetrics().every(
        (line) => line.width <= bounds.width - 11.5,
      ),
      isTrue,
    );
    painter.dispose();
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
      final outsideOriginal = Offset(detector.center.dx, overlay.top + 1);
      expect(outsideOriginal.dy, lessThan(detector.top));
      await tester.tapAt(outsideOriginal);
      expect(taps, 1);
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('translation-text-expanded')),
      );
      expect(text.overflow, isNull);
      expect(text.maxLines, isNull);
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
    expect(third, isNot(second));
    expectCompleteFit(tester, 'r1', resizeRegion.translatedText!);
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
    expect(find.byKey(const ValueKey('translation-text-r1')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('r1'))).width,
      greaterThan(20),
    );
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
    expect(text.overflow, isNull);
    expect(text.maxLines, isNull);
    expect(text.style!.fontSize, minimumOverlayFontSize);
  });

  testWidgets('reported Indonesian sentence expands and renders every line', (
    tester,
  ) async {
    const complete = 'Awalnya, itu berasal dari kelemahan hatiku.';
    const region = DetectedRegion(
      id: 'reported',
      x: 100,
      y: 100,
      width: 20,
      height: 40,
      sourceText: 'Japanese',
      translatedText: complete,
    );
    const effective = Rect.fromLTWH(225, 130, 20, 40);
    await pumpOverlay(tester, region, rect: effective);
    final rendered = tester.getRect(find.byKey(const ValueKey('reported')));
    expect(rendered.width, greaterThan(effective.width));
    expect(rendered.height, greaterThan(effective.height));
    expect(rendered.right, lessThanOrEqualTo(300));
    expect(rendered.bottom, lessThanOrEqualTo(200));
    expect(
      tester.getRect(find.byKey(const ValueKey('detector-box-reported'))),
      effective,
    );
    expectCompleteFit(tester, 'reported', complete);
  });

  testWidgets('very small box still shows its complete translation', (
    tester,
  ) async {
    const region = DetectedRegion(
      id: 'small',
      x: 0,
      y: 0,
      width: 2,
      height: 2,
      sourceText: 'Japanese',
      translatedText: 'Halo dunia',
    );
    await pumpOverlay(tester, region, rect: const Rect.fromLTWH(1, 1, 2, 2));
    final expanded = tester.getRect(find.byKey(const ValueKey('small')));
    expect(expanded.width, greaterThan(2));
    expect(expanded.left, greaterThanOrEqualTo(0));
    expect(expanded.top, greaterThanOrEqualTo(0));
    expectCompleteFit(tester, 'small', 'Halo dunia');
  });

  testWidgets('edited translation refits across all bundled fonts', (
    tester,
  ) async {
    const region = DetectedRegion(
      id: 'edited',
      x: 0,
      y: 0,
      width: 15,
      height: 25,
      sourceText: 'Japanese',
      translatedText: 'Awalnya.',
    );
    const effective = Rect.fromLTWH(5, 5, 15, 25);
    const edited = 'Awalnya, itu berasal dari kelemahan hatiku.';
    for (final font in MangaOverlayFont.all) {
      await pumpOverlay(
        tester,
        region,
        rect: effective,
        editedTranslatedText: edited,
        overlayFont: font,
      );
      expectCompleteFit(tester, 'edited', edited);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('translation-text-edited')))
            .style!
            .fontFamily,
        font.family,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('detector-box-edited'))),
        effective,
      );
    }
  });

  testWidgets('impossible page-sized text gives explicit Inspector fallback', (
    tester,
  ) async {
    final complete = List.filled(200, 'Semua kata tetap tersedia.').join(' ');
    final region = DetectedRegion(
      id: 'impossible',
      x: 0,
      y: 0,
      width: 5,
      height: 5,
      sourceText: 'Japanese',
      translatedText: complete,
    );
    await pumpOverlay(tester, region, rect: const Rect.fromLTWH(5, 5, 5, 5));
    expect(
      find.byKey(const ValueKey('translation-text-impossible')),
      findsNothing,
    );
    expect(find.textContaining('Select the region'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('impossible')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(tester.widget<Tooltip>(find.byType(Tooltip).last).message, complete);
  });
}

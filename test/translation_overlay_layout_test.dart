import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/manga_processing/presentation/translation_overlay_layout.dart';

void main() {
  const image = Rect.fromLTWH(0, 0, 400, 400);
  const center = Rect.fromLTWH(100, 100, 100, 80);

  test('expansion is symmetric and bounded without obstacles', () {
    final expanded = expandRectWithinBounds(center, image, 0.2, const [])!;
    expect(expanded, const Rect.fromLTWH(90, 92, 120, 96));
    final maximum = expandRectWithinBounds(center, image, 0.5, const [])!;
    expect(maximum.width, center.width * 1.5);
    expect(maximum.height, center.height * 1.5);
    expect(maximum.contains(center.topLeft), isTrue);
    expect(
      maximum.contains(center.bottomRight - const Offset(0.001, 0.001)),
      isTrue,
    );
    expect(center, const Rect.fromLTWH(100, 100, 100, 80));
  });

  test('image boundaries redistribute growth to the opposite side', () {
    final left = expandRectWithinBounds(
      const Rect.fromLTWH(0, 100, 100, 80),
      image,
      0.2,
      const [],
    )!;
    expect(left.left, 0);
    expect(left.right, 120);
    final right = expandRectWithinBounds(
      const Rect.fromLTWH(300, 100, 100, 80),
      image,
      0.2,
      const [],
    )!;
    expect(right.left, 280);
    expect(right.right, 400);
    final top = expandRectWithinBounds(
      const Rect.fromLTWH(100, 0, 100, 80),
      image,
      0.2,
      const [],
    )!;
    expect(top.top, 0);
    expect(top.bottom, 96);
    final bottom = expandRectWithinBounds(
      const Rect.fromLTWH(100, 320, 100, 80),
      image,
      0.2,
      const [],
    )!;
    expect(bottom.top, 304);
    expect(bottom.bottom, 400);
  });

  test('neighboring detector boxes redirect expansion on each side', () {
    final right = expandRectWithinBounds(center, image, 0.2, const [
      Rect.fromLTWH(200, 110, 40, 40),
    ])!;
    expect(right.left, 80);
    expect(right.right, 200);
    final left = expandRectWithinBounds(center, image, 0.2, const [
      Rect.fromLTWH(60, 110, 40, 40),
    ])!;
    expect(left.left, 100);
    expect(left.right, 220);
    final above = expandRectWithinBounds(center, image, 0.2, const [
      Rect.fromLTWH(120, 60, 40, 40),
    ])!;
    expect(above.top, 100);
    expect(above.bottom, 196);
    final below = expandRectWithinBounds(center, image, 0.2, const [
      Rect.fromLTWH(120, 180, 40, 40),
    ])!;
    expect(below.top, 84);
    expect(below.bottom, 180);
  });

  test('touching edges are allowed, diagonal overlap rejects a candidate', () {
    const diagonal = Rect.fromLTWH(205, 185, 25, 35);
    final ten = expandRectWithinBounds(center, image, 0.1, const [diagonal]);
    final twenty = expandRectWithinBounds(center, image, 0.2, const [diagonal]);
    expect(ten, isNotNull);
    expect(twenty, isNull);
    expect(expandRectWithinBounds(center, image, 0.1, const []), isNotNull);
  });

  testWidgets('original box is kept when full text already fits', (
    tester,
  ) async {
    final layout = findTranslationOverlayLayout(
      text: 'Halo',
      detectorRect: const Rect.fromLTWH(100, 100, 200, 100),
      imageRect: image,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
    );
    expect(layout.rect, const Rect.fromLTWH(100, 100, 200, 100));
    expect(layout.fontSize, maximumOverlayFontSize);
    expect(layout.cannotFit, isFalse);
  });

  testWidgets('measured expansion retains complete text', (tester) async {
    const detector = Rect.fromLTWH(100, 100, 80, 34);
    const text = 'Awalnya, itu berasal dari tempat yang jauh.';
    const style = TextStyle(height: 1.1);
    final layout = findTranslationOverlayLayout(
      text: text,
      detectorRect: detector,
      imageRect: image,
      obstacles: const [],
      style: style,
      direction: TextDirection.ltr,
    );
    expect(layout.rect.width, greaterThan(detector.width));
    expect(layout.cannotFit, isFalse);
    final available = Size(
      layout.rect.width - overlayPadding * 2,
      layout.rect.height - overlayPadding * 2,
    );
    expect(
      fittingOverlayFontSize(text, available, style, TextDirection.ltr),
      layout.fontSize,
    );
    expect(detector, const Rect.fromLTWH(100, 100, 80, 34));
  });

  testWidgets('impossible text is reported without claiming a fit', (
    tester,
  ) async {
    final text = List.filled(
      500,
      'A very long translation that cannot fit inside one manga page.',
    ).join(' ');
    final layout = findTranslationOverlayLayout(
      text: text,
      detectorRect: center,
      imageRect: image,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
    );
    expect(layout.rect, image);
    expect(layout.fontSize, minimumOverlayFontSize);
    expect(layout.cannotFit, isTrue);
  });

  testWidgets('long multi-line text fits after bounded expansion', (
    tester,
  ) async {
    final text = List.filled(
      8,
      'Ini adalah kalimat panjang untuk menguji seluruh hasil terjemahan.',
    ).join(' ');
    const original = Rect.fromLTWH(370, 375, 20, 20);
    final layout = findTranslationOverlayLayout(
      text: text,
      detectorRect: original,
      imageRect: image,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
    );
    expect(layout.cannotFit, isFalse);
    expect(layout.rect.right, lessThanOrEqualTo(image.right));
    expect(layout.rect.bottom, lessThanOrEqualTo(image.bottom));
    expect(layout.rect.left, lessThan(original.left));
    expect(layout.rect.top, lessThan(original.top));
    expect(
      fittingOverlayFontSize(
        text,
        Size(layout.rect.width - 12, layout.rect.height - 12),
        const TextStyle(height: 1.1),
        TextDirection.ltr,
      ),
      isNotNull,
    );
    expect(original, const Rect.fromLTWH(370, 375, 20, 20));
  });

  testWidgets('source-pixel expansion respects display scale', (tester) async {
    const sourceImage = Rect.fromLTWH(0, 0, 1600, 2400);
    const effective = Rect.fromLTWH(1480, 2200, 60, 70);
    const text = 'Awalnya, itu berasal dari kelemahan hatiku.';
    final layout = findTranslationOverlayLayout(
      text: text,
      detectorRect: effective,
      imageRect: sourceImage,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
      displayScale: 0.25,
    );
    expect(layout.cannotFit, isFalse);
    expect(layout.rect.right, lessThanOrEqualTo(sourceImage.right));
    expect(layout.rect.bottom, lessThanOrEqualTo(sourceImage.bottom));
    expect(layout.rect.width, greaterThan(effective.width));
    expect(
      fittingOverlayFontSize(
        text,
        Size(layout.rect.width * 0.25 - 12, layout.rect.height * 0.25 - 12),
        const TextStyle(height: 1.1),
        TextDirection.ltr,
      ),
      isNotNull,
    );
  });

  testWidgets('44x133 vertical source gets a balanced Latin render rect', (
    tester,
  ) async {
    const effective = Rect.fromLTWH(290, 255, 44, 133);
    const text = 'Karena aku ingin menjadi yang terbaik untuk Pak Rito...';
    final layout = findTranslationOverlayLayout(
      text: text,
      detectorRect: effective,
      imageRect: image,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
    );
    expect(layout.cannotFit, isFalse);
    expect(layout.rect.width, greaterThan(effective.width * 1.5));
    expect(layout.rect.width / layout.rect.height, greaterThan(0.4));
    expect(layout.rect.right, lessThanOrEqualTo(image.right));
    expect(layout.rect.bottom, lessThanOrEqualTo(image.bottom));
    expect(
      fittingOverlayFontSize(
        text,
        Size(layout.rect.width - 12, layout.rect.height - 12),
        const TextStyle(height: 1.1),
        TextDirection.ltr,
      ),
      isNotNull,
    );
    expect(effective, const Rect.fromLTWH(290, 255, 44, 133));
  });

  testWidgets('extreme vertical source widens for multi-word translation', (
    tester,
  ) async {
    const effective = Rect.fromLTWH(0, 0, 20, 120);
    const text = 'Aku akan selalu berusaha menjadi lebih baik dari kemarin.';
    final layout = findTranslationOverlayLayout(
      text: text,
      detectorRect: effective,
      imageRect: image,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
    );
    expect(layout.cannotFit, isFalse);
    expect(layout.rect.width, greaterThan(effective.width * 2));
    expect(layout.rect.left, 0);
    expect(layout.rect.top, 0);
    expect(layout.rect.width / layout.rect.height, greaterThan(0.35));
  });

  testWidgets('short text in vertical source keeps effective rect', (
    tester,
  ) async {
    const effective = Rect.fromLTWH(100, 100, 44, 133);
    final layout = findTranslationOverlayLayout(
      text: 'Halo',
      detectorRect: effective,
      imageRect: image,
      obstacles: const [],
      style: const TextStyle(height: 1.1),
      direction: TextDirection.ltr,
    );
    expect(layout.rect, effective);
  });
}

import 'dart:math' as math;

import 'package:flutter/painting.dart';

const double minimumOverlayFontSize = 9;
const double maximumOverlayFontSize = 22;
const double overlayPadding = 4;
const double overlayExpansionStep = 0.10;
const double maximumOverlayExpansionFactor = 0.50;

class TranslationOverlayLayout {
  const TranslationOverlayLayout(this.rect, this.fontSize, this.cannotFit);

  final Rect rect;
  final double fontSize;

  /// Complete text cannot fit anywhere inside the image at the minimum size.
  final bool cannotFit;
}

double _growth(double desired, double beforeSpace, double afterSpace) {
  return math.min(desired, beforeSpace + afterSpace);
}

(double, double) _splitGrowth(
  double desired,
  double beforeSpace,
  double afterSpace,
) {
  final growth = _growth(desired, beforeSpace, afterSpace);
  var before = math.min(growth / 2, beforeSpace);
  var after = math.min(growth / 2, afterSpace);
  var remaining = growth - before - after;
  if (beforeSpace - before >= afterSpace - after) {
    final extra = math.min(remaining, beforeSpace - before);
    before += extra;
    remaining -= extra;
    after += math.min(remaining, afterSpace - after);
  } else {
    final extra = math.min(remaining, afterSpace - after);
    after += extra;
    remaining -= extra;
    before += math.min(remaining, beforeSpace - before);
  }
  return (before, after);
}

bool _overlaps(Rect a, Rect b) =>
    a.left < b.right &&
    a.right > b.left &&
    a.top < b.bottom &&
    a.bottom > b.top;

Rect? expandRectWithinBounds(
  Rect detectorRect,
  Rect imageRect,
  double factor,
  List<Rect> obstacles,
) {
  if (factor == 0) return detectorRect;
  assert(factor >= 0 && factor <= maximumOverlayExpansionFactor);
  var leftFence = imageRect.left;
  var rightFence = imageRect.right;
  var topFence = imageRect.top;
  var bottomFence = imageRect.bottom;
  for (final obstacle in obstacles) {
    final verticalOverlap =
        obstacle.top < detectorRect.bottom &&
        obstacle.bottom > detectorRect.top;
    final horizontalOverlap =
        obstacle.left < detectorRect.right &&
        obstacle.right > detectorRect.left;
    if (verticalOverlap && obstacle.right <= detectorRect.left) {
      leftFence = math.max(leftFence, obstacle.right);
    }
    if (verticalOverlap && obstacle.left >= detectorRect.right) {
      rightFence = math.min(rightFence, obstacle.left);
    }
    if (horizontalOverlap && obstacle.bottom <= detectorRect.top) {
      topFence = math.max(topFence, obstacle.bottom);
    }
    if (horizontalOverlap && obstacle.top >= detectorRect.bottom) {
      bottomFence = math.min(bottomFence, obstacle.top);
    }
  }
  final (left, right) = _splitGrowth(
    detectorRect.width * factor,
    math.max(0, detectorRect.left - leftFence),
    math.max(0, rightFence - detectorRect.right),
  );
  final (top, bottom) = _splitGrowth(
    detectorRect.height * factor,
    math.max(0, detectorRect.top - topFence),
    math.max(0, bottomFence - detectorRect.bottom),
  );
  final candidate = Rect.fromLTRB(
    detectorRect.left - left,
    detectorRect.top - top,
    detectorRect.right + right,
    detectorRect.bottom + bottom,
  );
  if (obstacles.any((obstacle) => _overlaps(candidate, obstacle))) return null;
  return candidate;
}

double? fittingOverlayFontSize(
  String text,
  Size available,
  TextStyle style,
  TextDirection direction, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (available.width <= 0 || available.height <= 0) return null;
  for (
    var size = maximumOverlayFontSize;
    size >= minimumOverlayFontSize;
    size -= 1
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textAlign: TextAlign.center,
      textDirection: direction,
      textScaler: textScaler,
    )..layout(maxWidth: available.width);
    final fits =
        painter.height <= available.height &&
        painter.computeLineMetrics().every(
          (line) => line.width <= available.width + 0.5,
        );
    painter.dispose();
    if (fits) return size;
  }
  return null;
}

({double height, int lines, bool fitsWidth}) _measure(
  String text,
  double width,
  TextStyle style,
  TextDirection direction,
  TextScaler textScaler,
) {
  if (width <= 0) return (height: double.infinity, lines: 0, fitsWidth: false);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: direction,
    textScaler: textScaler,
  )..layout(maxWidth: width);
  final lineMetrics = painter.computeLineMetrics();
  final overwide = lineMetrics.any((line) => line.width > width + 0.5);
  final result = (
    height: painter.height,
    lines: lineMetrics.length,
    fitsWidth: !overwide,
  );
  painter.dispose();
  return result;
}

Rect _expandToSize(Rect base, Rect bounds, double width, double height) {
  final (left, right) = _splitGrowth(
    math.max(0, width - base.width),
    math.max(0, base.left - bounds.left),
    math.max(0, bounds.right - base.right),
  );
  final (top, bottom) = _splitGrowth(
    math.max(0, height - base.height),
    math.max(0, base.top - bounds.top),
    math.max(0, bounds.bottom - base.bottom),
  );
  return Rect.fromLTRB(
    base.left - left,
    base.top - top,
    base.right + right,
    base.bottom + bottom,
  );
}

double overlayFontSize(
  String text,
  Size available,
  TextStyle style,
  TextDirection direction,
) =>
    fittingOverlayFontSize(text, available, style, direction) ??
    minimumOverlayFontSize;

TranslationOverlayLayout findTranslationOverlayLayout({
  required String text,
  required Rect detectorRect,
  required Rect imageRect,
  required List<Rect> obstacles,
  required TextStyle style,
  required TextDirection direction,
  TextScaler textScaler = TextScaler.noScaling,
  double displayScale = 1,
}) {
  assert(displayScale > 0);
  // The border can be 2px when selected. Reserve it even when unselected so
  // selection never causes the final line to be clipped.
  const inset = overlayPadding + 2;
  final originalAvailable = Size(
    math.max(0, detectorRect.width * displayScale - inset * 2),
    math.max(0, detectorRect.height * displayScale - inset * 2),
  );
  final originalFont = fittingOverlayFontSize(
    text,
    originalAvailable,
    style,
    direction,
    textScaler: textScaler,
  );
  if (originalFont != null) {
    final originalMeasure = _measure(
      text,
      originalAvailable.width,
      style.copyWith(fontSize: originalFont),
      direction,
      textScaler,
    );
    // A short translation in a vertical source box should remain compact.
    // Many wrapped lines in that same box deserve a wider Latin layout.
    if (originalMeasure.lines <= 3 ||
        detectorRect.width / detectorRect.height >= 0.6) {
      return TranslationOverlayLayout(detectorRect, originalFont, false);
    }
  }

  final baseArea = math.max(1.0, detectorRect.width * detectorRect.height);
  final targetRatio = math.max(
    0.7,
    math.min(2.5, math.sqrt(detectorRect.width / detectorRect.height)),
  );
  TranslationOverlayLayout? best;
  var bestScore = double.infinity;
  var candidateWidth = detectorRect.width;
  // Geometric width steps explore balanced growth without a 2D brute-force
  // search. The final step always tests the full image width.
  for (var widthStep = 0; widthStep < 13; widthStep++) {
    if (widthStep == 12) candidateWidth = imageRect.width;
    final width = math.min(candidateWidth, imageRect.width);
    final contentWidth = width * displayScale - inset * 2;
    if (contentWidth > 0) {
      for (final fontSize in [22.0, 18.0, 15.0, 12.0, 9.0]) {
        final measured = _measure(
          text,
          contentWidth,
          style.copyWith(fontSize: fontSize),
          direction,
          textScaler,
        );
        if (!measured.fitsWidth) continue;
        final desiredHeight = math.max(
          detectorRect.height,
          (measured.height + inset * 2 + 1) / displayScale,
        );
        if (desiredHeight > imageRect.height + 0.01) continue;
        final candidate = _expandToSize(
          detectorRect,
          imageRect,
          width,
          desiredHeight,
        );
        final actualWidth = candidate.width * displayScale - inset * 2;
        final actualHeight = candidate.height * displayScale - inset * 2;
        if (actualWidth + 0.01 < contentWidth ||
            actualHeight + 0.01 < measured.height) {
          continue;
        }
        final areaPenalty = math.log(
          candidate.width * candidate.height / baseArea,
        );
        final ratio = candidate.width / candidate.height;
        final shapePenalty = (math.log(ratio / targetRatio)).abs();
        final fontPenalty = math.max(0.0, 16 - fontSize) * 0.12;
        final linePenalty = math.max(0, measured.lines - 4) * 0.04;
        final score =
            areaPenalty + shapePenalty * 0.8 + fontPenalty + linePenalty;
        if (score < bestScore) {
          bestScore = score;
          best = TranslationOverlayLayout(candidate, fontSize, false);
        }
      }
    }
    candidateWidth = math.max(
      candidateWidth * 1.4,
      candidateWidth + 12 / displayScale,
    );
  }
  if (best != null) return best;
  final maxContentWidth = imageRect.width * displayScale - inset * 2;
  final maxContentHeight = imageRect.height * displayScale - inset * 2;
  final wholeImageFont = fittingOverlayFontSize(
    text,
    Size(maxContentWidth, maxContentHeight),
    style,
    direction,
    textScaler: textScaler,
  );
  if (wholeImageFont != null) {
    return TranslationOverlayLayout(imageRect, wholeImageFont, false);
  }
  // Mathematically impossible inside the image: report this explicitly in the
  // overlay; the Inspector and tooltip retain the complete translation.
  return TranslationOverlayLayout(imageRect, minimumOverlayFontSize, true);
}

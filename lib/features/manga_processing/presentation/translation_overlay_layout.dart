import 'dart:math' as math;

import 'package:flutter/painting.dart';

const double minimumOverlayFontSize = 9;
const double maximumOverlayFontSize = 22;
const double minimumOverlayWidth = 32;
const double minimumOverlayHeight = 24;
const double overlayPadding = 4;
const double overlayExpansionStep = 0.10;
const double maximumOverlayExpansionFactor = 0.50;

class TranslationOverlayLayout {
  const TranslationOverlayLayout(
    this.rect,
    this.fontSize,
    this.requiresEllipsis,
  );

  final Rect rect;
  final double fontSize;
  final bool requiresEllipsis;
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
    final maxLines = math.max(
      1,
      (available.height / (size * (style.height ?? 1))).floor(),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textAlign: TextAlign.center,
      textDirection: direction,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: available.width);
    final fits =
        !painter.didExceedMaxLines &&
        painter.width <= available.width &&
        painter.height <= available.height;
    painter.dispose();
    if (fits) return size;
  }
  return null;
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
}) {
  var fallback = detectorRect;
  for (
    var step = 0;
    step <= (maximumOverlayExpansionFactor / overlayExpansionStep).round();
    step++
  ) {
    final candidate = expandRectWithinBounds(
      detectorRect,
      imageRect,
      step * overlayExpansionStep,
      obstacles,
    );
    if (candidate == null) continue;
    if (candidate.width * candidate.height > fallback.width * fallback.height) {
      fallback = candidate;
    }
    final available = Size(
      math.max(0, candidate.width - overlayPadding * 2),
      math.max(0, candidate.height - overlayPadding * 2),
    );
    final fontSize = fittingOverlayFontSize(
      text,
      available,
      style,
      direction,
      textScaler: textScaler,
    );
    if (fontSize != null) {
      return TranslationOverlayLayout(candidate, fontSize, false);
    }
  }
  return TranslationOverlayLayout(fallback, minimumOverlayFontSize, true);
}

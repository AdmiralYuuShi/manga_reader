import 'package:flutter/painting.dart';

import '../domain/page_analysis.dart';
import '../domain/region_edits.dart';

Rect displayRectForImage(Size imageSize, Size canvasSize) {
  final fitted = applyBoxFit(BoxFit.contain, imageSize, canvasSize);
  return Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & canvasSize,
  );
}

class ImageViewportTransform {
  ImageViewportTransform(this.imageSize, this.canvasSize)
    : imageRect = displayRectForImage(imageSize, canvasSize);

  final Size imageSize;
  final Size canvasSize;
  final Rect imageRect;

  Offset imageToViewport(Offset point) => Offset(
    imageRect.left + point.dx * imageRect.width / imageSize.width,
    imageRect.top + point.dy * imageRect.height / imageSize.height,
  );

  Offset viewportToImage(Offset point) => Offset(
    (point.dx - imageRect.left) * imageSize.width / imageRect.width,
    (point.dy - imageRect.top) * imageSize.height / imageRect.height,
  );

  Offset deltaViewportToImage(Offset delta) => Offset(
    delta.dx * imageSize.width / imageRect.width,
    delta.dy * imageSize.height / imageRect.height,
  );

  Rect boxToViewport(RegionBox box) {
    final topLeft = imageToViewport(Offset(box.x.toDouble(), box.y.toDouble()));
    final bottomRight = imageToViewport(
      Offset((box.x + box.width).toDouble(), (box.y + box.height).toDouble()),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }
}

Rect displayRectForRegion(
  DetectedRegion region,
  Size imageSize,
  Size canvasSize,
) {
  return displayRectForBox(RegionBox.detector(region), imageSize, canvasSize);
}

Rect displayRectForBox(RegionBox box, Size imageSize, Size canvasSize) {
  return ImageViewportTransform(imageSize, canvasSize).boxToViewport(box);
}

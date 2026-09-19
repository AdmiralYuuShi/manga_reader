import 'package:flutter/painting.dart';

import '../domain/page_analysis.dart';

Rect displayRectForImage(Size imageSize, Size canvasSize) {
  final fitted = applyBoxFit(BoxFit.contain, imageSize, canvasSize);
  return Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & canvasSize,
  );
}

Rect displayRectForRegion(
  DetectedRegion region,
  Size imageSize,
  Size canvasSize,
) {
  final imageRect = displayRectForImage(imageSize, canvasSize);
  final scaleX = imageRect.width / imageSize.width;
  final scaleY = imageRect.height / imageSize.height;
  return Rect.fromLTWH(
    imageRect.left + region.x * scaleX,
    imageRect.top + region.y * scaleY,
    region.width * scaleX,
    region.height * scaleY,
  );
}

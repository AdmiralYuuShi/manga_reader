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

Rect displayRectForRegion(
  DetectedRegion region,
  Size imageSize,
  Size canvasSize,
) {
  return displayRectForBox(RegionBox.detector(region), imageSize, canvasSize);
}

Rect displayRectForBox(RegionBox box, Size imageSize, Size canvasSize) {
  final imageRect = displayRectForImage(imageSize, canvasSize);
  final scaleX = imageRect.width / imageSize.width;
  final scaleY = imageRect.height / imageSize.height;
  return Rect.fromLTWH(
    imageRect.left + box.x * scaleX,
    imageRect.top + box.y * scaleY,
    box.width * scaleX,
    box.height * scaleY,
  );
}

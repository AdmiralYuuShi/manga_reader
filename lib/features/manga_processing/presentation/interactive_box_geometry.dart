import 'package:flutter/painting.dart';

import '../domain/region_edits.dart';

enum ResizeHandle {
  topLeft,
  top,
  topRight,
  left,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

RegionBox moveRegionBox(RegionBox start, Offset delta, Size imageSize) {
  final x = (start.x + delta.dx.round()).clamp(
    0,
    imageSize.width.toInt() - start.width,
  );
  final y = (start.y + delta.dy.round()).clamp(
    0,
    imageSize.height.toInt() - start.height,
  );
  return RegionBox(x, y, start.width, start.height);
}

RegionBox resizeRegionBox(
  RegionBox start,
  ResizeHandle handle,
  Offset delta,
  Size imageSize, {
  int minWidth = 1,
  int minHeight = 1,
}) {
  var left = start.x;
  var top = start.y;
  var right = start.x + start.width;
  var bottom = start.y + start.height;
  final dx = delta.dx.round();
  final dy = delta.dy.round();
  if (switch (handle) {
    ResizeHandle.topLeft ||
    ResizeHandle.left ||
    ResizeHandle.bottomLeft => true,
    _ => false,
  }) {
    left = (left + dx).clamp(0, right - minWidth);
  }
  if (switch (handle) {
    ResizeHandle.topRight ||
    ResizeHandle.right ||
    ResizeHandle.bottomRight => true,
    _ => false,
  }) {
    right = (right + dx).clamp(left + minWidth, imageSize.width.toInt());
  }
  if (switch (handle) {
    ResizeHandle.topLeft || ResizeHandle.top || ResizeHandle.topRight => true,
    _ => false,
  }) {
    top = (top + dy).clamp(0, bottom - minHeight);
  }
  if (switch (handle) {
    ResizeHandle.bottomLeft ||
    ResizeHandle.bottom ||
    ResizeHandle.bottomRight => true,
    _ => false,
  }) {
    bottom = (bottom + dy).clamp(top + minHeight, imageSize.height.toInt());
  }
  return RegionBox(left, top, right - left, bottom - top);
}

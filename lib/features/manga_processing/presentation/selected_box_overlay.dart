import 'package:flutter/material.dart';

import '../domain/region_edits.dart';
import 'interactive_box_geometry.dart';
import 'region_geometry.dart';

/// Editor chrome for the base box. Translation layout may extend beyond it.
class SelectedBoxOverlay extends StatefulWidget {
  const SelectedBoxOverlay({
    super.key,
    required this.box,
    required this.imageSize,
    required this.canvasSize,
    required this.onPreview,
    required this.onCommit,
  });

  final RegionBox box;
  final Size imageSize;
  final Size canvasSize;
  final ValueChanged<RegionBox> onPreview;
  final VoidCallback onCommit;

  @override
  State<SelectedBoxOverlay> createState() => _SelectedBoxOverlayState();
}

class _SelectedBoxOverlayState extends State<SelectedBoxOverlay> {
  RegionBox? _startBox;
  Offset? _startPointer;
  bool _changed = false;

  void _begin(DragStartDetails details) {
    _startBox = widget.box;
    _startPointer = details.globalPosition;
    _changed = false;
  }

  void _update(DragUpdateDetails details, ResizeHandle? handle) {
    final start = _startBox;
    final pointer = _startPointer;
    if (start == null || pointer == null) return;
    final transform = ImageViewportTransform(
      widget.imageSize,
      widget.canvasSize,
    );
    final delta = transform.deltaViewportToImage(
      details.globalPosition - pointer,
    );
    // A 12px display minimum stays usable at different image resolutions.
    final minWidth = (12 * widget.imageSize.width / transform.imageRect.width)
        .ceil()
        .clamp(1, start.width);
    final minHeight =
        (12 * widget.imageSize.height / transform.imageRect.height)
            .ceil()
            .clamp(1, start.height);
    final next = handle == null
        ? moveRegionBox(start, delta, widget.imageSize)
        : resizeRegionBox(
            start,
            handle,
            delta,
            widget.imageSize,
            minWidth: minWidth,
            minHeight: minHeight,
          );
    if (next != widget.box) {
      _changed = true;
      widget.onPreview(next);
    }
  }

  void _finish() {
    if (_changed) widget.onCommit();
    _startBox = null;
    _startPointer = null;
    _changed = false;
  }

  @override
  void dispose() {
    if (_changed) widget.onCommit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = ImageViewportTransform(
      widget.imageSize,
      widget.canvasSize,
    ).boxToViewport(widget.box);
    const hitSize = 24.0;
    const visualSize = 9.0;
    final handles = <(ResizeHandle, Offset, MouseCursor)>[
      (ResizeHandle.topLeft, rect.topLeft, SystemMouseCursors.resizeUpLeft),
      (ResizeHandle.top, rect.topCenter, SystemMouseCursors.resizeUpDown),
      (ResizeHandle.topRight, rect.topRight, SystemMouseCursors.resizeUpRight),
      (ResizeHandle.left, rect.centerLeft, SystemMouseCursors.resizeLeftRight),
      (
        ResizeHandle.right,
        rect.centerRight,
        SystemMouseCursors.resizeLeftRight,
      ),
      (
        ResizeHandle.bottomLeft,
        rect.bottomLeft,
        SystemMouseCursors.resizeUpRight,
      ),
      (ResizeHandle.bottom, rect.bottomCenter, SystemMouseCursors.resizeUpDown),
      (
        ResizeHandle.bottomRight,
        rect.bottomRight,
        SystemMouseCursors.resizeUpLeft,
      ),
    ];
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              key: const ValueKey('move-box'),
              behavior: HitTestBehavior.translucent,
              onPanStart: _begin,
              onPanUpdate: (details) => _update(details, null),
              onPanEnd: (_) => _finish(),
              onPanCancel: _finish,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 3),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amberAccent, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Handles come after the body so they win hit testing at the edges.
        for (final (handle, center, cursor) in handles)
          Positioned(
            left: center.dx - hitSize / 2,
            top: center.dy - hitSize / 2,
            width: hitSize,
            height: hitSize,
            child: MouseRegion(
              cursor: cursor,
              child: GestureDetector(
                key: ValueKey('resize-${handle.name}'),
                behavior: HitTestBehavior.opaque,
                onPanStart: _begin,
                onPanUpdate: (details) => _update(details, handle),
                onPanEnd: (_) => _finish(),
                onPanCancel: _finish,
                child: Center(
                  child: Container(
                    width: visualSize,
                    height: visualSize,
                    decoration: BoxDecoration(
                      color: Colors.amberAccent,
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/manga_processing/domain/region_edits.dart';
import 'package:manga_translator/features/manga_processing/presentation/interactive_box_geometry.dart';
import 'package:manga_translator/features/manga_processing/presentation/region_geometry.dart';

void main() {
  test('viewport mapping round trips with contain and letterboxing', () {
    for (final viewport in [
      const Size(500, 1000),
      const Size(1000, 1000),
      const Size(1000, 300),
    ]) {
      final mapping = ImageViewportTransform(const Size(1000, 2000), viewport);
      const point = Offset(123, 456);
      final restored = mapping.viewportToImage(mapping.imageToViewport(point));
      expect(restored.dx, closeTo(point.dx, 0.0001));
      expect(restored.dy, closeTo(point.dy, 0.0001));
    }
  });

  test('move preserves size and clamps all image edges', () {
    const box = RegionBox(20, 30, 40, 50);
    const image = Size(100, 100);
    expect(
      moveRegionBox(box, const Offset(10, 5), image),
      const RegionBox(30, 35, 40, 50),
    );
    expect(
      moveRegionBox(box, const Offset(-500, -500), image),
      const RegionBox(0, 0, 40, 50),
    );
    expect(
      moveRegionBox(box, const Offset(500, 500), image),
      const RegionBox(60, 50, 40, 50),
    );
  });

  test('all eight handles move only their respective edges', () {
    const box = RegionBox(20, 20, 40, 40);
    const image = Size(100, 100);
    final expected = <ResizeHandle, RegionBox>{
      ResizeHandle.topLeft: const RegionBox(25, 26, 35, 34),
      ResizeHandle.top: const RegionBox(20, 26, 40, 34),
      ResizeHandle.topRight: const RegionBox(20, 26, 45, 34),
      ResizeHandle.left: const RegionBox(25, 20, 35, 40),
      ResizeHandle.right: const RegionBox(20, 20, 45, 40),
      ResizeHandle.bottomLeft: const RegionBox(25, 20, 35, 46),
      ResizeHandle.bottom: const RegionBox(20, 20, 40, 46),
      ResizeHandle.bottomRight: const RegionBox(20, 20, 45, 46),
    };
    for (final entry in expected.entries) {
      expect(
        resizeRegionBox(box, entry.key, const Offset(5, 6), image),
        entry.value,
      );
    }
  });

  test('resize clamps bounds, minimum, and never flips', () {
    const box = RegionBox(20, 20, 40, 40);
    const image = Size(100, 100);
    expect(
      resizeRegionBox(
        box,
        ResizeHandle.topLeft,
        const Offset(-100, -100),
        image,
      ),
      const RegionBox(0, 0, 60, 60),
    );
    expect(
      resizeRegionBox(
        box,
        ResizeHandle.bottomRight,
        const Offset(100, 100),
        image,
      ),
      const RegionBox(20, 20, 80, 80),
    );
    expect(
      resizeRegionBox(
        box,
        ResizeHandle.topLeft,
        const Offset(100, 100),
        image,
        minWidth: 12,
        minHeight: 12,
      ),
      const RegionBox(48, 48, 12, 12),
    );
  });

  test('viewport resize does not mutate original pixel geometry', () {
    const box = RegionBox(20, 30, 40, 50);
    final first = ImageViewportTransform(
      const Size(100, 100),
      const Size(200, 200),
    ).boxToViewport(box);
    final second = ImageViewportTransform(
      const Size(100, 100),
      const Size(400, 400),
    ).boxToViewport(box);
    expect(second.left, first.left * 2);
    expect(box, const RegionBox(20, 30, 40, 50));
  });
}

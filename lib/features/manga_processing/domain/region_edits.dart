import 'page_analysis.dart';

class RegionBox {
  const RegionBox(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;

  static RegionBox detector(DetectedRegion region) =>
      RegionBox(region.x, region.y, region.width, region.height);

  @override
  bool operator ==(Object other) =>
      other is RegionBox &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height;
  @override
  int get hashCode => Object.hash(x, y, width, height);
}

class RegionEdit {
  const RegionEdit({this.translatedText, this.box});
  final String? translatedText;
  final RegionBox? box;
  bool get isEmpty => translatedText == null && box == null;
}

class PageEdits {
  final Map<String, RegionEdit> _regions = {};
  Iterable<MapEntry<String, RegionEdit>> get entries => _regions.entries;
  RegionEdit forRegion(String id) => _regions[id] ?? const RegionEdit();
  bool get hasEdits => _regions.isNotEmpty;

  String? effectiveTranslation(DetectedRegion region) =>
      forRegion(region.id).translatedText ?? region.translatedText;
  RegionBox effectiveBox(DetectedRegion region) =>
      forRegion(region.id).box ?? RegionBox.detector(region);

  void setTranslation(String id, String? text) {
    final old = forRegion(id);
    _set(id, RegionEdit(translatedText: text, box: old.box));
  }

  void setBox(String id, RegionBox? box) {
    final old = forRegion(id);
    _set(id, RegionEdit(translatedText: old.translatedText, box: box));
  }

  void _set(String id, RegionEdit edit) {
    if (edit.isEmpty) {
      _regions.remove(id);
    } else {
      _regions[id] = edit;
    }
  }
}

String? validateRegionBox(RegionBox box, PageAnalysis analysis) {
  if (box.x < 0) return 'X must be at least 0.';
  if (box.y < 0) return 'Y must be at least 0.';
  if (box.width <= 0) return 'Width must be greater than 0.';
  if (box.height <= 0) return 'Height must be greater than 0.';
  if (box.x + box.width > analysis.width) {
    return 'Text box exceeds image width.';
  }
  if (box.y + box.height > analysis.height) {
    return 'Text box exceeds image height.';
  }
  return null;
}

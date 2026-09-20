import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'manga_overlay_font.dart';
import 'appearance_mode.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences({Future<File> Function()? preferenceFile})
    : _preferenceFile = preferenceFile ?? _defaultPreferenceFile;

  final Future<File> Function() _preferenceFile;
  MangaOverlayFont _selected = MangaOverlayFont.defaultFont;
  AppearanceMode _appearance = AppearanceMode.system;
  Future<void> _writes = Future<void>.value();
  bool _fontChangedSinceStart = false;
  bool _appearanceChangedSinceStart = false;

  MangaOverlayFont get overlayFont => _selected;
  AppearanceMode get appearance => _appearance;

  static Future<File> _defaultPreferenceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'overlay_font.json'));
  }

  Future<void> load() async {
    try {
      final file = await _preferenceFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      final values = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final fontId = values['font_id'];
      final appearanceId = values['appearance_mode'];
      if (!_fontChangedSinceStart) {
        _selected = MangaOverlayFont.fromId(fontId is String ? fontId : null);
      }
      if (!_appearanceChangedSinceStart) {
        _appearance = AppearanceMode.fromId(
          appearanceId is String ? appearanceId : null,
        );
      }
      notifyListeners();
    } on Object {
      // A missing, unreadable, or malformed preference leaves the safe default.
    }
  }

  Future<void> selectFont(MangaOverlayFont font) {
    assert(MangaOverlayFont.all.contains(font));
    _fontChangedSinceStart = true;
    _selected = font;
    notifyListeners();
    return _save();
  }

  Future<void> selectAppearance(AppearanceMode mode) {
    _appearanceChangedSinceStart = true;
    _appearance = mode;
    notifyListeners();
    return _save();
  }

  Future<void> _save() {
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final file = await _preferenceFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'font_id': _selected.id,
          'appearance_mode': _appearance.id,
        }),
      );
    });
    return _writes;
  }
}

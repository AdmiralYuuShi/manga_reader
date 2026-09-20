import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'manga_overlay_font.dart';

class OverlayFontPreferences extends ChangeNotifier {
  OverlayFontPreferences({Future<File> Function()? preferenceFile})
    : _preferenceFile = preferenceFile ?? _defaultPreferenceFile;

  final Future<File> Function() _preferenceFile;
  MangaOverlayFont _selected = MangaOverlayFont.defaultFont;
  Future<void> _writes = Future<void>.value();
  bool _changedSinceStart = false;

  MangaOverlayFont get selected => _selected;

  static Future<File> _defaultPreferenceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'overlay_font.json'));
  }

  Future<void> load() async {
    try {
      final file = await _preferenceFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      final id = data is Map<String, dynamic> ? data['font_id'] : null;
      if (_changedSinceStart) return;
      _selected = MangaOverlayFont.fromId(id is String ? id : null);
      notifyListeners();
    } on Object {
      // A missing, unreadable, or malformed preference leaves the safe default.
    }
  }

  Future<void> select(MangaOverlayFont font) {
    assert(MangaOverlayFont.all.contains(font));
    _changedSinceStart = true;
    _selected = font;
    notifyListeners();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final file = await _preferenceFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'font_id': font.id}));
    });
    return _writes;
  }
}

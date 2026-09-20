import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/settings/manga_overlay_font.dart';
import 'package:manga_translator/features/settings/overlay_font_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('catalog has a default and bundled files for every choice', () async {
    expect(MangaOverlayFont.defaultFont, MangaOverlayFont.comicNeue);
    expect(
      MangaOverlayFont.all.map((font) => font.id).toSet().length,
      MangaOverlayFont.all.length,
    );
    for (final font in MangaOverlayFont.all) {
      final bytes = await rootBundle.load(
        'assets/fonts/${font.family}-Regular.ttf',
      );
      expect(bytes.lengthInBytes, greaterThan(1000));
    }
  });

  test('selection persists, reloads, and invalid data falls back', () async {
    final directory = await Directory.systemTemp.createTemp(
      'overlay_font_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}overlay_font.json',
    );
    Future<File> preferenceFile() async => file;
    final first = OverlayFontPreferences(preferenceFile: preferenceFile);
    expect(first.selected, MangaOverlayFont.comicNeue);
    await first.load();
    await first.select(MangaOverlayFont.bangers);
    expect(first.selected, MangaOverlayFont.bangers);
    first.dispose();

    final restored = OverlayFontPreferences(preferenceFile: preferenceFile);
    await restored.load();
    expect(restored.selected, MangaOverlayFont.bangers);
    restored.dispose();

    await file.writeAsString(jsonEncode({'font_id': 'obsolete'}));
    final unknown = OverlayFontPreferences(preferenceFile: preferenceFile);
    await unknown.load();
    expect(unknown.selected, MangaOverlayFont.comicNeue);
    unknown.dispose();

    await file.writeAsString('{broken');
    final corrupt = OverlayFontPreferences(preferenceFile: preferenceFile);
    await corrupt.load();
    expect(corrupt.selected, MangaOverlayFont.comicNeue);
    corrupt.dispose();
  });
}

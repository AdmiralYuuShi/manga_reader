import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/settings/appearance_mode.dart';
import 'package:manga_translator/features/settings/manga_overlay_font.dart';
import 'package:manga_translator/features/settings/app_preferences.dart';

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
    final first = AppPreferences(preferenceFile: preferenceFile);
    expect(first.overlayFont, MangaOverlayFont.comicNeue);
    expect(first.appearance, AppearanceMode.system);
    await first.load();
    await first.selectFont(MangaOverlayFont.bangers);
    await first.selectAppearance(AppearanceMode.dark);
    expect(first.overlayFont, MangaOverlayFont.bangers);
    expect(first.appearance, AppearanceMode.dark);
    first.dispose();

    final restored = AppPreferences(preferenceFile: preferenceFile);
    await restored.load();
    expect(restored.overlayFont, MangaOverlayFont.bangers);
    expect(restored.appearance, AppearanceMode.dark);
    restored.dispose();

    await file.writeAsString(
      jsonEncode({'font_id': 'obsolete', 'appearance_mode': 'unknown'}),
    );
    final unknown = AppPreferences(preferenceFile: preferenceFile);
    await unknown.load();
    expect(unknown.overlayFont, MangaOverlayFont.comicNeue);
    expect(unknown.appearance, AppearanceMode.system);
    unknown.dispose();

    await file.writeAsString('{broken');
    final corrupt = AppPreferences(preferenceFile: preferenceFile);
    await corrupt.load();
    expect(corrupt.overlayFont, MangaOverlayFont.comicNeue);
    expect(corrupt.appearance, AppearanceMode.system);
    corrupt.dispose();
  });

  test('appearance IDs map to Flutter modes', () {
    expect(AppearanceMode.system.themeMode, ThemeMode.system);
    expect(AppearanceMode.light.themeMode, ThemeMode.light);
    expect(AppearanceMode.dark.themeMode, ThemeMode.dark);
  });

  test(
    'existing M16-only preference keeps font and defaults appearance',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'app_preferences_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}overlay_font.json',
      );
      await file.writeAsString(
        jsonEncode({'font_id': MangaOverlayFont.patrickHand.id}),
      );
      final preferences = AppPreferences(preferenceFile: () async => file);
      await preferences.load();
      expect(preferences.overlayFont, MangaOverlayFont.patrickHand);
      expect(preferences.appearance, AppearanceMode.system);
      await preferences.selectAppearance(AppearanceMode.light);
      expect(preferences.overlayFont, MangaOverlayFont.patrickHand);
      preferences.dispose();
    },
  );
}

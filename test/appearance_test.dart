import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/processing_controller.dart';
import 'package:manga_translator/features/settings/appearance_mode.dart';
import 'package:manga_translator/features/settings/app_preferences.dart';
import 'package:manga_translator/features/settings/manga_overlay_font.dart';
import 'package:manga_translator/main.dart';

class _IdleRepository extends ProcessingRepository {
  _IdleRepository() : super(ProcessingRemoteDataSource(ApiClient()));

  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) =>
      throw StateError('Appearance change must not process the page');
}

void main() {
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP8//8/AwMDEwMYAAAkBgMBXaJOiAAAAABJRU5ErkJggg==',
  );
  const analysis = PageAnalysis(
    width: 100,
    height: 100,
    regions: [
      DetectedRegion(
        id: 'r1',
        x: 10,
        y: 10,
        width: 70,
        height: 70,
        sourceText: 'Japanese',
        translatedText: 'Translation',
      ),
    ],
  );

  testWidgets('System follows platform brightness changes', (tester) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final preferences = AppPreferences();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(
      MangaTranslatorApp(
        preferences: preferences,
        home: Builder(
          builder: (context) => Text(Theme.of(context).brightness.name),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });

  testWidgets('restored appearance applies on the first app frame', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('appearance_start_'),
    );
    final file = File(
      '${directory!.path}${Platform.pathSeparator}overlay_font.json',
    );
    final first = AppPreferences(preferenceFile: () async => file);
    await tester.runAsync(() => first.selectAppearance(AppearanceMode.dark));
    first.dispose();
    final restored = AppPreferences(preferenceFile: () async => file);
    await tester.runAsync(restored.load);
    await tester.pumpWidget(
      MangaTranslatorApp(
        preferences: restored,
        home: Builder(
          builder: (context) => Text(Theme.of(context).brightness.name),
        ),
      ),
    );
    expect(find.text('dark'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    restored.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  testWidgets(
    'Settings switches chrome without changing image, font, or region state',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(620, 700);
      tester.view.devicePixelRatio = 1;
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('appearance_test_'),
      );
      final file = File(
        '${directory!.path}${Platform.pathSeparator}overlay_font.json',
      );
      final preferences = AppPreferences(preferenceFile: () async => file);
      await tester.runAsync(
        () => preferences.selectFont(MangaOverlayFont.bangers),
      );
      final controller = ProcessingController(_IdleRepository());
      controller.selectImage('page.png', image);
      controller.analysis = analysis;
      controller.selectRegion('r1');
      await tester.pumpWidget(
        MangaTranslatorApp(
          preferences: preferences,
          home: HomePage(controller: controller, preferences: preferences),
        ),
      );
      await tester.pump();

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      Image mangaImage() => tester.widget<Image>(find.byType(Image).first);
      expect(app().themeMode, ThemeMode.system);
      expect(mangaImage().color, isNull);
      expect(mangaImage().colorBlendMode, isNull);
      expect((mangaImage().image as MemoryImage).bytes, image);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      for (final (label, expected, brightness) in [
        ('Dark', ThemeMode.dark, Brightness.dark),
        ('Light', ThemeMode.light, Brightness.light),
        ('System', ThemeMode.system, Brightness.light),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(app().themeMode, expected);
        expect(
          Theme.of(tester.element(find.byType(HomePage))).brightness,
          brightness,
        );
        expect((mangaImage().image as MemoryImage).bytes, image);
        expect(mangaImage().color, isNull);
        expect(mangaImage().colorBlendMode, isNull);
        expect(controller.analysis, same(analysis));
        expect(controller.selectedRegionId, 'r1');
        expect(controller.edits.hasEdits, isFalse);
        expect(preferences.overlayFont, MangaOverlayFont.bangers);
        expect(
          find.byKey(const ValueKey('translation-text-r1')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('move-box')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      preferences.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}

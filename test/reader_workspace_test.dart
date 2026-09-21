import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/chapter/source_hierarchy.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/manga_viewer_workspace.dart';
import 'package:manga_translator/features/manga_processing/presentation/processing_controller.dart';
import 'package:manga_translator/features/settings/manga_overlay_font.dart';
import 'package:manga_translator/features/settings/app_preferences.dart';
import 'package:manga_translator/main.dart';

class IdleRepository extends ProcessingRepository {
  IdleRepository() : super(ProcessingRemoteDataSource(ApiClient()));

  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) =>
      throw StateError('No processing request expected');
}

void main() {
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlqS28AAAAASUVORK5CYII=',
  );
  const analysis = PageAnalysis(
    width: 100,
    height: 100,
    regions: [
      DetectedRegion(
        id: 'region',
        x: 10,
        y: 10,
        width: 60,
        height: 60,
        sourceText: 'Japanese',
        translatedText: 'Machine',
      ),
    ],
  );

  testWidgets('empty workspace and compact chrome render in light and dark', (
    tester,
  ) async {
    final controller = ProcessingController(IdleRepository());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (brightness, size) in [
      (Brightness.light, const Size(1200, 800)),
      (Brightness.dark, const Size(620, 700)),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: brightness,
            ),
          ),
          home: HomePage(controller: controller),
        ),
      );
      await tester.pump();
      expect(find.text('Open a manga image to begin'), findsOneWidget);
      expect(
        find.text('Select a text region to inspect or edit it.'),
        findsOneWidget,
      );
      expect(find.text('Inspector'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'single image inspector shares effective box and preserves image bytes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ProcessingController(IdleRepository());
      controller.selectImage('page.png', image);
      controller.analysis = analysis;
      controller.selectRegion('region');
      await tester.pumpWidget(
        MaterialApp(home: HomePage(controller: controller)),
      );
      await tester.pump();
      expect(find.byType(MangaViewerWorkspace), findsOneWidget);
      expect(find.byKey(const ValueKey('move-box')), findsOneWidget);
      expect(find.byKey(const ValueKey('resize-topLeft')), findsOneWidget);
      expect(find.text('Selected Region: region'), findsOneWidget);
      final memory =
          tester.widget<Image>(find.byType(Image).first).image as MemoryImage;
      expect(memory.bytes, image);

      await tester.enterText(find.byKey(const ValueKey('box-field-0')), '20');
      await tester.ensureVisible(find.text('Apply Box'));
      await tester.tap(find.text('Apply Box'));
      await tester.pump();
      expect(controller.edits.forRegion('region').box!.x, 20);
      expect(find.byKey(const ValueKey('move-box')), findsOneWidget);
      expect(find.text('Edited'), findsWidgets);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(620, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
          ),
          home: HomePage(controller: controller),
        ),
      );
      await tester.pump();
      final darkImage =
          tester.widget<Image>(find.byType(Image).first).image as MemoryImage;
      expect(darkImage.bytes, image);
      expect(find.byKey(const ValueKey('box-field-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('chapter navigation clears page-scoped inspector selection', (
    tester,
  ) async {
    final folder = await tester.runAsync(
      () => Directory.systemTemp.createTemp('reader_workspace_'),
    );
    final first = File('${folder!.path}${Platform.pathSeparator}1.png');
    final second = File('${folder.path}${Platform.pathSeparator}2.png');
    await tester.runAsync(() async {
      await first.writeAsBytes(image);
      await second.writeAsBytes(image);
    });
    final chapter = ChapterController(IdleRepository());
    chapter.directoryPath = folder.path;
    chapter.pages = [ChapterPage(first), ChapterPage(second)];
    chapter.pages.first
      ..status = ChapterPageStatus.completed
      ..analysis = analysis;
    chapter.selectRegion('region');
    await tester.pumpWidget(
      MaterialApp(home: HomePage(chapterController: chapter)),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chapter-page-list')), findsOneWidget);
    expect(find.text('Selected Region: region'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chapter-page-1')));
    await tester.pump();
    expect(chapter.selectedPageIndex, 1);
    expect(chapter.selectedRegionId, isNull);
    expect(
      find.text('Select a text region to inspect or edit it.'),
      findsOneWidget,
    );
    expect(find.text('Page 2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    chapter.dispose();
    await tester.runAsync(() => folder.delete(recursive: true));
  });

  testWidgets(
    'global font selector updates single and chapter overlays without changing analysis',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(620, 700);
      tester.view.devicePixelRatio = 1;
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('font_workspace_'),
      );
      final preferenceFile = File(
        '${directory!.path}${Platform.pathSeparator}font.json',
      );
      final preferences = AppPreferences(
        preferenceFile: () async => preferenceFile,
      );
      final controller = ProcessingController(IdleRepository());
      controller.selectImage('page.png', image);
      controller.analysis = analysis;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(controller: controller, preferences: preferences),
        ),
      );
      await tester.pump();
      Text overlayText() => tester.widget<Text>(
        find.byKey(const ValueKey('translation-text-region')),
      );
      expect(
        overlayText().style!.fontFamily,
        MangaOverlayFont.comicNeue.family,
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Manga overlay font'), findsOneWidget);
      expect(find.byKey(const ValueKey('font-option-bangers')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('font-option-bangers')));
      await tester.pumpAndSettle();
      expect(overlayText().style!.fontFamily, MangaOverlayFont.bangers.family);
      expect(controller.analysis, same(analysis));
      expect(controller.edits.hasEdits, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();

      final pageFile = File(
        '${directory.path}${Platform.pathSeparator}page.png',
      );
      final chapter = ChapterController(IdleRepository());
      chapter.directoryPath = directory.path;
      chapter.pages = [ChapterPage(pageFile)];
      chapter.pages.first
        ..status = ChapterPageStatus.completed
        ..analysis = analysis;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(chapterController: chapter, preferences: preferences),
        ),
      );
      await tester.pump();
      expect(overlayText().style!.fontFamily, MangaOverlayFont.bangers.family);
      expect(chapter.pages.first.analysis, same(analysis));
      expect(chapter.pages.first.edits.hasEdits, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      chapter.dispose();
      imageCache.clear();
      imageCache.clearLiveImages();
      preferences.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );

  testWidgets(
    'hierarchical navigation switches active chapter and clears region selection',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('reader_tree_'),
      );
      for (final name in ['Chapter 1', 'Chapter 2']) {
        await tester.runAsync(() async {
          final file = File(
            '${root!.path}${Platform.pathSeparator}$name${Platform.pathSeparator}1.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes([1]);
        });
      }
      final hierarchy = (await tester.runAsync(
        () => SourceHierarchy.discover(root!.path),
      ))!;
      final chapter = (await tester.runAsync(() async {
        final value = ChapterController(IdleRepository());
        await value.open(hierarchy.chapters.first.path);
        return value;
      }))!;
      await tester.runAsync(
        () => File(chapter.pages.single.file.path).delete(),
      );
      chapter.pages.single
        ..status = ChapterPageStatus.completed
        ..analysis = analysis;
      chapter.selectRegion('region');
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            chapterController: chapter,
            sourceHierarchy: hierarchy,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('chapter-folder-list')), findsOneWidget);
      expect(find.text('Selected Region: region'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chapter-folder-Chapter 2')));
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 50 && chapter.directoryPath != hierarchy.chapters.last.path;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (chapter.directoryPath == hierarchy.chapters.last.path) {
          await chapter.pages.single.file.delete();
        }
      });
      await tester.pump();
      expect(chapter.directoryPath, hierarchy.chapters.last.path);
      expect(chapter.selectedRegionId, isNull);
      expect(chapter.pages.single.name, '1.png');
      expect(chapter.pages.single.status, ChapterPageStatus.pending);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(620, 700);
      await tester.pump();
      expect(find.byTooltip('Choose Chapter'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      chapter.dispose();
      imageCache.clear();
      imageCache.clearLiveImages();
      // Windows may briefly retain an image handle after the widget is removed.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await root!.delete(recursive: true);
      });
    },
  );
}

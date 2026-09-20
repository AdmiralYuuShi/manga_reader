import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/main.dart';

import 'chapter_test.dart' show QueueRepository;

void main() {
  testWidgets(
    'editor follows chapter page selection and keeps page-local edits',
    (tester) async {
      final folder = await tester.runAsync(
        () => Directory.systemTemp.createTemp('manga_editor_chapter_'),
      );
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlqS28AAAAASUVORK5CYII=',
      );
      final first = File('${folder!.path}${Platform.pathSeparator}1.png');
      final second = File('${folder.path}${Platform.pathSeparator}2.png');
      await tester.runAsync(() async {
        await first.writeAsBytes(bytes);
        await second.writeAsBytes(bytes);
      });
      const analysis = PageAnalysis(
        width: 100,
        height: 100,
        regions: [
          DetectedRegion(
            id: 'shared',
            x: 10,
            y: 10,
            width: 60,
            height: 60,
            sourceText: '日本語',
            translatedText: 'Machine',
          ),
        ],
      );
      final chapter = ChapterController(QueueRepository());
      chapter.directoryPath = folder.path;
      chapter.pages = [ChapterPage(first), ChapterPage(second)];
      for (final page in chapter.pages) {
        page.status = ChapterPageStatus.completed;
        page.analysis = analysis;
      }
      chapter.selectRegion('shared');
      await tester.pumpWidget(
        MaterialApp(home: HomePage(chapterController: chapter)),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('translation-editor')),
        'Page one',
      );
      await tester.pump();
      expect(
        chapter.pages[0].edits.effectiveTranslation(analysis.regions.first),
        'Page one',
      );
      chapter.selectPage(1);
      chapter.selectRegion('shared');
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('translation-editor')))
            .controller!
            .text,
        'Machine',
      );
      await tester.enterText(
        find.byKey(const ValueKey('translation-editor')),
        'Page two',
      );
      await tester.pump();
      chapter.selectPage(0);
      chapter.selectRegion('shared');
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('translation-editor')))
            .controller!
            .text,
        'Page one',
      );
      expect(
        chapter.pages[1].edits.effectiveTranslation(analysis.regions.first),
        'Page two',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      chapter.dispose();
      await tester.runAsync(() => folder.delete(recursive: true));
    },
  );

  testWidgets(
    'chapter viewer switches overlays and clears them on pending pages',
    (tester) async {
      final folder = await tester.runAsync(
        () => Directory.systemTemp.createTemp('manga_viewer_test_'),
      );
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlqS28AAAAASUVORK5CYII=',
      );
      final firstFile = File('${folder!.path}${Platform.pathSeparator}1.png');
      final secondFile = File('${folder.path}${Platform.pathSeparator}2.png');
      await tester.runAsync(() async {
        await firstFile.writeAsBytes(bytes);
        await secondFile.writeAsBytes(bytes);
      });
      final chapter = ChapterController(QueueRepository());
      chapter.directoryPath = folder.path;
      chapter.pages = [ChapterPage(firstFile), ChapterPage(secondFile)];
      chapter.pages.first
        ..status = ChapterPageStatus.completed
        ..analysis = const PageAnalysis(
          width: 1,
          height: 1,
          regions: [
            DetectedRegion(
              id: 'first',
              x: 0,
              y: 0,
              width: 1,
              height: 1,
              sourceText: '日本語',
              translatedText: 'Indonesian one',
            ),
          ],
        );
      await tester.pumpWidget(
        MaterialApp(home: HomePage(chapterController: chapter)),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-first')),
        findsOneWidget,
      );
      expect(find.text('Page 1 / 2'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-first')),
        findsNothing,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.byTooltip('Next Page'));
      await tester.pump();
      expect(find.text('Page 2 / 2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('translation-text-first')),
        findsNothing,
      );
      chapter.pages[1].status = ChapterPageStatus.failed;
      chapter.pages[1].error = 'Unreadable image';
      chapter.selectPage(1);
      await tester.pump();
      expect(find.textContaining('Unreadable image'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('translation-text-first')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Previous Page'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('translation-text-first')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      chapter.dispose();
      await tester.runAsync(() => folder.delete(recursive: true));
    },
  );
}

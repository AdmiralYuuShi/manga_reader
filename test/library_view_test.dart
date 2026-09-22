import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/chapter/chapter_persistence.dart';
import 'package:manga_translator/features/chapter/source_hierarchy.dart';
import 'package:manga_translator/features/library/library_controller.dart';
import 'package:manga_translator/features/library/library_index_repository.dart';
import 'package:manga_translator/features/library/library_view.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets(
    'empty library offers Add/Open Folder in narrow light and dark themes',
    (tester) async {
      final storage = await tester.runAsync(
        () => Directory.systemTemp.createTemp('library_ui_empty_'),
      );
      final controller = (await tester.runAsync(
        () async => LibraryController(
          index: LibraryIndexRepository(supportDirectory: () async => storage!),
          chapterPersistence: () async =>
              ChapterPersistenceRepository(storage!),
        ),
      ))!;
      await tester.runAsync(controller.load);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(620, 700);
      tester.view.devicePixelRatio = 1;
      var adds = 0;
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: brightness,
              ),
            ),
            home: Scaffold(
              body: LibraryView(
                controller: controller,
                onAddFolder: () => adds++,
                onOpenRoot: (_) {},
                onOpenPage: (_, _, _) {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text('Open a manga folder to add it to your library.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Add / Open Folder'));
        expect(tester.takeException(), isNull);
      }
      expect(adds, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(() => storage!.delete(recursive: true));
    },
  );

  testWidgets(
    'tree expands to pages, opens selection, refreshes, and removes only index entry',
    (tester) async {
      final storage = await tester.runAsync(
        () => Directory.systemTemp.createTemp('library_ui_storage_'),
      );
      final source = await tester.runAsync(
        () => Directory.systemTemp.createTemp('library_ui_source_'),
      );
      final page = File(p.join(source!.path, 'Volume 1', 'Chapter 1', '1.jpg'));
      await tester.runAsync(() async {
        await page.parent.create(recursive: true);
        await page.writeAsBytes([1]);
      });
      final controller = (await tester.runAsync(
        () async => LibraryController(
          index: LibraryIndexRepository(supportDirectory: () async => storage!),
          chapterPersistence: () async =>
              ChapterPersistenceRepository(storage!),
        ),
      ))!;
      final hierarchy = (await tester.runAsync(
        () => SourceHierarchy.discover(source.path),
      ))!;
      final root = (await tester.runAsync(
        () => controller.register(hierarchy),
      ))!;
      await tester.runAsync(
        () => controller.refresh(root.id, discovered: hierarchy),
      );
      String? openedPage;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryView(
              controller: controller,
              onAddFolder: () {},
              onOpenRoot: (_) {},
              onOpenPage: (root, folder, name) =>
                  openedPage = '${folder.relativePath}/$name',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Volume 1'), findsOneWidget);
      expect(find.text('Chapter 1'), findsNothing);
      await tester.tap(find.text('Volume 1'));
      await tester.pump();
      expect(find.text('Chapter 1'), findsOneWidget);
      await tester.tap(find.text('Chapter 1'));
      await tester.pump();
      expect(find.text('1.jpg'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      await tester.tap(find.text('1.jpg'));
      expect(openedPage, '${p.join('Volume 1', 'Chapter 1')}/1.jpg');
      await tester.tap(find.byTooltip('Actions for ${root.name}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Library'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Library?'), findsOneWidget);
      await tester.tap(find.text('Remove').last);
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && controller.roots.isNotEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(controller.roots, isEmpty);
      expect(await tester.runAsync(page.exists), isTrue);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(() async {
        await source.delete(recursive: true);
        await storage!.delete(recursive: true);
      });
    },
  );
}

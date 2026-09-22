import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/chapter/chapter_persistence.dart';
import 'package:manga_translator/features/chapter/source_hierarchy.dart';
import 'package:manga_translator/features/library/library_controller.dart';
import 'package:manga_translator/features/library/library_index_repository.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/main.dart';
import 'package:path/path.dart' as p;

class _IdleRepository extends ProcessingRepository {
  _IdleRepository() : super(ProcessingRemoteDataSource(ApiClient()));

  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) =>
      throw StateError('Browsing the library must not process pages.');
}

void main() {
  testWidgets('library page opens the selected chapter and returns to library', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final storage = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_reader_storage_'),
    ))!;
    final source = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('library_reader_source_'),
    ))!;
    final page = File(p.join(source.path, 'Volume 1', 'Chapter 2', '2.png'));
    await tester.runAsync(() async {
      await page.parent.create(recursive: true);
      await page.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlqS28AAAAASUVORK5CYII=',
        ),
      );
    });
    final setup = (await tester.runAsync(() async {
      final library = LibraryController(
        index: LibraryIndexRepository(supportDirectory: () async => storage),
        chapterPersistence: () async => ChapterPersistenceRepository(storage),
      );
      final hierarchy = await SourceHierarchy.discover(source.path);
      final root = await library.register(hierarchy);
      await library.refresh(root.id, discovered: hierarchy);
      final chapter = ChapterController(
        _IdleRepository(),
        persistence: ChapterPersistenceRepository(storage),
      );
      return (library, chapter);
    }))!;
    final (library, chapter) = setup;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(libraryController: library, chapterController: chapter),
      ),
    );
    await tester.tap(find.text('Library').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Volume 1'), findsOneWidget);
    await tester.tap(find.text('Volume 1'));
    await tester.pump();
    await tester.tap(find.text('Chapter 2'));
    await tester.pump();
    await tester.tap(find.text('2.png'));
    for (var i = 0; i < 50 && chapter.directoryPath != page.parent.path; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.runAsync(page.delete);
    await tester.pumpAndSettle();
    expect(chapter.directoryPath, page.parent.path);
    expect(chapter.selectedPage?.name, '2.png');
    for (var i = 0; i < 50 && find.text('Library').evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.text('Library'), findsOneWidget);
    await tester.tap(find.text('Library').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Translation Library'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    library.dispose();
    chapter.dispose();
    imageCache.clear();
    imageCache.clearLiveImages();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await source.delete(recursive: true);
      await storage.delete(recursive: true);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/chapter/chapter_persistence.dart';
import 'package:manga_translator/features/chapter/source_hierarchy.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/domain/region_edits.dart';
import 'package:path/path.dart' as p;

class _CountingRepository extends ProcessingRepository {
  _CountingRepository() : super(ProcessingRemoteDataSource(ApiClient()));
  int calls = 0;
  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) async {
    calls++;
    return const PageAnalysis(
      width: 100,
      height: 100,
      regions: [
        DetectedRegion(
          id: 'r',
          x: 1,
          y: 1,
          width: 20,
          height: 20,
          sourceText: 'Japanese',
          translatedText: 'Machine',
        ),
      ],
    );
  }
}

Future<void> addPage(Directory root, String relativePath) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes([1, 2, 3]);
}

void main() {
  test(
    'simple chapter keeps natural page order and supported case-insensitive formats',
    () async {
      final root = await Directory.systemTemp.createTemp('source_simple_');
      addTearDown(() => root.delete(recursive: true));
      for (final name in ['10.WEBP', '2.png', '1.JPG', 'notes.txt']) {
        await addPage(root, name);
      }
      final hierarchy = await SourceHierarchy.discover(root.path);
      expect(hierarchy.chapters, hasLength(1));
      expect(hierarchy.chapters.single.pageNames, [
        '1.JPG',
        '2.png',
        '10.WEBP',
      ]);
      expect(hierarchy.chapters.single.path, root.path);
    },
  );

  test(
    'flat manga root sorts sibling chapters without flattening pages',
    () async {
      final root = await Directory.systemTemp.createTemp('source_flat_');
      addTearDown(() => root.delete(recursive: true));
      for (final path in [
        'Chapter 10/1.jpg',
        'Chapter 2/1.jpg',
        'Chapter 1/1.jpg',
      ]) {
        await addPage(root, path);
      }
      final hierarchy = await SourceHierarchy.discover(root.path);
      expect(hierarchy.chapters.map((node) => node.name), [
        'Chapter 1',
        'Chapter 2',
        'Chapter 10',
      ]);
      expect(
        hierarchy.chapters.every((node) => node.pageNames.length == 1),
        isTrue,
      );
    },
  );

  test(
    'nested volumes retain separate naturally ordered chapters and ignore empties',
    () async {
      final root = await Directory.systemTemp.createTemp('source_nested_');
      addTearDown(() => root.delete(recursive: true));
      for (final path in [
        'Volume 1/Chapter 10/1.jpg',
        'Volume 1/Chapter 2/1.jpg',
        'Volume 1/Chapter 1/1.jpg',
        'Volume 2/Chapter 1/1.jpg',
        'Empty/notes.txt',
      ]) {
        await addPage(root, path);
      }
      final hierarchy = await SourceHierarchy.discover(root.path);
      expect(hierarchy.root.children.map((node) => node.name), [
        'Volume 1',
        'Volume 2',
      ]);
      expect(hierarchy.root.children.first.isChapter, isFalse);
      expect(hierarchy.chapters.map((node) => node.relativePath), [
        p.join('Volume 1', 'Chapter 1'),
        p.join('Volume 1', 'Chapter 2'),
        p.join('Volume 1', 'Chapter 10'),
        p.join('Volume 2', 'Chapter 1'),
      ]);
      expect(
        chapterStorageId(hierarchy.chapters.first.path),
        isNot(chapterStorageId(hierarchy.chapters.last.path)),
      );
    },
  );

  test(
    'mixed root keeps its direct pages separate from child chapters',
    () async {
      final root = await Directory.systemTemp.createTemp('source_mixed_');
      addTearDown(() => root.delete(recursive: true));
      for (final path in ['2.jpg', '1.jpg', 'Chapter 2/1.jpg']) {
        await addPage(root, path);
      }
      final hierarchy = await SourceHierarchy.discover(root.path);
      expect(hierarchy.chapters, hasLength(2));
      expect(hierarchy.chapters.first.relativePath, '');
      expect(hierarchy.chapters.first.pageNames, ['1.jpg', '2.jpg']);
      expect(hierarchy.chapters.last.relativePath, 'Chapter 2');
      expect(hierarchy.chapters.last.pageNames, ['1.jpg']);
    },
  );

  test('missing selected root reports a filesystem error', () async {
    final root = await Directory.systemTemp.createTemp('source_missing_');
    await root.delete();
    await expectLater(
      SourceHierarchy.discover(root.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'old simple cache and separate nested caches restore edits across switches',
    () async {
      final root = await Directory.systemTemp.createTemp('source_cache_');
      final storage = await Directory.systemTemp.createTemp(
        'source_cache_storage_',
      );
      addTearDown(() async {
        await root.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      for (final path in [
        'Chapter 1/1.jpg',
        'Volume 1/Chapter 1/1.jpg',
        'Volume 2/Chapter 1/1.jpg',
      ]) {
        await addPage(root, path);
      }
      final service = ChapterPersistenceRepository(storage);
      final simple = p.join(root.path, 'Chapter 1');
      final old = ChapterController(
        _CountingRepository(),
        persistence: service,
      );
      await old.open(simple);
      await old.processPending();
      old.setTranslation('r', 'Old edit');
      old.setBox('r', const RegionBox(2, 2, 25, 25));
      await old.flushSaves();
      old.dispose();
      final oldFile = service.chapterFile(simple).path;

      final hierarchy = await SourceHierarchy.discover(root.path);
      final nested = hierarchy.chapters
          .where((node) => node.relativePath.contains('Volume'))
          .toList();
      final repo = _CountingRepository();
      final active = ChapterController(repo, persistence: service);
      await active.open(nested[0].path);
      await active.processPending();
      active.setTranslation('r', 'Volume one');
      await active.open(nested[1].path);
      expect(active.selectedRegionId, isNull);
      expect(active.pages.single.status, ChapterPageStatus.pending);
      await active.processPending();
      active.setTranslation('r', 'Volume two');
      await active.flushSaves();
      active.dispose();
      expect(
        service.chapterFile(nested[0].path).path,
        isNot(service.chapterFile(nested[1].path).path),
      );
      expect(service.chapterFile(simple).path, oldFile);

      final restoredRepo = _CountingRepository();
      final restored = ChapterController(restoredRepo, persistence: service);
      await restored.open(simple);
      expect(restored.pages.single.restoredFromCache, isTrue);
      expect(
        restored.pages.single.edits.forRegion('r').translatedText,
        'Old edit',
      );
      expect(
        restored.pages.single.edits.forRegion('r').box,
        const RegionBox(2, 2, 25, 25),
      );
      for (final (index, text) in [(0, 'Volume one'), (1, 'Volume two')]) {
        await restored.open(nested[index].path);
        expect(restored.pages.single.restoredFromCache, isTrue);
        expect(restored.pages.single.edits.forRegion('r').translatedText, text);
      }
      expect(restoredRepo.calls, 0);
      await restored.flushSaves();
      restored.dispose();
    },
  );
}

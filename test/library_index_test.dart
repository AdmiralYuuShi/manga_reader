import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/chapter/chapter_persistence.dart';
import 'package:manga_translator/features/chapter/source_hierarchy.dart';
import 'package:manga_translator/features/library/library_controller.dart';
import 'package:manga_translator/features/library/library_index_repository.dart';
import 'package:manga_translator/features/library/library_model.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/domain/region_edits.dart';
import 'package:path/path.dart' as p;

Future<File> _page(Directory root, String relative) async {
  final file = File(p.join(root.path, relative));
  await file.parent.create(recursive: true);
  await file.writeAsBytes([1, 2, 3]);
  return file;
}

const _analysis = PageAnalysis(
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

Future<void> _cache(
  ChapterPersistenceRepository service,
  File file, {
  String? translation,
  RegionBox? box,
}) async {
  final edits = PageEdits();
  if (translation != null) edits.setTranslation('r', translation);
  if (box != null) edits.setBox('r', box);
  await service.savePage(
    file.parent.path,
    PersistedPage(
      name: p.basename(file.path),
      fingerprint: await fingerprintFile(file),
      analysis: _analysis,
      edits: edits,
    ),
  );
}

void main() {
  test(
    'empty library, deduplicated registration, reload, and remove keep source and M6 cache',
    () async {
      final storage = await Directory.systemTemp.createTemp('library_storage_');
      final sources = await Directory.systemTemp.createTemp('library_sources_');
      addTearDown(() async {
        await storage.delete(recursive: true);
        await sources.delete(recursive: true);
      });
      final firstPage = await _page(sources, 'Manga A/Chapter 1/1.jpg');
      await _page(sources, 'Manga B/Chapter 1/1.jpg');
      final cache = ChapterPersistenceRepository(storage);
      await _cache(cache, firstPage);
      final index = LibraryIndexRepository(
        supportDirectory: () async => storage,
      );
      LibraryController controller() => LibraryController(
        index: index,
        chapterPersistence: () async => cache,
      );
      final first = controller();
      await first.load();
      expect(first.roots, isEmpty);
      final a = await SourceHierarchy.discover(p.join(sources.path, 'Manga A'));
      final b = await SourceHierarchy.discover(p.join(sources.path, 'Manga B'));
      await first.register(a);
      await first.register(a);
      await first.register(b);
      expect(first.roots, hasLength(2));
      first.dispose();

      final second = controller();
      await second.load();
      expect(second.roots, hasLength(2));
      await second.remove(chapterStorageId(a.root.path));
      expect(second.roots, hasLength(1));
      expect(await firstPage.exists(), isTrue);
      expect(await cache.chapterFile(firstPage.parent.path).exists(), isTrue);
      second.dispose();
      final third = controller();
      await third.load();
      expect(third.roots.single.name, 'Manga B');
      third.dispose();
    },
  );

  test(
    'refresh derives hierarchy and statuses from current files and M6 fingerprints',
    () async {
      final storage = await Directory.systemTemp.createTemp(
        'library_status_storage_',
      );
      final source = await Directory.systemTemp.createTemp(
        'library_status_source_',
      );
      addTearDown(() async {
        if (await source.exists()) await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      final one = await _page(source, 'Volume 1/Chapter 1/1.jpg');
      final two = await _page(source, 'Volume 1/Chapter 1/2.jpg');
      await _page(source, 'Volume 2/Chapter 1/1.jpg');
      final cache = ChapterPersistenceRepository(storage);
      final library = LibraryController(
        index: LibraryIndexRepository(supportDirectory: () async => storage),
        chapterPersistence: () async => cache,
      );
      final hierarchy = await SourceHierarchy.discover(source.path);
      final root = await library.register(hierarchy);
      expect(root.status, LibraryStatus.notIndexed);
      await library.refresh(root.id, discovered: hierarchy);
      var snapshot = library.roots.single.snapshot!;
      expect(
        snapshot.children.first.children.first.pages.map((page) => page.status),
        [LibraryPageStatus.pending, LibraryPageStatus.pending],
      );
      expect(library.roots.single.status, LibraryStatus.pending);

      await _cache(cache, one);
      await library.refresh(root.id);
      expect(library.roots.single.status, LibraryStatus.partial);
      await _cache(cache, two);
      await library.refresh(root.id);
      expect(snapshot.children.first.name, 'Volume 1');
      expect(
        library.roots.single.status,
        LibraryStatus.partial,
      ); // Volume 2 is pending.
      await _cache(
        cache,
        File(p.join(source.path, 'Volume 2/Chapter 1/1.jpg')),
      );
      await library.refresh(root.id);
      expect(library.roots.single.status, LibraryStatus.cached);

      await _cache(cache, one, translation: 'Edited translation');
      await _cache(cache, two, box: const RegionBox(2, 2, 30, 30));
      await library.refresh(root.id);
      snapshot = library.roots.single.snapshot!;
      expect(
        snapshot.children.first.children.first.pages.map((page) => page.status),
        [LibraryPageStatus.edited, LibraryPageStatus.edited],
      );
      expect(library.roots.single.status, LibraryStatus.edited);
      await one.writeAsBytes([9, 9, 9]);
      await library.refresh(root.id);
      expect(
        library
            .roots
            .single
            .snapshot!
            .children
            .first
            .children
            .first
            .pages
            .first
            .status,
        LibraryPageStatus.pending,
      );

      await _page(source, 'Volume 1/Chapter 2/10.jpg');
      await _page(source, 'Volume 1/Chapter 2/2.jpg');
      await two.delete();
      await library.refresh(root.id);
      snapshot = library.roots.single.snapshot!;
      expect(snapshot.children.first.children.map((chapter) => chapter.name), [
        'Chapter 1',
        'Chapter 2',
      ]);
      expect(
        snapshot.children.first.children.last.pages.map((page) => page.name),
        ['2.jpg', '10.jpg'],
      );
      expect(snapshot.children.first.children.first.pages, hasLength(1));
      library.dispose();
    },
  );

  test(
    'missing root stays registered and refresh marks it unavailable',
    () async {
      final storage = await Directory.systemTemp.createTemp(
        'library_missing_storage_',
      );
      final source = await Directory.systemTemp.createTemp(
        'library_missing_source_',
      );
      addTearDown(() async {
        if (await source.exists()) await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      await _page(source, 'Chapter 1/1.jpg');
      final controller = LibraryController(
        index: LibraryIndexRepository(supportDirectory: () async => storage),
        chapterPersistence: () async => ChapterPersistenceRepository(storage),
      );
      final entry = await controller.register(
        await SourceHierarchy.discover(source.path),
      );
      await controller.refresh(entry.id);
      await source.delete(recursive: true);
      await controller.refresh(entry.id);
      expect(controller.roots, hasLength(1));
      expect(controller.roots.single.status, LibraryStatus.unavailable);
      controller.dispose();
    },
  );

  test(
    'malformed and unsupported indexes preserve files; backup recovers interrupted save',
    () async {
      final storage = await Directory.systemTemp.createTemp('library_corrupt_');
      addTearDown(() => storage.delete(recursive: true));
      final index = LibraryIndexRepository(
        supportDirectory: () async => storage,
      );
      final file = await index.indexFile();
      await file.writeAsString('{broken');
      final corrupt = await index.load();
      expect(corrupt.roots, isEmpty);
      expect(corrupt.writable, isFalse);
      expect(await file.readAsString(), '{broken');
      await file.writeAsString(jsonEncode({'schemaVersion': 999, 'roots': []}));
      final future = await index.load();
      expect(future.writable, isFalse);
      expect(await file.exists(), isTrue);
      await index.save([]);
      await file.rename('${file.path}.bak');
      await File('${file.path}.tmp').writeAsString('{interrupted');
      expect((await index.load()).writable, isTrue);
      await index.save([]);
      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/chapter/chapter_persistence.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/domain/region_edits.dart';
import 'package:manga_translator/features/manga_processing/presentation/processing_controller.dart';
import 'package:path/path.dart' as p;

import 'chapter_persistence_test.dart' show CountingRepository;

class CountingPersistence extends ChapterPersistenceRepository {
  CountingPersistence(super.root);
  int writes = 0;
  bool fail = false;
  @override
  Future<void> savePage(String sourceDirectory, PersistedPage page) async {
    writes++;
    if (fail) throw FileSystemException('Disk unavailable');
    await super.savePage(sourceDirectory, page);
  }
}

void main() {
  const analysis = PageAnalysis(
    width: 100,
    height: 100,
    regions: [
      DetectedRegion(
        id: 'r',
        x: 10,
        y: 10,
        width: 30,
        height: 30,
        sourceText: '日本語',
        translatedText: 'Machine',
      ),
    ],
  );

  test('partial cache accepts added pages and ignores removed pages', () async {
    final source = await Directory.systemTemp.createTemp('manga_partial_');
    final storage = await Directory.systemTemp.createTemp('manga_storage_');
    addTearDown(() async {
      await source.delete(recursive: true);
      await storage.delete(recursive: true);
    });
    final firstFile = File(p.join(source.path, '1.png'));
    await firstFile.writeAsBytes([1]);
    final service = ChapterPersistenceRepository(storage);
    final original = ChapterController(
      CountingRepository(analysis),
      persistence: service,
    );
    await original.open(source.path);
    await original.processPending();
    original.dispose();
    await File(p.join(source.path, '2.png')).writeAsBytes([2]);
    final repo = CountingRepository(analysis);
    final restored = ChapterController(repo, persistence: service);
    await restored.open(source.path);
    expect(restored.pages.map((page) => page.name), ['1.png', '2.png']);
    expect(restored.pages.first.restoredFromCache, isTrue);
    expect(restored.pages.last.status, ChapterPageStatus.pending);
    await restored.processPending();
    expect(repo.calls, 1);
    restored.dispose();
    await firstFile.delete();
    final fewer = ChapterController(
      CountingRepository(analysis),
      persistence: service,
    );
    addTearDown(fewer.dispose);
    await fewer.open(source.path);
    expect(fewer.pages.map((page) => page.name), ['2.png']);
  });

  test('analysis version mismatch does not restore old edits', () async {
    final source = await Directory.systemTemp.createTemp('manga_version_');
    final storage = await Directory.systemTemp.createTemp('manga_storage_');
    addTearDown(() async {
      await source.delete(recursive: true);
      await storage.delete(recursive: true);
    });
    final image = File(p.join(source.path, '1.jpg'));
    await image.writeAsBytes([1]);
    final service = ChapterPersistenceRepository(storage);
    await service.savePage(
      source.path,
      PersistedPage(
        name: '1.jpg',
        fingerprint: await fingerprintFile(image),
        analysis: analysis,
        edits: PageEdits()..setTranslation('r', 'Old edit'),
      ),
    );
    final file = service.chapterFile(source.path);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    (raw['pages'] as List).single['analysisCacheVersion'] = 999;
    await file.writeAsString(jsonEncode(raw));
    final controller = ChapterController(
      CountingRepository(analysis),
      persistence: service,
    );
    addTearDown(controller.dispose);
    await controller.open(source.path);
    expect(controller.pages.single.status, ChapterPageStatus.pending);
    expect(controller.pages.single.edits.hasEdits, isFalse);
    expect(
      (jsonDecode(await file.readAsString())['pages'] as List)
          .single['userEdits']['r']['translatedText'],
      'Old edit',
    );
  });

  test('Open Image reuses the same JSON and restores edits', () async {
    final source = await Directory.systemTemp.createTemp('manga_single_');
    final storage = await Directory.systemTemp.createTemp('manga_storage_');
    addTearDown(() async {
      await source.delete(recursive: true);
      await storage.delete(recursive: true);
    });
    final image = File(p.join(source.path, 'solo.png'));
    await image.writeAsBytes([1, 2, 3]);
    final service = ChapterPersistenceRepository(storage);
    final first = ProcessingController(CountingRepository(analysis))
      ..persistence = service;
    await first.openImageFile(image.path, Uint8List.fromList([1, 2, 3]));
    await first.detect();
    first.setTranslation('r', 'Manual');
    expect(first.setBox('r', const RegionBox(0, 0, 50, 60)), isNull);
    await first.flushSaves();
    first.dispose();
    final repo = CountingRepository(analysis);
    final second = ProcessingController(repo)..persistence = service;
    addTearDown(second.dispose);
    await second.openImageFile(image.path, Uint8List.fromList([1, 2, 3]));
    expect(second.restoredFromCache, isTrue);
    expect(second.analysis!.regions.first.translatedText, 'Machine');
    expect(
      second.edits.effectiveTranslation(second.analysis!.regions.first),
      'Manual',
    );
    expect(
      second.edits.effectiveBox(second.analysis!.regions.first),
      const RegionBox(0, 0, 50, 60),
    );
    expect(repo.calls, 0);
  });

  test('rapid edits coalesce and save failure keeps in-memory state', () async {
    final source = await Directory.systemTemp.createTemp('manga_autosave_');
    final storage = await Directory.systemTemp.createTemp('manga_storage_');
    addTearDown(() async {
      await source.delete(recursive: true);
      await storage.delete(recursive: true);
    });
    await File(p.join(source.path, '1.png')).writeAsBytes([1]);
    final service = CountingPersistence(storage);
    final controller = ChapterController(
      CountingRepository(analysis),
      persistence: service,
    );
    addTearDown(controller.dispose);
    await controller.open(source.path);
    await controller.processPending();
    expect(service.writes, 1);
    controller.setTranslation('r', 'a');
    controller.setTranslation('r', 'ab');
    controller.setTranslation('r', 'abc');
    await controller.stopAndWait();
    expect(service.writes, 2);
    expect(
      (await service.load(
        source.path,
      )).pages['1.png']!.edits.forRegion('r').translatedText,
      'abc',
    );
    service.fail = true;
    controller.setBox('r', const RegionBox(0, 0, 50, 60));
    await controller.flushSaves();
    expect(
      controller.pages.single.edits.forRegion('r').box,
      const RegionBox(0, 0, 50, 60),
    );
    expect(controller.saveError, contains('Could not save'));
    service.fail = false;
    controller.resetBox('r');
    await controller.flushSaves();
    expect(controller.saveError, isNull);
  });
}

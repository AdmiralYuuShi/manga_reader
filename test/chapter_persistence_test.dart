import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/chapter/chapter_persistence.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/domain/region_edits.dart';
import 'package:path/path.dart' as p;

class CountingRepository extends ProcessingRepository {
  CountingRepository(this.result)
    : super(ProcessingRemoteDataSource(ApiClient()));
  final PageAnalysis result;
  int calls = 0;
  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) async {
    calls++;
    return result;
  }
}

void main() {
  const analysis = PageAnalysis(
    width: 100,
    height: 120,
    regions: [
      DetectedRegion(
        id: 'r',
        x: 10,
        y: 20,
        width: 30,
        height: 40,
        sourceLanguage: 'ja',
        sourceText: '日本語',
        targetLanguage: 'id',
        translatedText: 'Machine',
        errorCode: null,
        translationErrorCode: null,
      ),
    ],
  );

  test(
    'JSON round trip keeps generated data, edits, versions and duration',
    () async {
      final source = await Directory.systemTemp.createTemp('manga_source_');
      final storage = await Directory.systemTemp.createTemp('manga_storage_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      final image = File(p.join(source.path, '001.jpg'));
      await image.writeAsBytes([1, 2, 3]);
      final edits = PageEdits()
        ..setTranslation('r', '')
        ..setBox('r', const RegionBox(0, 0, 50, 60));
      final service = ChapterPersistenceRepository(storage);
      await service.savePage(
        source.path,
        PersistedPage(
          name: '001.jpg',
          fingerprint: await fingerprintFile(image),
          analysis: analysis,
          edits: edits,
          duration: const Duration(seconds: 13),
        ),
      );
      final raw =
          jsonDecode(await service.chapterFile(source.path).readAsString())
              as Map<String, dynamic>;
      expect(raw['schemaVersion'], currentPersistenceSchemaVersion);
      expect(raw['sourceDirectory'], normalizeSourcePath(source.path));
      expect(
        (raw['pages'] as List).single['analysisCacheVersion'],
        currentAnalysisCacheVersion,
      );
      expect((raw['pages'] as List).single['relativePath'], '001.jpg');
      final restored = (await service.load(source.path)).pages['001.jpg']!;
      expect(restored.analysis.width, 100);
      expect(restored.analysis.height, 120);
      expect(restored.analysis.regions.first.sourceText, '日本語');
      expect(restored.analysis.regions.first.translatedText, 'Machine');
      expect(
        RegionBox.detector(restored.analysis.regions.first),
        const RegionBox(10, 20, 30, 40),
      );
      expect(restored.edits.forRegion('r').translatedText, '');
      expect(
        restored.edits.effectiveBox(restored.analysis.regions.first),
        const RegionBox(0, 0, 50, 60),
      );
      expect(restored.duration, const Duration(seconds: 13));
      expect(
        await File('${service.chapterFile(source.path).path}.tmp').exists(),
        isFalse,
      );
    },
  );

  test(
    'fingerprint hash is authoritative and storage IDs are deterministic',
    () async {
      final folder = await Directory.systemTemp.createTemp('manga_hash_');
      addTearDown(() => folder.delete(recursive: true));
      final file = File(p.join(folder.path, 'page.png'));
      await file.writeAsBytes([1, 2, 3]);
      final first = await fingerprintFile(file);
      final again = await fingerprintFile(file);
      expect(first.sha256Hash, again.sha256Hash);
      expect(first.size, 3);
      expect(first.modifiedMicros, greaterThan(0));
      final oldTime = (await file.stat()).modified;
      await file.writeAsBytes([3, 2, 1]);
      await file.setLastModified(oldTime);
      final replaced = await fingerprintFile(file);
      expect(replaced.size, first.size);
      expect(replaced.sha256Hash, isNot(first.sha256Hash));
      expect(
        chapterStorageId(folder.path),
        chapterStorageId(p.join(folder.path, '.')),
      );
      expect(
        chapterStorageId(folder.path),
        isNot(chapterStorageId(p.join(folder.path, 'other'))),
      );
      expect(safePageName('001.jpg'), isTrue);
      expect(safePageName('../escape.jpg'), isFalse);
      expect(safePageName('C:escape.jpg'), isFalse);
    },
  );

  test(
    'fully cached chapter and M5 edits reopen without backend calls',
    () async {
      final source = await Directory.systemTemp.createTemp('manga_cached_');
      final storage = await Directory.systemTemp.createTemp('manga_storage_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      await File(p.join(source.path, '1.png')).writeAsBytes([1]);
      await File(p.join(source.path, '2.png')).writeAsBytes([2]);
      final service = ChapterPersistenceRepository(storage);
      final initialRepo = CountingRepository(analysis);
      final initial = ChapterController(initialRepo, persistence: service);
      await initial.open(source.path);
      await initial.processPending();
      expect(initialRepo.calls, 2);
      initial.selectPage(0);
      initial.setTranslation('r', 'User edit');
      expect(initial.setBox('r', const RegionBox(0, 0, 50, 60)), isNull);
      await initial.flushSaves();
      initial.dispose();
      await File(
        p.join(source.path, '1.png'),
      ).setLastModified(DateTime.now().subtract(const Duration(days: 1)));

      final restoredRepo = CountingRepository(analysis);
      final restored = ChapterController(restoredRepo, persistence: service);
      addTearDown(restored.dispose);
      await restored.open(source.path);
      expect(
        restored.pages.every(
          (page) => page.status == ChapterPageStatus.completed,
        ),
        isTrue,
      );
      expect(restored.pages.every((page) => page.restoredFromCache), isTrue);
      expect(
        restored.pages[0].analysis!.regions.first.translatedText,
        'Machine',
      );
      expect(
        restored.pages[0].edits.effectiveTranslation(
          restored.pages[0].analysis!.regions.first,
        ),
        'User edit',
      );
      expect(
        restored.pages[0].edits.effectiveBox(
          restored.pages[0].analysis!.regions.first,
        ),
        const RegionBox(0, 0, 50, 60),
      );
      await restored.processPending();
      expect(restoredRepo.calls, 0);
      expect(restored.averageDuration, isNotNull);
      expect(restored.chapterElapsed, Duration.zero);
    },
  );

  test(
    'changed image is pending with no stale edits, then reprocess replaces cache',
    () async {
      final source = await Directory.systemTemp.createTemp('manga_changed_');
      final storage = await Directory.systemTemp.createTemp('manga_storage_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      final image = File(p.join(source.path, '1.jpg'));
      await image.writeAsBytes([1]);
      final service = ChapterPersistenceRepository(storage);
      final first = ChapterController(
        CountingRepository(analysis),
        persistence: service,
      );
      await first.open(source.path);
      await first.processPending();
      first.setTranslation('r', 'Old user edit');
      await first.flushSaves();
      first.dispose();
      await image.writeAsBytes([2]);
      final replacement = ChapterController(
        CountingRepository(analysis),
        persistence: service,
      );
      addTearDown(replacement.dispose);
      await replacement.open(source.path);
      expect(replacement.pages.single.status, ChapterPageStatus.pending);
      expect(replacement.pages.single.analysis, isNull);
      expect(replacement.pages.single.edits.hasEdits, isFalse);
      expect(
        (await service.load(
          source.path,
        )).pages['1.jpg']!.edits.forRegion('r').translatedText,
        'Old user edit',
      );
      await replacement.processPending();
      expect(replacement.pages.single.status, ChapterPageStatus.completed);
      expect(replacement.pages.single.edits.hasEdits, isFalse);
      expect(
        (await service.load(source.path)).pages['1.jpg']!.edits.hasEdits,
        isFalse,
      );
    },
  );

  test(
    'corrupt and future schema are unavailable without overwriting source data',
    () async {
      final source = await Directory.systemTemp.createTemp('manga_schema_');
      final storage = await Directory.systemTemp.createTemp('manga_storage_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      final service = ChapterPersistenceRepository(storage);
      final file = service.chapterFile(source.path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{broken');
      final corrupt = await service.load(source.path);
      expect(corrupt.pages, isEmpty);
      expect(corrupt.writable, isFalse);
      expect(await file.readAsString(), '{broken');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 999,
          'sourceDirectory': normalizeSourcePath(source.path),
          'pages': [],
        }),
      );
      final future = await service.load(source.path);
      expect(future.writable, isFalse);
      expect(future.warning, contains('Unsupported'));
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 999);
    },
  );

  test(
    'backup recovers an interrupted replacement and stale temp is replaced',
    () async {
      final source = await Directory.systemTemp.createTemp('manga_atomic_');
      final storage = await Directory.systemTemp.createTemp('manga_storage_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await storage.delete(recursive: true);
      });
      final image = File(p.join(source.path, '1.png'));
      await image.writeAsBytes([1]);
      final service = ChapterPersistenceRepository(storage);
      final page = PersistedPage(
        name: '1.png',
        fingerprint: await fingerprintFile(image),
        analysis: analysis,
        edits: PageEdits(),
      );
      await service.savePage(source.path, page);
      final finalFile = service.chapterFile(source.path);
      await finalFile.rename('${finalFile.path}.bak');
      await File('${finalFile.path}.tmp').writeAsString('{interrupted');
      expect(
        (await service.load(source.path)).pages.containsKey('1.png'),
        isTrue,
      );
      await service.savePage(source.path, page);
      expect(await finalFile.exists(), isTrue);
      expect(
        (await service.load(source.path)).pages.containsKey('1.png'),
        isTrue,
      );
      expect(await File('${finalFile.path}.tmp').exists(), isFalse);
    },
  );
}

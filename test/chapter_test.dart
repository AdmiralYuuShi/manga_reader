import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/chapter/chapter_controller.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';

class QueueRepository extends ProcessingRepository {
  QueueRepository() : super(ProcessingRemoteDataSource(ApiClient()));
  final calls = <String>[];
  final responses = <Completer<PageAnalysis>>[];
  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) {
    calls.add(filename);
    final response = Completer<PageAnalysis>();
    responses.add(response);
    return response.future;
  }
}

class ManualStopwatch implements Stopwatch {
  Duration value = Duration.zero;
  bool running = false;
  @override
  Duration get elapsed => value;
  @override
  int get elapsedMicroseconds => value.inMicroseconds;
  @override
  int get elapsedMilliseconds => value.inMilliseconds;
  @override
  int get elapsedTicks => value.inMicroseconds;
  @override
  int get frequency => 1000000;
  @override
  bool get isRunning => running;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void reset() => value = Duration.zero;
}

Future<void> waitForCalls(QueueRepository repository, int count) async {
  for (var i = 0; i < 100 && repository.calls.length < count; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(repository.calls.length, count);
}

void main() {
  test('natural order, formats, deterministic tie and duration formatting', () {
    expect(['10.jpg', '2.jpg', '1.jpg']..sort(naturalCompare), [
      '1.jpg',
      '2.jpg',
      '10.jpg',
    ]);
    expect(['page10.png', 'page2.png', 'page1.png']..sort(naturalCompare), [
      'page1.png',
      'page2.png',
      'page10.png',
    ]);
    expect(['010.jpg', '002.jpg', '001.jpg']..sort(naturalCompare), [
      '001.jpg',
      '002.jpg',
      '010.jpg',
    ]);
    expect(['1.png', '1.jpg']..sort(naturalCompare), ['1.jpg', '1.png']);
    expect(isChapterImage('PAGE.WEBP'), isTrue);
    expect(isChapterImage('notes.txt'), isFalse);
    expect(formatDuration(const Duration(seconds: 5)), '00:05');
    expect(formatDuration(const Duration(seconds: 65)), '01:05');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 5, seconds: 8)),
      '01:05:08',
    );
  });

  test(
    'sequential processing isolates failures, resumes, retries and clears state',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'manga_chapter_test_',
      );
      addTearDown(() => folder.delete(recursive: true));
      for (final name in ['10.png', '2.jpg', '1.jpg', 'notes.txt']) {
        await File(
          '${folder.path}${Platform.pathSeparator}$name',
        ).writeAsBytes([1]);
      }
      final repo = QueueRepository();
      final chapter = ChapterController(repo);
      addTearDown(chapter.dispose);
      await chapter.open(folder.path);
      expect(chapter.pages.map((p) => p.name), ['1.jpg', '2.jpg', '10.png']);
      expect(chapter.selectedPageIndex, 0);
      expect(
        chapter.pages.every((p) => p.status == ChapterPageStatus.pending),
        isTrue,
      );
      final run = chapter.processPending();
      await waitForCalls(repo, 1);
      expect(repo.calls, ['1.jpg']);
      expect(chapter.pages.first.status, ChapterPageStatus.processing);
      const first = PageAnalysis(
        width: 1,
        height: 1,
        regions: [DetectedRegion(id: 'first', x: 0, y: 0, width: 1, height: 1)],
      );
      repo.responses[0].complete(first);
      await waitForCalls(repo, 2);
      expect(repo.calls, ['1.jpg', '2.jpg']);
      expect(chapter.pages.first.analysis, same(first));
      expect(chapter.averageDuration, isNotNull);
      repo.responses[1].completeError(StateError('bad page'));
      await waitForCalls(repo, 3);
      expect(repo.calls, ['1.jpg', '2.jpg', '10.png']);
      repo.responses[2].complete(
        const PageAnalysis(width: 2, height: 2, regions: []),
      );
      await run;
      expect(chapter.pages[1].status, ChapterPageStatus.failed);
      expect(chapter.pages[2].status, ChapterPageStatus.completed);
      chapter.selectPage(0);
      chapter.selectRegion('first');
      expect(chapter.selectedRegion?.id, 'first');
      chapter.selectPage(1);
      expect(chapter.selectedRegion, isNull);
      final retry = chapter.retryPage(1);
      await waitForCalls(repo, 4);
      expect(repo.calls.last, '2.jpg');
      repo.responses[3].complete(
        const PageAnalysis(width: 3, height: 3, regions: []),
      );
      await retry;
      expect(chapter.pages[1].status, ChapterPageStatus.completed);
      expect(chapter.pages[1].error, isNull);
      expect(chapter.pages.first.analysis, same(first));
      await chapter.open(folder.path);
      expect(chapter.pages.every((p) => p.analysis == null), isTrue);
      expect(chapter.chapterElapsed, Duration.zero);
    },
  );

  test('stop after current page leaves following pages pending', () async {
    final folder = await Directory.systemTemp.createTemp('manga_stop_test_');
    addTearDown(() => folder.delete(recursive: true));
    for (final name in ['1.jpg', '2.jpg']) {
      await File(
        '${folder.path}${Platform.pathSeparator}$name',
      ).writeAsBytes([1]);
    }
    final repo = QueueRepository();
    final chapter = ChapterController(repo);
    addTearDown(chapter.dispose);
    await chapter.open(folder.path);
    final run = chapter.processPending();
    await waitForCalls(repo, 1);
    chapter.requestStop();
    repo.responses.first.complete(
      const PageAnalysis(width: 1, height: 1, regions: []),
    );
    await run;
    expect(repo.calls, ['1.jpg']);
    expect(chapter.pages[1].status, ChapterPageStatus.pending);
    final resume = chapter.processPending();
    await waitForCalls(repo, 2);
    expect(repo.calls, ['1.jpg', '2.jpg']);
    repo.responses.last.complete(
      const PageAnalysis(width: 1, height: 1, regions: []),
    );
    await resume;
  });

  test('empty folder is not processable', () async {
    final folder = await Directory.systemTemp.createTemp('manga_empty_test_');
    addTearDown(() => folder.delete(recursive: true));
    final chapter = ChapterController(QueueRepository());
    addTearDown(chapter.dispose);
    await chapter.open(folder.path);
    expect(chapter.pages, isEmpty);
    expect(chapter.error, isNotNull);
  });

  test('timing uses successful rolling average and clamps remaining', () async {
    final folder = await Directory.systemTemp.createTemp('manga_timing_test_');
    addTearDown(() => folder.delete(recursive: true));
    for (var i = 1; i <= 7; i++) {
      await File(
        '${folder.path}${Platform.pathSeparator}$i.jpg',
      ).writeAsBytes([1]);
    }
    final watches = <ManualStopwatch>[];
    final repo = QueueRepository();
    final chapter = ChapterController(
      repo,
      stopwatchFactory: () {
        final watch = ManualStopwatch();
        watches.add(watch);
        return watch;
      },
    );
    addTearDown(chapter.dispose);
    await chapter.open(folder.path);
    final run = chapter.processPending();
    await waitForCalls(repo, 1);
    expect(chapter.pageElapsed, Duration.zero);
    expect(chapter.estimatedRemaining, isNull);
    watches[0].value = const Duration(seconds: 3);
    watches[1].value = const Duration(seconds: 4);
    chapter.tickForTest();
    expect(chapter.chapterElapsed, const Duration(seconds: 3));
    expect(chapter.pageElapsed, const Duration(seconds: 4));
    repo.responses[0].complete(
      const PageAnalysis(width: 1, height: 1, regions: []),
    );
    await waitForCalls(repo, 2);
    expect(chapter.pages[0].duration, const Duration(seconds: 4));
    expect(chapter.averageDuration, const Duration(seconds: 4));
    expect(chapter.pageRemaining, const Duration(seconds: 4));
    watches[2].value = const Duration(seconds: 10);
    chapter.tickForTest();
    expect(chapter.pageRemaining, Duration.zero);
    expect(chapter.estimatedRemaining!.isNegative, isFalse);
    expect(
      chapter.estimatedTotal,
      chapter.chapterElapsed + chapter.estimatedRemaining!,
    );
    chapter.requestStop();
    repo.responses[1].completeError(StateError('failed'));
    await run;
    expect(chapter.averageDuration, const Duration(seconds: 4));
    final stopped = chapter.chapterElapsed;
    chapter.tickForTest();
    expect(chapter.chapterElapsed, stopped);
    expect(watches.every((watch) => !watch.running), isTrue);
  });

  test('rolling estimate uses last five successful completions', () async {
    final folder = await Directory.systemTemp.createTemp('manga_average_test_');
    addTearDown(() => folder.delete(recursive: true));
    for (var i = 1; i <= 6; i++) {
      await File(
        '${folder.path}${Platform.pathSeparator}$i.png',
      ).writeAsBytes([1]);
    }
    final watches = <ManualStopwatch>[];
    final repo = QueueRepository();
    final chapter = ChapterController(
      repo,
      stopwatchFactory: () {
        final watch = ManualStopwatch();
        watches.add(watch);
        return watch;
      },
    );
    addTearDown(chapter.dispose);
    await chapter.open(folder.path);
    final run = chapter.processPending();
    for (var i = 1; i <= 6; i++) {
      await waitForCalls(repo, i);
      watches.last.value = Duration(seconds: i);
      repo.responses[i - 1].complete(
        const PageAnalysis(width: 1, height: 1, regions: []),
      );
    }
    await run;
    expect(chapter.averageDuration, const Duration(seconds: 4));
    expect(chapter.estimatedRemaining, Duration.zero);
  });
}

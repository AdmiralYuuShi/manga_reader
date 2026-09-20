import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';
import 'package:manga_translator/features/manga_processing/data/processing_repository.dart';
import 'package:manga_translator/features/manga_processing/domain/page_analysis.dart';
import 'package:manga_translator/features/manga_processing/presentation/processing_controller.dart';
import 'package:manga_translator/main.dart';

class NoRequestRepository extends ProcessingRepository {
  NoRequestRepository() : super(ProcessingRemoteDataSource(ApiClient()));
  int calls = 0;
  @override
  Future<PageAnalysis> analyze(String filename, List<int> bytes) async {
    calls++;
    throw StateError('Editing must not call the backend');
  }
}

void main() {
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlqS28AAAAASUVORK5CYII=',
  );

  testWidgets('single-page editor updates text and geometry without requests', (
    tester,
  ) async {
    final repo = NoRequestRepository();
    final controller = ProcessingController(repo);
    controller.selectImage('page.png', image);
    controller.analysis = const PageAnalysis(
      width: 100,
      height: 100,
      regions: [
        DetectedRegion(
          id: 'r',
          x: 20,
          y: 20,
          width: 40,
          height: 40,
          sourceText: '日本語',
          translatedText: 'Machine',
        ),
      ],
    );
    controller.selectRegion('r');
    await tester.pumpWidget(
      MaterialApp(home: HomePage(controller: controller)),
    );
    await tester.pump();
    expect(find.text('Machine translation: Machine'), findsOneWidget);
    expect(find.byKey(const ValueKey('translation-text-r')), findsOneWidget);
    final detectorBefore = tester.getTopLeft(
      find.byKey(const ValueKey('detector-box-r')),
    );
    final overlayBefore = tester.getTopLeft(find.byKey(const ValueKey('r')));

    await tester.enterText(
      find.byKey(const ValueKey('translation-editor')),
      'Edited translation',
    );
    await tester.pump();
    expect(find.text('Edited translation'), findsWidgets);
    expect(controller.analysis!.regions.first.translatedText, 'Machine');
    expect(repo.calls, 0);

    await tester.enterText(find.byKey(const ValueKey('box-field-0')), '-1');
    await tester.ensureVisible(find.text('Apply Box'));
    await tester.tap(find.text('Apply Box'));
    await tester.pump();
    expect(find.textContaining('X must be at least 0'), findsOneWidget);
    expect(controller.edits.forRegion('r').box, isNull);

    await tester.enterText(find.byKey(const ValueKey('box-field-0')), '0');
    await tester.tap(find.text('Apply Box'));
    await tester.pump();
    expect(controller.edits.forRegion('r').box!.x, 0);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('r'))).dx,
      lessThan(overlayBefore.dx),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('detector-box-r'))),
      detectorBefore,
    );

    await tester.tap(find.text('Reset Box'));
    await tester.pump();
    expect(controller.edits.forRegion('r').box, isNull);
    expect(tester.getTopLeft(find.byKey(const ValueKey('r'))), overlayBefore);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('box-field-0')))
          .controller!
          .text,
      '20',
    );

    await tester.enterText(
      find.byKey(const ValueKey('translation-editor')),
      '',
    );
    await tester.pump();
    expect(controller.edits.forRegion('r').translatedText, '');
    expect(find.byKey(const ValueKey('translation-text-r')), findsNothing);
    final reset = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Reset Translation'),
        matching: find.byType(TextButton),
      ),
    );
    expect(reset.onPressed, isNotNull);
    reset.onPressed!();
    await tester.pump();
    expect(controller.edits.forRegion('r').translatedText, isNull);
    expect(find.byKey(const ValueKey('translation-text-r')), findsOneWidget);
    expect(repo.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

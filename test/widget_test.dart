import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/main.dart';

void main() {
  testWidgets('shows the backend status and retry control', (tester) async {
    await tester.pumpWidget(const MangaTranslatorApp());
    expect(find.text('Manga Translator'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
}

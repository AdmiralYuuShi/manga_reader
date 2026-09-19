import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_translator/core/api/api_client.dart';

void main() {
  test('API client reads the backend health response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) {
      expect(request.uri.path, '/api/v1/health');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'status': 'ok',
          'detector_ready': false,
          'ocr_ready': false,
        }),
      );
      request.response.close();
    });

    try {
      final health = await ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      ).getHealth();
      expect(health.status, 'ok');
      expect(health.detectorReady, isFalse);
      expect(health.ocrReady, isFalse);
    } finally {
      await serving.cancel();
      await server.close(force: true);
    }
  });
}

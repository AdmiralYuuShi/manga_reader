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

  test('API client posts multipart image and reads analysis JSON', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      expect(request.uri.path, '/api/v1/pages/analyze');
      expect(request.headers.contentType!.mimeType, 'multipart/form-data');
      final body = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      expect(latin1.decode(body), contains('filename="page.png"'));
      expect(latin1.decode(body), contains('PNGDATA'));
      expect(latin1.decode(body), contains('name="translate"\r\n\r\ntrue'));
      expect(latin1.decode(body), contains('name="target_language"\r\n\r\nid'));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'page': {'width': 10, 'height': 20},
          'regions': [],
          'processing': {'detection_ms': 1, 'total_ms': 2},
        }),
      );
      await request.response.close();
    });
    try {
      final response = await ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
      ).postImage('page.png', utf8.encode('PNGDATA'));
      expect((response['page'] as Map<String, dynamic>)['height'], 20);
    } finally {
      await serving.cancel();
      await server.close(force: true);
    }
  });
}

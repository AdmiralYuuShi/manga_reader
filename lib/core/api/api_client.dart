import 'dart:convert';
import 'dart:io';

class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.detectorReady,
    required this.ocrReady,
  });

  final String status;
  final bool detectorReady;
  final bool ocrReady;

  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
    status: json['status'] as String,
    detectorReady: json['detector_ready'] as bool,
    ocrReady: json['ocr_ready'] as bool,
  );
}

class ApiClient {
  ApiClient({
    String baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    HttpClient? httpClient,
  }) : _baseUrl = Uri.parse(baseUrl),
       _httpClient = httpClient ?? HttpClient();

  final Uri _baseUrl;
  final HttpClient _httpClient;

  Future<HealthResponse> getHealth() async {
    final uri = _baseUrl.resolve('/api/v1/health');
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Health request failed: ${response.statusCode}',
        uri: uri,
      );
    }
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 5));
    return HealthResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> postImage(
    String filename,
    List<int> bytes, {
    Duration timeout = const Duration(
      seconds: int.fromEnvironment(
        'ANALYSIS_TIMEOUT_SECONDS',
        defaultValue: 900,
      ),
    ),
  }) async {
    final uri = _baseUrl.resolve('/api/v1/pages/analyze');
    final boundary = 'manga-${DateTime.now().microsecondsSinceEpoch}';
    final safeName = filename.replaceAll(RegExp(r'[\r\n"\\]'), '_');
    final request = await _httpClient.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    request.add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="image"; filename="$safeName"\r\nContent-Type: application/octet-stream\r\n\r\n',
      ),
    );
    request.add(bytes);
    request.add(utf8.encode('\r\n--$boundary--\r\n'));
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Detection failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

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
}

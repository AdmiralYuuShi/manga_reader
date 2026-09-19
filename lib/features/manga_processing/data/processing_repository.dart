import '../../../core/api/api_client.dart';
import '../domain/page_analysis.dart';
import 'page_analysis_dto.dart';

class ProcessingRemoteDataSource {
  ProcessingRemoteDataSource(this.apiClient);

  final ApiClient apiClient;

  Future<Map<String, dynamic>> analyze(String filename, List<int> bytes) =>
      apiClient.postImage(filename, bytes);
}

class ProcessingRepository {
  ProcessingRepository(this.remote);

  final ProcessingRemoteDataSource remote;

  Future<PageAnalysis> analyze(String filename, List<int> bytes) async =>
      parsePageAnalysis(await remote.analyze(filename, bytes));
}

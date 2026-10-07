import '../../domain/entities/navigation_step.dart';
import '../../domain/repositories/navigation_repository.dart';
import '../datasources/navigation_api_datasource.dart';

class NavigationRepositoryImpl implements NavigationRepository {
  final NavigationApiDataSource _apiDataSource;

  NavigationRepositoryImpl([NavigationApiDataSource? apiDataSource])
      : _apiDataSource = apiDataSource ?? NavigationApiDataSource();

  @override
  Future<List<NavigationStep>> getRoute({required String destination}) {
    return _apiDataSource.fetchRoute(destination: destination);
  }

  @override
  Future<bool> verifyApiConnection() {
    return _apiDataSource.checkApiConnection();
  }

  @override
  void setApiUrl(String url) {
    _apiDataSource.apiUrl = url;
  }

  @override
  String getApiUrl() {
    return _apiDataSource.apiUrl;
  }
}

import '../../domain/entities/navigation_step.dart';

abstract class NavigationRepository {
  Future<List<NavigationStep>> getRoute({required String destination});
  Future<bool> verifyApiConnection();
  void setApiUrl(String url);
  String getApiUrl();
}

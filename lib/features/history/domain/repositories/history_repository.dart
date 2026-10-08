import '../../../assistant/domain/entities/detection_event.dart';

abstract class HistoryRepository {
  /// Máximo de entradas que se conservan.
  static const int maxEntries = 100;

  /// Historial, más reciente primero.
  Future<List<DetectionEvent>> getHistory();
  Future<void> addEvent(DetectionEvent event);
  Future<void> clear();
}

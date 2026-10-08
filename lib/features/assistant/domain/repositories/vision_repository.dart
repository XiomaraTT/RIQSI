import '../entities/detection_event.dart';
import '../entities/vision_connection_event.dart';

abstract class VisionRepository {
  Stream<DetectionEvent> get detections;

  /// Aperturas y cierres inesperados del canal con el servidor.
  Stream<VisionConnectionEvent> get connectionEvents;

  Future<void> connect(String ipAddress);

  /// Devuelve true si el frame se entregó al canal abierto.
  Future<bool> sendFrame(List<int> frameBytes);

  Future<void> disconnect();
}

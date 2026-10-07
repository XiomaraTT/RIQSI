import 'dart:async';
import '../../domain/entities/detected_object.dart';
import '../../domain/entities/detection_event.dart';
import '../../domain/repositories/vision_repository.dart';
import '../datasources/websocket_datasource.dart';

class VisionRepositoryImpl implements VisionRepository {
  final WebSocketDataSource dataSource;
  final StreamController<DetectionEvent> _detectionController =
      StreamController<DetectionEvent>.broadcast();

  VisionRepositoryImpl(this.dataSource) {
    dataSource.messages.listen(
      (data) {
        if (data["type"] == "detection") {
          final label = data["label"] as String? ?? "";
          final pos = data["position"] as String? ?? "Adelante";
          final risk = data["risk"] as String? ?? "Bajo";
          final desc = data["description"] as String? ?? "";
          
          // Nuevos campos enviados desde server/detector.py
          final distancia = data["distancia"] as String? ?? "lejos";
          final announceVoice = data["announce_voice"] as bool? ?? true;

          final List<DetectedObject> objectsList = [];
          if (data["objects"] != null) {
            for (var item in data["objects"]) {
              final List<int> box = List<int>.from(item["box"] ?? []);
              final List<double> boxNorm = item["box_norm"] != null
                  ? List<double>.from((item["box_norm"] as List).map((e) => (e as num).toDouble()))
                  : [];
              objectsList.add(DetectedObject(
                label: item["label"] as String? ?? "",
                relativePosition: (item["pos"] ?? item["position"] ?? "") as String,
                riskLevel: item["risk"] as String? ?? "Bajo",
                distancia: item["distancia"] as String? ?? "lejos",
                box: box,
                boxNorm: boxNorm,
              ));
            }
          }

          final event = DetectionEvent(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            label: label,
            relativePosition: pos,
            riskLevel: risk,
            timestamp: DateTime.now(),
            description: desc,
            distancia: distancia,
            announceVoice: announceVoice,
            objects: objectsList,
          );
          _detectionController.add(event);
        } else if (data["type"] == "clear") {
          // Evento vacío para indicar que la vía está libre y frenar vibraciones continuas
          final event = DetectionEvent(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            label: "despejado",
            relativePosition: "",
            riskLevel: "Bajo",
            timestamp: DateTime.now(),
            description: "",
            distancia: "despejado",
            announceVoice: false,
            objects: [],
          );
          _detectionController.add(event);
        }
      },
      onError: (err) {
        _detectionController.addError(err);
      },
    );
  }

  @override
  Stream<DetectionEvent> get detections => _detectionController.stream;

  @override
  Future<void> connect(String ipAddress) async {
    await dataSource.connect(ipAddress);
  }

  @override
  Future<void> sendFrame(List<int> frameBytes) async {
    await dataSource.sendBytes(frameBytes);
  }

  @override
  Future<void> disconnect() async {
    await dataSource.disconnect();
  }
}
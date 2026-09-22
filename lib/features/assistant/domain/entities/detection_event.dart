import 'detected_object.dart';

class DetectionEvent {
  final String id;
  final String label;
  final String relativePosition; // 'Izquierda', 'Derecha', 'Adelante'
  final String riskLevel;        // 'Bajo', 'Medio', 'Alto'
  final DateTime timestamp;
  final String description;
  final String distancia;        // 'muy_cerca', 'cerca', 'lejos', 'despejado'
  final bool announceVoice;      // true para hablar, false para solo modular vibración
  final List<DetectedObject> objects;

  DetectionEvent({
    required this.id,
    required this.label,
    required this.relativePosition,
    required this.riskLevel,
    required this.timestamp,
    required this.description,
    this.distancia = 'lejos',
    this.announceVoice = true,
    this.objects = const [],
  });
}
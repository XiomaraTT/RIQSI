import 'detected_object.dart';

class DetectionEvent {
  final String id;
  final String label;
  final String relativePosition; // 'Izquierda', 'Derecha', 'Adelante'
  final String riskLevel;        // 'Bajo', 'Medio', 'Alto'
  final DateTime timestamp;
  final String description;
  final String distancia;        // 'muy_cerca', 'cerca', 'lejos', 'despejado'
  final bool announceVoice;      // true para hablar, false para solo vibrar
  final List<DetectedObject> objects;
  final bool isClear;            // true si la escena está despejada

  DetectionEvent({
    required this.id,
    required this.label,
    required this.relativePosition,
    required this.riskLevel,
    required this.timestamp,
    required this.description,
    this.distancia = 'lejos',
    this.announceVoice = false,
    this.objects = const [],
    this.isClear = false,
  });

  bool get isHighRisk => riskLevel == 'Alto';

  /// Serialización para el historial persistido (sin cajas de detección).
  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'position': relativePosition,
        'risk': riskLevel,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'description': description,
        'distancia': distancia,
      };

  static DetectionEvent? fromMap(Map<String, dynamic> map) {
    try {
      return DetectionEvent(
        id: map['id']?.toString() ?? '',
        label: map['label'] as String? ?? '',
        relativePosition: map['position'] as String? ?? '',
        riskLevel: map['risk'] as String? ?? 'Bajo',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (map['timestamp'] as num?)?.toInt() ?? 0),
        description: map['description'] as String? ?? '',
        distancia: map['distancia'] as String? ?? 'lejos',
      );
    } catch (_) {
      return null;
    }
  }
}

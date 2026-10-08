import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/detected_object.dart';
import '../../domain/entities/detection_event.dart';
import '../../domain/entities/proximity.dart';
import '../../domain/entities/vision_connection_event.dart';
import '../../domain/repositories/vision_repository.dart';
import '../datasources/websocket_datasource.dart';

class VisionRepositoryImpl implements VisionRepository {
  final WebSocketDataSource dataSource;
  final StreamController<DetectionEvent> _detectionController =
      StreamController<DetectionEvent>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _messagesSub;
  int _seq = 0;

  VisionRepositoryImpl(this.dataSource) {
    _messagesSub = dataSource.messages.listen((data) {
      final event = parseMessage(data, id: _nextId());
      if (event != null) _detectionController.add(event);
    });
  }

  String _nextId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_seq++}';

  /// Convierte un mensaje del servidor en [DetectionEvent]. Devuelve null si
  /// el mensaje no es de un tipo conocido o está mal formado.
  @visibleForTesting
  static DetectionEvent? parseMessage(Map<String, dynamic> data,
      {required String id}) {
    try {
      final type = data['type'];
      if (type == 'clear') {
        return DetectionEvent(
          id: id,
          label: Proximity.despejado,
          relativePosition: '',
          riskLevel: 'Bajo',
          timestamp: DateTime.now(),
          description: '',
          distancia: Proximity.despejado,
          announceVoice: false,
          isClear: true,
        );
      }
      if (type != 'detection') return null;

      final risk = _str(data['risk']) ?? 'Bajo';
      // Por defecto NO se anuncia por voz (el servidor aplica cooldown a
      // Medio/Bajo); el riesgo Alto se anuncia salvo indicación explícita.
      final announceRaw = data['announce_voice'];
      final announceVoice = announceRaw is bool ? announceRaw : risk == 'Alto';

      final objectsList = <DetectedObject>[];
      final rawObjects = data['objects'];
      if (rawObjects is List) {
        for (final item in rawObjects) {
          if (item is! Map) continue;
          try {
            final box = (item['box'] as List?)
                    ?.map((e) => (e as num).toInt())
                    .toList() ??
                const <int>[];
            final boxNorm = (item['box_norm'] as List?)
                    ?.map((e) => (e as num).toDouble())
                    .toList() ??
                const <double>[];
            objectsList.add(DetectedObject(
              label: _str(item['label']) ?? '',
              relativePosition:
                  _str(item['pos']) ?? _str(item['position']) ?? '',
              riskLevel: _str(item['risk']) ?? 'Bajo',
              distancia: Proximity.normalize(_str(item['distancia'])) ??
                  Proximity.lejos,
              box: box,
              boxNorm: boxNorm,
            ));
          } catch (e) {
            debugPrint('[VISION] Objeto malformado ignorado: $e');
          }
        }
      }

      return DetectionEvent(
        id: id,
        label: _str(data['label']) ?? '',
        relativePosition: _str(data['position']) ?? 'Adelante',
        riskLevel: risk,
        timestamp: DateTime.now(),
        description: _str(data['description']) ?? '',
        distancia:
            Proximity.normalize(_str(data['distancia'])) ?? Proximity.lejos,
        announceVoice: announceVoice,
        objects: objectsList,
      );
    } catch (e) {
      debugPrint('[VISION] Mensaje del servidor ignorado: $e');
      return null;
    }
  }

  static String? _str(dynamic v) => v is String ? v : null;

  @override
  Stream<DetectionEvent> get detections => _detectionController.stream;

  @override
  Stream<VisionConnectionEvent> get connectionEvents =>
      dataSource.connectionEvents;

  @override
  Future<void> connect(String ipAddress) async {
    await dataSource.connect(ipAddress);
  }

  @override
  Future<bool> sendFrame(List<int> frameBytes) async {
    return dataSource.sendBytes(frameBytes);
  }

  @override
  Future<void> disconnect() async {
    await dataSource.disconnect();
  }

  Future<void> dispose() async {
    await _messagesSub.cancel();
    await _detectionController.close();
    await dataSource.dispose();
  }
}

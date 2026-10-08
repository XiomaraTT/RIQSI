import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../../domain/entities/proximity.dart';
import '../../domain/repositories/vibration_repository.dart';

typedef HasVibratorFn = Future<bool> Function();
typedef VibrateFn = void Function(int durationMs);
typedef CancelVibrationFn = void Function();

Future<bool> _defaultHasVibrator() async =>
    (await Vibration.hasVibrator()) == true;

void _defaultVibrate(int durationMs) {
  Vibration.vibrate(duration: durationMs).catchError((Object e) {
    debugPrint('[VIBRATION] $e');
  });
}

void _defaultCancel() {
  Vibration.cancel().catchError((Object e) {
    debugPrint('[VIBRATION] $e');
  });
}

class VibrationRepositoryImpl implements VibrationRepository {
  VibrationRepositoryImpl({
    HasVibratorFn? hasVibrator,
    VibrateFn? vibrate,
    CancelVibrationFn? cancel,
  })  : _hasVibratorFn = hasVibrator ?? _defaultHasVibrator,
        _vibrateFn = vibrate ?? _defaultVibrate,
        _cancelFn = cancel ?? _defaultCancel;

  final HasVibratorFn _hasVibratorFn;
  final VibrateFn _vibrateFn;
  final CancelVibrationFn _cancelFn;

  Timer? _activeLoop;
  String _currentDistance = "";
  Future<bool>? _hasVibrator;
  bool _disposed = false;
  int _patternToken = 0;

  @visibleForTesting
  String get currentDistance => _currentDistance;

  @visibleForTesting
  bool get isLoopActive => _activeLoop?.isActive ?? false;

  Future<bool> _checkVibrator() {
    return _hasVibrator ??= _hasVibratorFn().catchError((Object e) {
      debugPrint('[VIBRATION] hasVibrator falló: $e');
      return false;
    });
  }

  @override
  Future<void> vibrate(int durationMs) async {
    if (_disposed) return;
    if (await _checkVibrator()) _vibrateFn(durationMs);
  }

  @override
  void triggerProximityFeedback(String distancia) {
    final normalized = Proximity.normalize(distancia);
    if (normalized == null) {
      // Valor desconocido: no tocar la vibración activa sin motivo.
      debugPrint('[VIBRATION] distancia desconocida ignorada: "$distancia"');
      return;
    }
    if (_currentDistance == normalized) return;

    if (normalized == Proximity.despejado) {
      stop();
      return;
    }

    _currentDistance = normalized;
    _activeLoop?.cancel();
    _activeLoop = null;
    _startPattern(normalized, ++_patternToken);
  }

  Future<void> _startPattern(String distancia, int token) async {
    if (!await _checkVibrator()) return;
    // Pudo cambiar la distancia (o pararse) mientras esperábamos.
    if (_disposed || token != _patternToken) return;
    _activeLoop?.cancel();

    if (distancia == Proximity.muyCerca) {
      // Pulso continuo e insistente: 140ms cada 220ms
      _vibrateFn(140);
      _activeLoop = Timer.periodic(const Duration(milliseconds: 220), (_) {
        _vibrateFn(140);
      });
    } else if (distancia == Proximity.cerca) {
      // Pulso intermedio espaciado
      _vibrateFn(180);
      _activeLoop = Timer.periodic(const Duration(milliseconds: 650), (_) {
        _vibrateFn(180);
      });
    } else if (distancia == Proximity.lejos) {
      // Pulso leve único
      _vibrateFn(70);
    }
  }

  @override
  void stop() {
    final wasActive = _currentDistance.isNotEmpty || _activeLoop != null;
    _currentDistance = "";
    _patternToken++;
    _activeLoop?.cancel();
    _activeLoop = null;
    if (wasActive) _cancelFn();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
  }
}

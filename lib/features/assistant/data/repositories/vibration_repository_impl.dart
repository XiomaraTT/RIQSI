import 'dart:async';
import 'package:vibration/vibration.dart';
import '../../domain/repositories/vibration_repository.dart';

class VibrationRepositoryImpl implements VibrationRepository {
  Timer? _activeLoop;
  String _currentDistance = "";

  @override
  Future<void> vibrate(int durationMs) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(duration: durationMs);
      }
    } catch (_) {}
  }

  @override
  void triggerProximityFeedback(String distancia) async {
    if (_currentDistance == distancia) return;
    _currentDistance = distancia;

    _activeLoop?.cancel();

    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    if (distancia == "muy_cerca") {
      // Pulso continuo e insistente: 140ms cada 220ms
      Vibration.vibrate(duration: 140);
      _activeLoop = Timer.periodic(const Duration(milliseconds: 220), (_) {
        Vibration.vibrate(duration: 140);
      });
    } else if (distancia == "cerca") {
      // Pulso intermedio espaciado
      Vibration.vibrate(duration: 180);
      _activeLoop = Timer.periodic(const Duration(milliseconds: 650), (_) {
        Vibration.vibrate(duration: 180);
      });
    } else if (distancia == "lejos") {
      // Pulso leve único
      Vibration.vibrate(duration: 70);
    } else if (distancia == "despejado") {
      stop();
    }
  }

  @override
  void stop() {
    _currentDistance = "";
    _activeLoop?.cancel();
    Vibration.cancel();
  }
}
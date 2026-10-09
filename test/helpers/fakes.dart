import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:riqsi/features/assistant/domain/repositories/tts_repository.dart';
import 'package:riqsi/features/assistant/domain/repositories/vibration_repository.dart';

/// Deja correr microtareas y timers de duración cero pendientes.
Future<void> flush([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// FlutterTts falso: `speak` no termina hasta que se llame a
/// [finishCurrent] o `stop`.
class FakeFlutterTts extends Fake implements FlutterTts {
  final List<String> spoken = [];
  final List<double> volumes = [];
  int stopCalls = 0;
  double _volume = 1.0;
  Completer<void>? _current;

  bool get isSpeaking => _current != null;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async {
    _volume = volume;
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken.add(text);
    volumes.add(_volume);
    final c = Completer<void>();
    _current = c;
    return c.future;
  }

  @override
  Future<dynamic> stop() async {
    stopCalls++;
    finishCurrent();
    return 1;
  }

  void finishCurrent() {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete();
  }
}

class TtsCall {
  final String text;
  final double volume;
  final SpeechPriority priority;
  TtsCall(this.text, this.volume, this.priority);

  @override
  String toString() => 'TtsCall($text, $volume, $priority)';
}

/// TtsRepository que solo registra las llamadas (para tests de AppState).
class RecordingTtsRepository implements TtsRepository {
  final List<TtsCall> calls = [];
  int stopCalls = 0;

  List<String> get texts => calls.map((c) => c.text).toList();
  List<TtsCall> get alerts =>
      calls.where((c) => c.priority == SpeechPriority.alert).toList();

  @override
  Future<void> speak(String text, double rate, double volume,
      {SpeechPriority priority = SpeechPriority.normal}) async {
    calls.add(TtsCall(text, volume, priority));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class NoopVibrationRepository implements VibrationRepository {
  final List<String> proximity = [];
  int stopCalls = 0;

  @override
  Future<void> vibrate(int durationMs) async {}

  @override
  void triggerProximityFeedback(String distancia) => proximity.add(distancia);

  @override
  void stop() => stopCalls++;

  @override
  void dispose() {}
}

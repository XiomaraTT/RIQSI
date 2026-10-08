import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:riqsi/features/assistant/domain/repositories/tts_repository.dart';
import 'package:riqsi/features/assistant/domain/repositories/vibration_repository.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Deja correr microtareas y timers de duración cero pendientes.
Future<void> flush([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeWebSocketSink extends Fake implements WebSocketSink {
  final List<dynamic> sent = [];
  bool closed = false;

  @override
  void add(dynamic data) {
    if (closed) throw StateError('sink cerrado');
    sent.add(data);
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {
    closed = true;
  }
}

/// Canal WebSocket falso: el test controla `ready`, los mensajes entrantes,
/// errores y el cierre.
class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  FakeWebSocketChannel({bool autoReady = true}) {
    if (autoReady) readyCompleter.complete();
  }

  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final Completer<void> readyCompleter = Completer<void>();
  final FakeWebSocketSink fakeSink = FakeWebSocketSink();

  @override
  Stream get stream => incoming.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  Future<void> get ready => readyCompleter.future;

  void serverSend(Map<String, dynamic> json) => incoming.add(jsonEncode(json));
}

/// Factory que entrega canales falsos nuevos y los guarda para inspección.
class FakeChannelFactory {
  final List<FakeWebSocketChannel> created = [];
  final List<Uri> uris = [];
  bool autoReady = true;

  WebSocketChannel call(Uri uri) {
    uris.add(uri);
    final ch = FakeWebSocketChannel(autoReady: autoReady);
    created.add(ch);
    return ch;
  }

  FakeWebSocketChannel get last => created.last;
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

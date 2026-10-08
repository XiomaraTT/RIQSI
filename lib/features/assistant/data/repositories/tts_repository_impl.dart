import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/repositories/tts_repository.dart';

class _Utterance {
  final String text;
  final double rate;
  final double volume;
  final SpeechPriority priority;

  _Utterance(this.text, this.rate, this.volume, this.priority);

  bool get isAlert => priority == SpeechPriority.alert;
}

/// TTS con cola de prioridad.
///
/// Reglas:
/// - Una alerta interrumpe una frase normal en curso.
/// - Una alerta que llega mientras suena otra alerta espera (solo se guarda
///   la más reciente) para no cortar la frase de peligro a la mitad.
/// - Una frase normal interrumpe otra frase normal en curso, pero si hay una
///   alerta sonando o pendiente espera detrás (solo se guarda la última).
/// - Se usa `awaitSpeakCompletion(true)` para saber cuándo termina cada frase.
class TtsRepositoryImpl implements TtsRepository {
  TtsRepositoryImpl({FlutterTts? tts}) : _tts = tts;

  FlutterTts? _tts;
  FlutterTts get _engine => _tts ??= FlutterTts();

  Future<void>? _initFuture;

  _Utterance? _current;
  _Utterance? _pendingAlert;
  _Utterance? _pendingNormal;
  Completer<void>? _interrupt;
  bool _pumping = false;

  @visibleForTesting
  bool get isSpeakingAlert => _current?.isAlert ?? false;

  Future<void> _initTts() {
    return _initFuture ??= () async {
      try {
        await _engine.awaitSpeakCompletion(true);
        await _engine.setLanguage("es-ES");
        await _engine.setPitch(1.0);
      } catch (e) {
        debugPrint('[TTS] Error de inicialización: $e');
      }
    }();
  }

  @override
  Future<void> speak(
    String text,
    double rate,
    double volume, {
    SpeechPriority priority = SpeechPriority.normal,
  }) async {
    if (text.trim().isEmpty) return;
    final u = _Utterance(text, rate, volume, priority);

    if (u.isAlert) {
      _pendingAlert = u;
      // Las frases normales pendientes quedan obsoletas frente a un peligro.
      _pendingNormal = null;
      if (_current != null && !_current!.isAlert) _interruptCurrent();
    } else {
      final alertBusy = (_current?.isAlert ?? false) || _pendingAlert != null;
      _pendingNormal = u;
      if (!alertBusy && _current != null) _interruptCurrent();
    }
    _pump();
  }

  void _interruptCurrent() {
    final c = _interrupt;
    if (c != null && !c.isCompleted) c.complete();
    _engine.stop().catchError((Object e) {
      debugPrint('[TTS] Error al detener: $e');
    });
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      await _initTts();
      while (true) {
        final next = _pendingAlert ?? _pendingNormal;
        if (next == null) break;
        if (identical(next, _pendingAlert)) {
          _pendingAlert = null;
        } else {
          _pendingNormal = null;
        }
        _current = next;
        _interrupt = Completer<void>();
        await _speakNow(next, _interrupt!.future);
        _current = null;
      }
    } finally {
      _current = null;
      _pumping = false;
    }
  }

  Future<void> _speakNow(_Utterance u, Future<void> interrupted) async {
    try {
      final ttsRate = (u.rate * 0.5).clamp(0.1, 1.0);
      await _engine.setSpeechRate(ttsRate);
      await _engine.setVolume(u.volume.clamp(0.0, 1.0));
      // Límite de seguridad por si la plataforma nunca avisa del final.
      final maxDuration = Duration(
          milliseconds: math.min(20000, 2000 + u.text.length * 120));
      await Future.any<void>([
        _engine.speak(u.text).then((_) {}),
        interrupted,
      ]).timeout(maxDuration, onTimeout: () {});
    } catch (e) {
      debugPrint('[TTS] Error al hablar: $e');
    }
  }

  @override
  Future<void> stop() async {
    _pendingAlert = null;
    _pendingNormal = null;
    final c = _interrupt;
    if (c != null && !c.isCompleted) c.complete();
    try {
      await _engine.stop();
    } catch (e) {
      debugPrint('[TTS] Error al detener: $e');
    }
  }
}

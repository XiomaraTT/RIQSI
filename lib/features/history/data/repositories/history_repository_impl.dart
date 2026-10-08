import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../assistant/domain/entities/detection_event.dart';
import '../../domain/repositories/history_repository.dart';

typedef HistoryPrefsProvider = Future<SharedPreferences> Function();

/// Historial persistido en SharedPreferences (máx. 100 entradas, la más
/// reciente primero). Los mensajes 'clear' nunca se guardan.
class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl({HistoryPrefsProvider? prefs})
      : _prefsProvider = prefs ?? SharedPreferences.getInstance;

  static const historyKey = 'riqsi.history.v1';

  final HistoryPrefsProvider _prefsProvider;
  final List<DetectionEvent> _history = [];
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future.value();

  Future<SharedPreferences?> _prefs() async {
    try {
      return await _prefsProvider();
    } catch (e) {
      debugPrint('[HISTORY] Almacenamiento no disponible: $e');
      return null;
    }
  }

  Future<void> _load() => _loadFuture ??= () async {
        final prefs = await _prefs();
        if (prefs == null) return;
        try {
          final raw = prefs.getString(historyKey);
          if (raw == null) return;
          final data = jsonDecode(raw);
          if (data is! List) return;
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final event = DetectionEvent.fromMap(item);
            if (event != null) _history.add(event);
          }
          if (_history.length > HistoryRepository.maxEntries) {
            _history.removeRange(HistoryRepository.maxEntries, _history.length);
          }
        } catch (e) {
          debugPrint('[HISTORY] Historial guardado ilegible, se descarta: $e');
        }
      }();

  @override
  Future<List<DetectionEvent>> getHistory() async {
    await _load();
    return List.unmodifiable(_history);
  }

  @override
  Future<void> addEvent(DetectionEvent event) async {
    if (event.isClear) return;
    await _load();
    _history.insert(0, event);
    if (_history.length > HistoryRepository.maxEntries) {
      _history.removeRange(HistoryRepository.maxEntries, _history.length);
    }
    await _persist();
  }

  @override
  Future<void> clear() async {
    await _load();
    _history.clear();
    await _persist();
  }

  /// Serializa las escrituras para que no se pisen entre sí.
  Future<void> _persist() {
    final snapshot = jsonEncode(_history.map((e) => e.toMap()).toList());
    _writeChain = _writeChain.then((_) async {
      final prefs = await _prefs();
      try {
        await prefs?.setString(historyKey, snapshot);
      } catch (e) {
        debugPrint('[HISTORY] No se pudo guardar el historial: $e');
      }
    });
    return _writeChain;
  }
}

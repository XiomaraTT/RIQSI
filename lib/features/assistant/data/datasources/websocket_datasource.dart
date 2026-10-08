import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/vision_connection_event.dart';

/// Crea el canal WebSocket. Inyectable para poder usar fakes en tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Canal real: ping periódico para detectar sockets muertos (si el servidor
/// no responde al ping, dart:io cierra el socket y se dispara onDone) y
/// timeout de conexión para no quedar colgados en un handshake.
WebSocketChannel defaultWebSocketChannelFactory(Uri uri) {
  return IOWebSocketChannel.connect(
    uri,
    pingInterval: const Duration(seconds: 3),
    connectTimeout: const Duration(seconds: 5),
  );
}

class WebSocketDataSource {
  WebSocketDataSource({
    WebSocketChannelFactory? channelFactory,
    this.port = 8765,
  }) : _channelFactory = channelFactory ?? defaultWebSocketChannelFactory;

  final WebSocketChannelFactory _channelFactory;
  final int port;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _isOpen = false;

  /// Token de generación: cada connect/disconnect lo incrementa. Los
  /// callbacks de canales viejos comparan su token y se ignoran si ya no es
  /// el vigente, así un onDone/onError tardío no anula la conexión nueva.
  int _generation = 0;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<VisionConnectionEvent> _connectionController =
      StreamController<VisionConnectionEvent>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Aperturas y cierres (no pedidos por la app) del canal vigente.
  Stream<VisionConnectionEvent> get connectionEvents =>
      _connectionController.stream;

  bool get isConnected => _isOpen && _channel != null;

  @visibleForTesting
  int get generation => _generation;

  Future<void> connect(String host) async {
    await disconnect();
    final gen = ++_generation;

    final WebSocketChannel channel;
    try {
      channel = _channelFactory(Uri(scheme: 'ws', host: host, port: port));
    } catch (e) {
      debugPrint('[WS] No se pudo crear el canal: $e');
      _handleClosed(gen, e);
      return;
    }
    _channel = channel;

    _subscription = channel.stream.listen(
      (message) {
        if (gen != _generation) return;
        _handleMessage(message);
      },
      onError: (Object err) {
        if (gen != _generation) return;
        debugPrint('[WS] Error en el canal: $err');
        _handleClosed(gen, err);
      },
      onDone: () {
        if (gen != _generation) return;
        debugPrint('[WS] Canal cerrado por el servidor');
        _handleClosed(gen, null);
      },
      cancelOnError: true,
    );

    try {
      await channel.ready;
    } catch (e) {
      if (gen == _generation) {
        debugPrint('[WS] Fallo al conectar: $e');
        _handleClosed(gen, e);
      }
      return;
    }

    // El usuario pudo detener o reconectar mientras esperábamos el handshake.
    if (gen != _generation) return;
    _isOpen = true;
    _connectionController.add(const VisionConnectionEvent.connected());
  }

  void _handleMessage(dynamic message) {
    try {
      final String text =
          message is List<int> ? utf8.decode(message) : message.toString();
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) {
        _messageController.add(data);
      } else {
        debugPrint('[WS] Mensaje ignorado (no es un objeto JSON)');
      }
    } catch (e) {
      // Un mensaje malformado no debe cortar la sesión: se descarta.
      debugPrint('[WS] Mensaje malformado descartado: $e');
    }
  }

  void _handleClosed(int gen, Object? error) {
    if (gen != _generation) return;
    // Invalida cualquier otro callback de este canal (p.ej. onError + onDone).
    _generation++;
    _isOpen = false;
    final channel = _channel;
    final sub = _subscription;
    _channel = null;
    _subscription = null;
    sub?.cancel();
    _closeQuietly(channel);
    _connectionController.add(VisionConnectionEvent.disconnected(error));
  }

  /// Envía un frame. Devuelve false si no hay canal abierto o el envío falla.
  bool sendBytes(List<int> bytes) {
    final channel = _channel;
    if (channel == null || !_isOpen) return false;
    try {
      channel.sink.add(bytes);
      return true;
    } catch (e) {
      debugPrint('[WS] Error enviando frame: $e');
      _handleClosed(_generation, e);
      return false;
    }
  }

  Future<void> disconnect() async {
    _generation++;
    _isOpen = false;
    final channel = _channel;
    final sub = _subscription;
    _channel = null;
    _subscription = null;
    await sub?.cancel();
    await _closeQuietly(channel);
  }

  Future<void> _closeQuietly(WebSocketChannel? channel) async {
    if (channel == null) return;
    try {
      await channel.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _connectionController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketDataSource {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _isConnected && _channel != null;

  Future<void> connect(String ipAddress) async {
    await disconnect();
    try {
      final wsUrl = Uri.parse("ws://$ipAddress:8765");
      _channel = WebSocketChannel.connect(wsUrl);
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString());
            if (data is Map<String, dynamic>) {
              _messageController.add(data);
            }
          } catch (e) {
            _messageController.addError(e);
          }
        },
        onError: (err) {
          _isConnected = false;
          _channel = null;
          _messageController.addError(err);
        },
        onDone: () {
          _isConnected = false;
          _channel = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnected = false;
      _channel = null;
      _messageController.addError(e);
    }
  }

  Future<void> sendBytes(List<int> bytes) async {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(bytes);
      } catch (e) {
        _isConnected = false;
        _channel = null;
      }
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}

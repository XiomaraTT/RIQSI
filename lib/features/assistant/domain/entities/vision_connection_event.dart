/// Estado de la conexión con el servidor de visión.
enum VisionConnectionStatus { connected, disconnected }

/// Evento emitido cuando el canal con el servidor se abre o se cierra.
///
/// Un cierre puede venir de un error de red ([error] != null) o de un cierre
/// limpio del servidor ([error] == null). Los cierres pedidos explícitamente
/// por la app (`disconnect()`) no emiten evento.
class VisionConnectionEvent {
  final VisionConnectionStatus status;
  final Object? error;

  const VisionConnectionEvent._(this.status, [this.error]);

  const VisionConnectionEvent.connected()
      : this._(VisionConnectionStatus.connected);

  const VisionConnectionEvent.disconnected([Object? error])
      : this._(VisionConnectionStatus.disconnected, error);

  bool get isConnected => status == VisionConnectionStatus.connected;

  @override
  String toString() =>
      'VisionConnectionEvent($status${error != null ? ', $error' : ''})';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/data/datasources/websocket_datasource.dart';
import 'package:riqsi/features/assistant/domain/entities/vision_connection_event.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeChannelFactory factory;
  late WebSocketDataSource ds;
  late List<Map<String, dynamic>> messages;
  late List<Object> errors;
  late List<VisionConnectionEvent> events;

  setUp(() {
    factory = FakeChannelFactory();
    ds = WebSocketDataSource(channelFactory: factory.call);
    messages = [];
    errors = [];
    events = [];
    ds.messages.listen(messages.add, onError: errors.add);
    ds.connectionEvents.listen(events.add, onError: errors.add);
  });

  tearDown(() => ds.dispose());

  test('usa ws://host:8765', () async {
    await ds.connect('192.168.1.15');
    expect(factory.uris.single.toString(), 'ws://192.168.1.15:8765');
  });

  test('JSON malformado se descarta sin emitir error ni cortar la sesión',
      () async {
    await ds.connect('10.0.0.1');
    final ch = factory.last;

    ch.incoming.add('{esto no es json');
    ch.incoming.add('[1, 2, 3]'); // JSON válido pero no es objeto
    ch.serverSend({'type': 'clear'});
    await flush();

    expect(errors, isEmpty);
    expect(messages, hasLength(1));
    expect(messages.single['type'], 'clear');
    expect(ds.isConnected, isTrue);
    expect(events.map((e) => e.status),
        [VisionConnectionStatus.connected]);
  });

  test('onDone del servidor propaga un evento de desconexión', () async {
    await ds.connect('10.0.0.1');
    expect(ds.isConnected, isTrue);

    await factory.last.incoming.close();
    await flush();

    expect(events.map((e) => e.status), [
      VisionConnectionStatus.connected,
      VisionConnectionStatus.disconnected,
    ]);
    expect(ds.isConnected, isFalse);
    expect(ds.sendBytes([1, 2, 3]), isFalse);
  });

  test('onError del canal propaga desconexión una sola vez', () async {
    await ds.connect('10.0.0.1');
    factory.last.incoming.addError(Exception('reset'));
    await flush();

    final disconnects =
        events.where((e) => !e.isConnected).toList();
    expect(disconnects, hasLength(1));
    expect(disconnects.single.error, isNotNull);
    expect(errors, isEmpty);
  });

  test('fallo del handshake emite desconexión', () async {
    factory.autoReady = false;
    final future = ds.connect('10.0.0.1');
    await flush();
    factory.last.readyCompleter.completeError(Exception('timeout'));
    await future;
    await flush();

    expect(events.map((e) => e.status), [VisionConnectionStatus.disconnected]);
    expect(ds.isConnected, isFalse);
  });

  test('callbacks del canal viejo no afectan al canal nuevo', () async {
    await ds.connect('10.0.0.1');
    final oldCh = factory.last;
    await ds.connect('10.0.0.2');
    final newCh = factory.last;
    await flush();
    events.clear();

    // El canal viejo "muere" tarde y sigue mandando cosas.
    oldCh.serverSend({'type': 'detection', 'label': 'viejo'});
    oldCh.incoming.addError(Exception('error tardío'));
    await oldCh.incoming.close();
    newCh.serverSend({'type': 'detection', 'label': 'nuevo'});
    await flush();

    expect(events, isEmpty, reason: 'no debe emitirse desconexión');
    expect(ds.isConnected, isTrue);
    expect(messages.map((m) => m['label']), ['nuevo']);
    expect(oldCh.fakeSink.closed, isTrue);
    expect(ds.sendBytes([9]), isTrue);
    expect(newCh.fakeSink.sent, [
      [9]
    ]);
  });

  test('un handshake tardío de un canal viejo se ignora', () async {
    factory.autoReady = false;
    final first = ds.connect('10.0.0.1');
    await flush();
    final oldCh = factory.last;

    factory.autoReady = true;
    await ds.connect('10.0.0.2');
    oldCh.readyCompleter.complete(); // llega tarde
    await first;
    await flush();

    expect(events.map((e) => e.status), [VisionConnectionStatus.connected]);
    expect(ds.isConnected, isTrue);
    expect(oldCh.fakeSink.closed, isTrue);
  });

  test('disconnect explícito no emite evento y bloquea el envío', () async {
    await ds.connect('10.0.0.1');
    final ch = factory.last;
    await ds.disconnect();
    await ch.incoming.close();
    await flush();

    expect(events.map((e) => e.status), [VisionConnectionStatus.connected]);
    expect(ds.sendBytes([1]), isFalse);
  });
}

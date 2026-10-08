import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/data/datasources/websocket_datasource.dart';
import 'package:riqsi/features/assistant/data/repositories/vision_repository_impl.dart';
import 'package:riqsi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChannelFactory factory;
  late RecordingTtsRepository tts;
  late NoopVibrationRepository vibration;
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    factory = FakeChannelFactory();
    tts = RecordingTtsRepository();
    vibration = NoopVibrationRepository();
    state = AppState(
      webSocketDataSource: WebSocketDataSource(channelFactory: factory.call),
      ttsRepository: tts,
      vibrationRepository: vibration,
      splashDuration: const Duration(hours: 1),
    );
    await state.ready;
  });

  tearDown(() => state.dispose());

  Future<void> startAssistance() async {
    state.toggleAssistance();
    await flush();
    expect(state.connectionStatus, ServerConnectionStatus.connected);
    tts.calls.clear();
  }

  Map<String, dynamic> detection({
    String label = 'Persona',
    String risk = 'Medio',
    bool? announce,
    String distancia = 'cerca',
    String description = 'Persona adelante',
  }) =>
      {
        'type': 'detection',
        'label': label,
        'position': 'Adelante',
        'risk': risk,
        'description': description,
        'distancia': distancia,
        'announce_voice': ?announce,
        'objects': [],
      };

  group('validación de IP', () {
    test('acepta IPv4 y nombres de equipo', () {
      for (final ok in [
        '192.168.1.15',
        ' 10.0.2.2 ',
        '0.0.0.0',
        'localhost',
        'mi-servidor.local',
        'riqsi-pc',
      ]) {
        expect(AppState.validateServerAddress(ok), isNull, reason: ok);
      }
    });

    test('rechaza vacíos y formatos inválidos', () {
      for (final bad in [
        '',
        '   ',
        '999.1.1.1',
        '1.2.3',
        '1.2.3.4.5',
        'http://1.2.3.4',
        '1.2.3.4:8765',
        'host_con_guion_bajo',
        '-abc',
        'a..b',
      ]) {
        expect(AppState.validateServerAddress(bad), isNotNull, reason: bad);
      }
    });

    test('updateServerIp guarda la IP recortada o devuelve el error', () {
      final previous = state.serverIp;
      expect(state.updateServerIp('no válida!'), isNotNull);
      expect(state.serverIp, previous);

      expect(state.updateServerIp('  192.168.1.20  '), isNull);
      expect(state.serverIp, '192.168.1.20');
    });

    test('cambiar la IP con la asistencia activa reconecta', () async {
      await startAssistance();
      expect(factory.uris.last.host, state.serverIp);

      state.updateServerIp('192.168.1.77');
      await flush();
      expect(factory.created, hasLength(2));
      expect(factory.uris.last.host, '192.168.1.77');
      expect(factory.created.first.fakeSink.closed, isTrue);
      expect(state.connectionStatus, ServerConnectionStatus.connected);
    });
  });

  group('voz y silencio', () {
    test('con la voz silenciada no suenan frases normales pero sí riesgo Alto',
        () async {
      await startAssistance();
      state.updateVolume(0);
      await flush();

      state.speak('Controles visibles');
      factory.last.serverSend(detection(
          label: 'Hueco',
          risk: 'Alto',
          announce: false,
          distancia: 'inmediato',
          description: '¡Cuidado! Hueco adelante'));
      await flush();

      expect(tts.texts, ['¡Cuidado! Hueco adelante']);
      expect(tts.alerts.single.volume, greaterThan(0));
      expect(state.assistanceState, AssistanceState.riskDetected);
      expect(vibration.proximity.last, 'muy_cerca');
    });

    test('riesgo Alto con announce_voice=false no se repite en cada frame',
        () async {
      await startAssistance();
      for (var i = 0; i < 5; i++) {
        factory.last.serverSend(detection(
            label: 'Auto', risk: 'Alto', announce: false, description: 'Auto'));
      }
      await flush();
      expect(tts.alerts, hasLength(1));
    });

    test('Medio/Bajo respetan announce_voice (por defecto no se anuncia)',
        () async {
      await startAssistance();
      factory.last.serverSend(detection(announce: null));
      factory.last.serverSend(detection(announce: false));
      await flush();
      expect(tts.calls, isEmpty);

      factory.last.serverSend(detection(announce: true));
      await flush();
      expect(tts.texts, ['Persona adelante']);
    });
  });

  group('historial', () {
    test('no guarda clear ni detecciones no anunciadas', () async {
      await startAssistance();
      factory.last.serverSend({'type': 'clear'});
      factory.last.serverSend(detection(announce: false));
      await flush();
      expect(state.history, isEmpty);

      factory.last.serverSend(detection(announce: true));
      await flush();
      expect(state.history, hasLength(1));
    });

    test('respeta el tope de 100 entradas', () async {
      await startAssistance();
      for (var i = 0; i < 110; i++) {
        factory.last.serverSend(
            detection(label: 'Obj $i', announce: true, description: 'Obj $i'));
      }
      await flush(20);
      expect(state.history, hasLength(AppState.maxHistoryEntries));
      expect(state.history.first.label, 'Obj 109');
    });
  });

  group('conexión', () {
    test('cierre del servidor: avisa una vez y reconecta con backoff', () async {
      await startAssistance();
      await factory.last.incoming.close();
      await flush();

      expect(state.connectionStatus, ServerConnectionStatus.reconnecting);
      expect(state.isConnected, isFalse);
      expect(tts.alerts.map((c) => c.text).single,
          contains('Sin conexión con el servidor'));

      // Primer reintento a 1 s: vuelve a conectar y anuncia la recuperación.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await flush();
      expect(factory.created, hasLength(2));
      expect(state.connectionStatus, ServerConnectionStatus.connected);
      expect(tts.texts.last, 'Conexión recuperada.');
      expect(tts.alerts, hasLength(1));
    });

    test('watchdog: frames sin respuesta en 5 s pasan a reconectando',
        () async {
      await startAssistance();
      expect(await state.sendFrameBytes([1, 2, 3]), isTrue);

      state.checkWatchdog(DateTime.now().add(const Duration(seconds: 2)));
      expect(state.connectionStatus, ServerConnectionStatus.connected);

      state.checkWatchdog(DateTime.now().add(const Duration(seconds: 6)));
      expect(state.connectionStatus, ServerConnectionStatus.reconnecting);
      state.checkWatchdog(DateTime.now().add(const Duration(seconds: 12)));
      expect(tts.alerts, hasLength(1), reason: 'se anuncia una sola vez');
    });

    test('no se acumulan frames: se espera la respuesta del anterior',
        () async {
      await startAssistance();
      expect(await state.sendFrameBytes([1]), isTrue);
      expect(state.canStreamFrames, isFalse);
      expect(await state.sendFrameBytes([2]), isFalse);
      factory.last.serverSend({'type': 'clear'});
      await flush();
      expect(state.canStreamFrames, isTrue);
      expect(await state.sendFrameBytes([3]), isTrue);
      expect(factory.last.fakeSink.sent, [
        [1],
        [3]
      ]);
    });

    test('una respuesta del servidor reinicia el watchdog', () async {
      await startAssistance();
      await state.sendFrameBytes([1]);
      factory.last.serverSend({'type': 'clear'});
      await flush();
      state.checkWatchdog(DateTime.now().add(const Duration(seconds: 6)));
      expect(state.connectionStatus, ServerConnectionStatus.connected);
    });

    test('Detener durante el handshake no deja una conexión viva', () async {
      factory.autoReady = false;
      state.toggleAssistance();
      await flush();
      state.toggleAssistance(); // Detener
      factory.last.readyCompleter.complete();
      await flush();

      expect(state.assistanceState, AssistanceState.inactive);
      expect(state.connectionStatus, ServerConnectionStatus.idle);
      expect(factory.last.fakeSink.closed, isTrue);
      expect(await state.sendFrameBytes([1]), isFalse);
    });

    test('backoff 1, 2, 4, 8 y máximo 10 s', () {
      expect(
          List.generate(6, (i) => AppState.reconnectDelayFor(i).inSeconds),
          [1, 2, 4, 8, 10, 10]);
    });
  });

  test('parser: announce_voice por defecto false salvo riesgo Alto', () {
    final medio = VisionRepositoryImpl.parseMessage(
        {'type': 'detection', 'risk': 'Medio'},
        id: '1');
    final alto = VisionRepositoryImpl.parseMessage(
        {'type': 'detection', 'risk': 'Alto', 'distancia': 'inmediato'},
        id: '2');
    expect(medio!.announceVoice, isFalse);
    expect(alto!.announceVoice, isTrue);
    expect(alto.distancia, 'muy_cerca');
    expect(VisionRepositoryImpl.parseMessage({'type': 'otro'}, id: '3'),
        isNull);
    expect(
        VisionRepositoryImpl.parseMessage(
            {'type': 'detection', 'objects': 'basura'},
            id: '4'),
        isNotNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/domain/scene/scene_logic.dart';
import 'package:riqsi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

/// Analizador real que además cuenta las llamadas.
class CountingAnalyzer extends SceneAnalyzer {
  final List<int> calls = [];
  int resets = 0;

  @override
  SceneResult analyse(List<RawDetection> detections, {required int nowMs}) {
    calls.add(nowMs);
    return super.analyse(detections, nowMs: nowMs);
  }

  @override
  void reset() {
    resets++;
    super.reset();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingTtsRepository tts;
  late NoopVibrationRepository vibration;
  late CountingAnalyzer analyzer;
  late AppState state;
  var now = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tts = RecordingTtsRepository();
    vibration = NoopVibrationRepository();
    analyzer = CountingAnalyzer();
    now = 1000;
    state = AppState(
      ttsRepository: tts,
      vibrationRepository: vibration,
      sceneAnalyzer: analyzer,
      clockMs: () => now,
      splashDuration: const Duration(hours: 1),
    );
    await state.ready;
  });

  tearDown(() => state.dispose());

  void startAssistance() {
    state.toggleAssistance();
    tts.calls.clear();
  }

  var seq = 0;
  DetectionEvent detection({
    String label = 'persona',
    String pos = 'centro',
    String risk = 'Medio',
    bool announce = false,
    String distancia = 'cerca',
    String description = 'Persona adelante',
    bool clear = false,
  }) =>
      DetectionEvent(
        id: 'e${seq++}',
        label: clear ? '' : label,
        relativePosition: clear ? '' : pos,
        riskLevel: risk,
        timestamp: DateTime(2026),
        description: clear ? '' : description,
        distancia: clear ? 'despejado' : distancia,
        announceVoice: announce,
        isClear: clear,
      );

  group('voz y alertas', () {
    test('riesgo Alto anunciado: alerta prioritaria aunque la voz esté en 0',
        () {
      startAssistance();
      state.updateVolume(0);

      state.speak('Controles visibles');
      state.applyDetection(detection(
          label: 'hueco',
          risk: 'Alto',
          announce: true,
          distancia: 'muy_cerca',
          description: '¡Cuidado! Hueco adelante'));

      expect(tts.texts, ['¡Cuidado! Hueco adelante']);
      expect(tts.alerts.single.volume, greaterThan(0));
      expect(state.assistanceState, AssistanceState.riskDetected);
      expect(vibration.proximity.last, 'muy_cerca');
    });

    test('sin announce no se habla, pero sí se vibra y se muestra', () {
      startAssistance();
      state.applyDetection(detection(risk: 'Alto', announce: false));
      state.applyDetection(detection(risk: 'Medio', announce: false));
      expect(tts.calls, isEmpty);
      expect(vibration.proximity, ['cerca', 'cerca']);
      expect(state.activeDetection, isNotNull);
    });

    test('Medio/Bajo anunciados usan la voz normal', () {
      startAssistance();
      state.applyDetection(detection(announce: true));
      expect(tts.texts, ['Persona adelante']);
      expect(tts.alerts, isEmpty);
      expect(state.assistanceState, AssistanceState.objectDetected);
    });

    test('con la asistencia detenida se ignoran las detecciones', () {
      state.applyDetection(detection(announce: true));
      state.onRawDetections(const []);
      expect(tts.calls, isEmpty);
      expect(analyzer.calls, isEmpty);
      expect(state.activeDetection, isNull);
    });

    test('Entendido evita reabrir la misma alerta durante el cooldown', () {
      startAssistance();
      state.applyDetection(detection(risk: 'Alto'));
      expect(state.assistanceState, AssistanceState.riskDetected);
      state.dismissAlert();

      now += 1000;
      state.applyDetection(detection(risk: 'Alto', announce: true));
      expect(state.assistanceState, AssistanceState.objectDetected);
      expect(tts.alerts, hasLength(1), reason: 'se sigue avisando por voz');

      now += AppState.alertDismissCooldown.inMilliseconds;
      state.applyDetection(detection(risk: 'Alto'));
      expect(state.assistanceState, AssistanceState.riskDetected);
    });
  });

  group('cámara → analizador', () {
    test('procesa como máximo ~8 resultados por segundo', () {
      startAssistance();
      for (final t in [0, 50, 119, 120, 200, 239, 240, 1000]) {
        now = 5000 + t;
        state.onRawDetections(const []);
      }
      expect(analyzer.calls, [5000, 5120, 5240, 6000]);
    });

    test('escena vacía: vibración despejado y sin cambio de estado', () {
      startAssistance();
      state.onRawDetections(const []);
      expect(vibration.proximity.last, 'despejado');
      expect(state.assistanceState, AssistanceState.analyzing);
      expect(state.statusHeadline, 'Camino despejado');
    });

    test('iniciar reinicia el analizador; detener para la vibración', () {
      startAssistance();
      expect(analyzer.resets, 1);
      state.toggleAssistance();
      expect(state.assistanceState, AssistanceState.inactive);
      expect(vibration.stopCalls, greaterThan(0));
      state.onRawDetections(const []);
      expect(analyzer.calls, isEmpty);
    });
  });

  group('historial', () {
    test('solo guarda las detecciones anunciadas', () {
      startAssistance();
      state.applyDetection(detection(clear: true));
      state.applyDetection(detection(announce: false));
      expect(state.history, isEmpty);

      state.applyDetection(detection(announce: true));
      expect(state.history, hasLength(1));
    });

    test('respeta el tope de entradas', () {
      startAssistance();
      for (var i = 0; i < 110; i++) {
        state.applyDetection(
            detection(label: 'obj $i', announce: true, description: 'Obj $i'));
      }
      expect(state.history, hasLength(AppState.maxHistoryEntries));
      expect(state.history.first.label, 'obj 109');
    });
  });

  group('estado visible', () {
    test('titular con objeto, distancia y posición', () {
      startAssistance();
      state.applyDetection(
          detection(label: 'persona', distancia: 'muy_cerca', pos: 'centro'));
      expect(state.statusHeadline, 'Persona muy cerca · centro');
      expect(state.statusRisk, 'Medio');
    });

    test('al entrar a la pantalla principal se abre la pestaña Inicio', () {
      state.setTab(1);
      state.navigateToScreen(AppScreen.mainLayout);
      expect(state.currentTab, 0);
    });

    test('sin nombre el saludo es genérico', () {
      expect(state.userName, isEmpty);
      expect(state.greeting, 'Hola.');
      state.updateUserName('  Ana ');
      expect(state.greeting, 'Hola, Ana.');
    });
  });
}

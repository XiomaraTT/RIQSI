import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/data/repositories/tts_repository_impl.dart';
import 'package:riqsi/features/assistant/domain/repositories/tts_repository.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeFlutterTts engine;
  late TtsRepositoryImpl tts;

  setUp(() {
    engine = FakeFlutterTts();
    tts = TtsRepositoryImpl(tts: engine);
  });

  test('una frase de UI no corta una alerta en curso; espera detrás',
      () async {
    await tts.speak('¡Cuidado! Hueco adelante', 1, 0.8,
        priority: SpeechPriority.alert);
    await flush();
    expect(engine.spoken, ['¡Cuidado! Hueco adelante']);

    await tts.speak('Controles visibles', 1, 0.8);
    await flush();
    expect(engine.stopCalls, 0, reason: 'la alerta no se interrumpe');
    expect(engine.spoken, ['¡Cuidado! Hueco adelante']);

    engine.finishCurrent();
    await flush();
    expect(engine.spoken, ['¡Cuidado! Hueco adelante', 'Controles visibles']);
  });

  test('una alerta interrumpe una frase normal', () async {
    await tts.speak('Asistencia iniciada', 1, 0.8);
    await flush();
    await tts.speak('¡Cuidado! Auto muy cerca', 1, 0.8,
        priority: SpeechPriority.alert);
    await flush();

    expect(engine.stopCalls, greaterThanOrEqualTo(1));
    expect(engine.spoken, ['Asistencia iniciada', '¡Cuidado! Auto muy cerca']);
  });

  test('una frase normal reemplaza a otra normal', () async {
    await tts.speak('uno', 1, 0.8);
    await flush();
    await tts.speak('dos', 1, 0.8);
    await flush();
    expect(engine.spoken, ['uno', 'dos']);
    expect(engine.stopCalls, 1);
  });

  test('alertas seguidas no se cortan entre sí: suena la más reciente después',
      () async {
    await tts.speak('alerta 1', 1, 0.8, priority: SpeechPriority.alert);
    await flush();
    await tts.speak('alerta 2', 1, 0.8, priority: SpeechPriority.alert);
    await tts.speak('alerta 3', 1, 0.8, priority: SpeechPriority.alert);
    await flush();
    expect(engine.stopCalls, 0);

    engine.finishCurrent();
    await flush();
    expect(engine.spoken, ['alerta 1', 'alerta 3']);
  });

  test('frases vacías se ignoran', () async {
    await tts.speak('   ', 1, 0.8);
    await flush();
    expect(engine.spoken, isEmpty);
  });

  test('stop vacía la cola', () async {
    await tts.speak('alerta', 1, 0.8, priority: SpeechPriority.alert);
    await flush();
    await tts.speak('pendiente', 1, 0.8);
    await tts.stop();
    await flush();
    expect(engine.spoken, ['alerta']);
  });
}

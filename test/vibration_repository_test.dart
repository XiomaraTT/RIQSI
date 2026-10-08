import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/data/repositories/vibration_repository_impl.dart';
import 'package:riqsi/features/assistant/domain/entities/proximity.dart';

import 'helpers/fakes.dart';

void main() {
  late List<int> pulses;
  late int cancels;
  late VibrationRepositoryImpl repo;

  setUp(() {
    pulses = [];
    cancels = 0;
    repo = VibrationRepositoryImpl(
      hasVibrator: () async => true,
      vibrate: pulses.add,
      cancel: () => cancels++,
    );
  });

  tearDown(() => repo.dispose());

  test('normalize: "inmediato" equivale a "muy_cerca"', () {
    expect(Proximity.normalize('inmediato'), Proximity.muyCerca);
    expect(Proximity.normalize('muy_cerca'), Proximity.muyCerca);
    expect(Proximity.normalize(' Cerca '), Proximity.cerca);
    expect(Proximity.normalize('raro'), isNull);
    expect(Proximity.normalize(null), isNull);
  });

  test('"inmediato" activa el patrón de muy_cerca', () async {
    repo.triggerProximityFeedback('inmediato');
    await flush();
    expect(repo.currentDistance, Proximity.muyCerca);
    expect(repo.isLoopActive, isTrue);
    expect(pulses, [140]);
  });

  test('un valor desconocido no cancela la vibración activa', () async {
    repo.triggerProximityFeedback('cerca');
    await flush();
    expect(repo.isLoopActive, isTrue);

    repo.triggerProximityFeedback('valor_raro');
    await flush();
    expect(repo.currentDistance, Proximity.cerca);
    expect(repo.isLoopActive, isTrue);
    expect(cancels, 0);
  });

  test('despejado detiene el bucle', () async {
    repo.triggerProximityFeedback('muy_cerca');
    await flush();
    repo.triggerProximityFeedback('despejado');
    await flush();
    expect(repo.isLoopActive, isFalse);
    expect(cancels, 1);
  });

  test('dispose cancela los timers', () async {
    repo.triggerProximityFeedback('cerca');
    await flush();
    repo.dispose();
    expect(repo.isLoopActive, isFalse);
  });

  test('cambios rápidos no dejan dos bucles vivos', () async {
    repo.triggerProximityFeedback('cerca');
    repo.stop();
    repo.triggerProximityFeedback('cerca');
    await flush();
    expect(repo.isLoopActive, isTrue);
    // Un solo bucle de 650 ms: pulso inicial + 1 periódico.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(pulses, [180, 180]);
    repo.stop();
    expect(repo.isLoopActive, isFalse);
  });
}

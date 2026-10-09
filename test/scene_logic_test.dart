import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/domain/scene/scene_logic.dart';

RawDetection det(String c, List<double> b, [double conf = 0.8]) => RawDetection(
    className: c, confidence: conf, left: b[0], top: b[1], right: b[2], bottom: b[3]);

const big = [0.15, 0.2, 0.85, 0.99]; // muy cerca
const small = [0.47, 0.42, 0.52, 0.5]; // lejos

SceneResult run(List<RawDetection> d, {SceneAnalyzer? a, int t = 0}) =>
    (a ?? SceneAnalyzer()).analyse(d, nowMs: t);

void main() {
  test('distancia siempre valida', () {
    const classes = ['car', 'person', 'traffic light', 'fire hydrant', 'bench'];
    const boxes = [
      big,
      small,
      [0.0, 0.0, 1.0, 1.0],
      [0.02, 0.8, 0.1, 0.97],
      [0.47, 0.2, 0.53, 0.6]
    ];
    for (final c in classes) {
      for (final b in boxes) {
        final r = run([det(c, b)]);
        expect(['muy_cerca', 'cerca', 'lejos'], contains(r.top!.distancia));
      }
    }
  });

  test('top es el mas peligroso', () {
    final r = run([
      det('person', small),
      det('car', big),
      det('bench', [0.47, 0.6, 0.53, 0.85])
    ]);
    expect(r.top!.label, 'auto');
    expect(r.objects.first.label, 'auto');
    expect(r.risk, 'Alto');
  });

  test('vehiculo muy cerca es Alto, persona Medio', () {
    for (final c in ['car', 'bus', 'truck', 'motorbike']) {
      final r = run([det(c, big)]);
      expect(r.top!.distancia, 'muy_cerca');
      expect(r.top!.risk, 'Alto');
    }
    expect(run([det('person', big)]).top!.risk, 'Medio');
    expect(run([det('car', big)]).description, contains('Auto'));
  });

  test('NMS elimina duplicado de la misma clase', () {
    final r = run([
      det('motorcycle', [0.15, 0.2, 0.3, 0.4], 0.6),
      det('motorbike', [0.16, 0.21, 0.31, 0.39], 0.9),
      det('car', [0.15, 0.2, 0.3, 0.4], 0.5),
    ]);
    expect(r.objects.length, 2);
  });

  test('descarta clases irrelevantes y baja confianza', () {
    expect(run([det('banana', big)]).isClear, isTrue);
    expect(run([det('car', big, 0.2)]).isClear, isTrue);
  });

  test('histeresis de posicion no alterna', () {
    final a = SceneAnalyzer();
    final seen = <String>{};
    var t = 0;
    for (final xc in [0.36, 0.40, 0.37, 0.40, 0.39, 0.37]) {
      final r = a.analyse([det('person', [xc - 0.1, 0.4, xc + 0.1, 0.5])],
          nowMs: t += 100);
      seen.add(r.top!.pos);
    }
    expect(seen.length, 1);
    expect(run([det('person', [0.05, 0.4, 0.15, 0.5])]).top!.pos, 'izquierda');
    expect(run([det('person', [0.85, 0.4, 0.95, 0.5])]).top!.pos, 'derecha');
  });

  test('cooldown de Alto y Alto nuevo inmediato', () {
    final a = SceneAnalyzer();
    final car = det('car', big);
    expect(a.analyse([car], nowMs: 100000).announce, isTrue);
    expect(a.analyse([car], nowMs: 101000).announce, isFalse);
    expect(a.analyse([car], nowMs: 102600).announce, isTrue);
    final bus = det('bus', [0.0, 0.2, 0.4, 0.99]);
    expect(a.analyse([car, bus], nowMs: 102700).announce, isTrue);
  });

  test('repeticion de escena 6.5 s', () {
    final a = SceneAnalyzer();
    final p = det('person', small);
    expect(a.analyse([p], nowMs: 100000).announce, isTrue);
    expect(a.analyse([p], nowMs: 104500).announce, isFalse);
    expect(a.analyse([p], nowMs: 106600).announce, isTrue);
  });

  test('plurales', () {
    expect(pluralizeEs('camión'), 'camiones');
    expect(pluralizeEs('señal de pare'), 'señales de pare');
    expect(pluralizeEs('autobús'), 'autobuses');
    expect(pluralizeEs('persona'), 'personas');
    final r = run([
      det('truck', [0.02, 0.4, 0.1, 0.5]),
      det('truck', [0.15, 0.4, 0.23, 0.5])
    ]);
    expect(r.description, contains('camiones'));
  });

  test('semaforo sin consejo', () {
    final r = run([det('traffic light', [0.47, 0.2, 0.52, 0.3])]);
    expect(r.top!.advice, '');
    expect(r.risk, 'Bajo');
    expect(r.description, isNot(contains('Desvíate')));
  });

  test('persona muy cerca al centro da frase con consejo', () {
    final r = run([det('person', [0.3, 0.2, 0.7, 0.99])]);
    expect(r.description, startsWith('Persona muy cerca al centro.'));
    expect(r.description, contains('Desvíate'));
  });

  test('vacio', () {
    final r = run([]);
    expect(r.isClear, isTrue);
    expect(r.distancia, 'despejado');
    expect(r.description, 'Camino despejado');
    expect(r.top, isNull);
  });
}

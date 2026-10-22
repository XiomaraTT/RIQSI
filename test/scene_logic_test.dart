import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/assistant/data/datasources/labels_datasource.dart';
import 'package:riqsi/features/assistant/domain/scene/scene_logic.dart';

RawDetection det(String c, List<double> b, [double conf = 0.8]) => RawDetection(
    className: c, confidence: conf, left: b[0], top: b[1], right: b[2], bottom: b[3]);

const big = [0.15, 0.2, 0.85, 0.99]; // muy cerca
const small = [0.47, 0.42, 0.52, 0.5]; // lejos

/// Mismo contenido que assets/labels.txt
const labelsTxt = '''Barandas
Billete
LLave
Laptop
Lentes
Mesa
Mochila
Persona
Puerta
Silla
escaleras
''';

final labels = parseLabels(labelsTxt);

/// Helper para crear analizador. confirm=1 permite probar fotogramas únicos.
SceneAnalyzer analyzer({int confirm = 1}) =>
    SceneAnalyzer(labels: labels, confirmFrames: confirm);

SceneResult run(List<RawDetection> d, {SceneAnalyzer? a, int t = 0}) =>
    (a ?? analyzer()).analyse(d, nowMs: t);

void main() {
  test('labels.txt se lee sin lineas vacias ni CRLF', () {
    expect(labels.length, 11);
    expect(labels.first, 'Barandas');
    expect(labels.last, 'escaleras');
    expect(labels, contains('Persona'));
    expect(parseLabels('\n  Silla \r\n\r\nMesa\n'), ['Silla', 'Mesa']);
  });

  test('el archivo real assets/labels.txt tiene 11 clases', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loaded = await loadModelLabels();
    expect(loaded, labels);
  });

  test('distancia siempre valida', () {
    const classes = ['Silla', 'Puerta', 'escaleras', 'Persona', 'LLave'];
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
        if (!r.isClear) {
          expect(['muy_cerca', 'cerca', 'lejos'], contains(r.top!.distancia));
        }
      }
    }
  });

  test('top es el mas peligroso', () {
    final r = run([
      det('Silla', small),
      det('escaleras', big, 0.9),
      det('Mesa', [0.47, 0.6, 0.53, 0.85])
    ]);
    expect(r.top!.label, 'escaleras');
    expect(r.objects.first.label, 'escaleras');
    expect(r.risk, 'Alto');
  });

  test('escaleras cerca con alta confianza es Alto, obstaculo y persona Medio, objeto Bajo', () {
    final r = run([det('escaleras', big, 0.9)]);
    expect(r.top!.distancia, 'muy_cerca');
    expect(r.top!.risk, 'Alto');
    expect(r.description, startsWith('¡Cuidado! Escaleras muy cerca'));
    expect(r.description, contains('Detente'));

    for (final c in ['Silla', 'Mesa', 'Puerta', 'Barandas', 'Persona']) {
      expect(run([det(c, big, 0.8)]).top!.risk, 'Medio');
    }
    final obj = run([det('Lentes', big, 0.8)]).top!;
    expect(obj.risk, 'Bajo');
    expect(obj.advice, '');
  });

  test('NMS elimina duplicado de la misma clase (IoU 0.40)', () {
    final r = run([
      det('Silla', [0.15, 0.2, 0.3, 0.4], 0.6),
      det('silla', [0.16, 0.21, 0.31, 0.39], 0.9),
      det('Mesa', [0.15, 0.2, 0.3, 0.4], 0.7),
    ]);
    expect(r.objects.length, 2);
  });

  test('descarta clases fuera de labels.txt y baja confianza', () {
    expect(run([det('car', big)]).isClear, isTrue);
    expect(run([det('Silla', big, 0.39)]).isClear, isTrue);
    expect(run([det('Silla', big, 0.40)]).isClear, isFalse);
    expect(run([det('Persona', big, 0.50)]).isClear, isFalse);
    // Clases sensibles requieren mayor umbral
    expect(run([det('escaleras', big, 0.54)]).isClear, isTrue);
    expect(run([det('Lentes', small, 0.50)]).isClear, isTrue);
    expect(run([det('Lentes', small, 0.70)]).isClear, isFalse);
  });

  test('sin etiquetas cargadas acepta cualquier clase', () {
    final r = SceneAnalyzer(confirmFrames: 1).analyse([det('Lo Que Sea', small, 0.8)], nowMs: 0);
    expect(r.top!.label, 'lo que sea');
  });

  test('histeresis de posicion no alterna', () {
    final a = analyzer();
    final seen = <String>{};
    var t = 0;
    for (final xc in [0.36, 0.40, 0.37, 0.40, 0.39, 0.37]) {
      final r = a.analyse([det('Silla', [xc - 0.1, 0.4, xc + 0.1, 0.5], 0.8)],
          nowMs: t += 100);
      seen.add(r.top!.pos);
    }
    expect(seen.length, 1);
    expect(run([det('Silla', [0.05, 0.4, 0.15, 0.5], 0.8)]).top!.pos, 'izquierda');
    expect(run([det('Silla', [0.85, 0.4, 0.95, 0.5], 0.8)]).top!.pos, 'derecha');
  });

  test('cooldown de Alto 2.5 s y Alto nuevo inmediato', () {
    final a = analyzer();
    final stairs = det('escaleras', big, 0.9);
    expect(a.analyse([stairs], nowMs: 100000).announce, isTrue);
    expect(a.analyse([stairs], nowMs: 101000).announce, isFalse);
    expect(a.analyse([stairs], nowMs: 102600).announce, isTrue);
    final left = det('escaleras', [0.0, 0.2, 0.3, 0.99], 0.9);
    expect(a.analyse([stairs, left], nowMs: 102700).announce, isTrue);
  });

  test('cambio de escena espera 2.5 s', () {
    final a = analyzer();
    expect(a.analyse([det('Silla', small, 0.8)], nowMs: 100000).announce, isTrue);
    final changed = [det('Silla', small, 0.8), det('Lentes', [0.02, 0.4, 0.1, 0.5], 0.8)];
    expect(a.analyse(changed, nowMs: 101500).announce, isFalse);
    expect(a.analyse(changed, nowMs: 102600).announce, isTrue);
  });

  test('repeticion de escena 6.5 s', () {
    final a = analyzer();
    final p = det('Silla', small, 0.8);
    expect(a.analyse([p], nowMs: 100000).announce, isTrue);
    expect(a.analyse([p], nowMs: 104500).announce, isFalse);
    expect(a.analyse([p], nowMs: 106600).announce, isTrue);
  });

  test('plurales', () {
    expect(pluralizeEs('camión'), 'camiones');
    expect(pluralizeEs('señal de pare'), 'señales de pare');
    expect(pluralizeEs('silla'), 'sillas');
    expect(pluralizeEs('llave'), 'llaves');
    expect(pluralizeEs('laptop'), 'laptops');
    expect(pluralizeEs('escaleras'), 'escaleras');
    final r = run([
      det('Silla', [0.02, 0.4, 0.1, 0.5], 0.8),
      det('Silla', [0.15, 0.4, 0.23, 0.5], 0.8)
    ]);
    expect(r.description, contains('2 sillas'));
  });

  test('objeto pequeno sin consejo', () {
    final r = run([det('LLave', [0.47, 0.2, 0.52, 0.3], 0.8)]);
    expect(r.top!.label, 'llave');
    expect(r.top!.advice, '');
    expect(r.risk, 'Bajo');
    expect(r.description, isNot(contains('Desvíate')));
  });

  test('silla muy cerca al centro da frase con consejo', () {
    final r = run([det('Silla', [0.3, 0.2, 0.7, 0.99], 0.8)]);
    expect(r.description, startsWith('Silla muy cerca al centro.'));
    expect(r.description, contains('Desvíate'));
  });

  test('vacio muestra estado neutro y no anuncia por voz', () {
    final r = run([]);
    expect(r.isClear, isTrue);
    expect(r.distancia, 'despejado');
    expect(r.description, noObjectsText);
    expect(r.description, isNot(contains('despejado')));
    expect(r.announce, isFalse);
    expect(r.top, isNull);
  });

  test('confirmacion temporal: un solo cuadro no genera alarma', () {
    final a = analyzer(confirm: 2);
    final stairs = det('escaleras', big, 0.9);
    // Primer cuadro: se detecta pero no se confirma todavía
    expect(a.analyse([stairs], nowMs: 0).isClear, isTrue);
    // Segundo cuadro: se confirma y se emite la detección
    final r = a.analyse([stairs], nowMs: 120);
    expect(r.isClear, isFalse);
    expect(r.announce, isTrue);
    // Un parpadeo aislado de un solo cuadro de otra clase no aparece
    expect(a.analyse([stairs, det('Mesa', big, 0.9)], nowMs: 240).objects.length, 1);
  });

  test('escaleras con confianza media informan pero no son Alto', () {
    final r = run([det('escaleras', big, 0.62)]);
    expect(r.top!.risk, 'Medio');
    expect(r.top!.advice, isNotEmpty);
  });

  test('cajas diminutas o excesivamente grandes se ignoran', () {
    expect(run([det('Silla', [0.5, 0.5, 0.51, 0.51], 0.95)]).isClear, isTrue);
    expect(run([det('Mesa', [0.0, 0.0, 0.99, 0.99], 0.95)]).isClear, isTrue);
  });

  test('quedar sin objetos nunca se anuncia por voz como camino despejado', () {
    final a = analyzer();
    expect(a.analyse([det('Silla', small, 0.8)], nowMs: 100000).announce, isTrue);
    expect(a.analyse([], nowMs: 110000).announce, isFalse);
  });
}

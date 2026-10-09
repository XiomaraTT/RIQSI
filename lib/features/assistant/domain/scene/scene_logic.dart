// Lógica de escena en Dart puro (sin Flutter ni plugins).
// Port de server/riqsi_logic.py: distancia por borde inferior y área, riesgo,
// prioridad, NMS, tracker EMA + histéresis, debouncer de voz y descripción.

/// Detección cruda del modelo, coordenadas NORMALIZADAS 0..1 (origen arriba-izquierda).
class RawDetection {
  const RawDetection({
    required this.className,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Nombre COCO en inglés, p. ej. 'person', 'car', 'traffic light'.
  final String className;
  final double confidence;
  final double left, top, right, bottom;
}

class SceneObject {
  const SceneObject({
    required this.label,
    required this.pos,
    required this.risk,
    required this.distancia,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.advice,
  });

  /// En español, p. ej. 'persona', 'auto'.
  final String label;

  /// 'izquierda' | 'centro' | 'derecha'
  final String pos;

  /// 'Alto' | 'Medio' | 'Bajo'
  final String risk;

  /// 'muy_cerca' | 'cerca' | 'lejos'
  final String distancia;
  final double left, top, right, bottom;

  /// Consejo de esquive ('' si no aplica).
  final String advice;
}

class SceneResult {
  const SceneResult({
    required this.objects,
    required this.top,
    required this.description,
    required this.risk,
    required this.distancia,
    required this.announce,
  });

  final List<SceneObject> objects;
  final SceneObject? top;
  final String description;
  final String risk;
  final String distancia;
  final bool announce;
  bool get isClear => objects.isEmpty;
}

// ---------------------------------------------------------------------------
// Tablas
// ---------------------------------------------------------------------------
const Map<String, int> _riskOrder = {'Bajo': 0, 'Medio': 1, 'Alto': 2};
const Map<String, int> _distOrder = {
  'despejado': -1,
  'lejos': 0,
  'cerca': 1,
  'muy_cerca': 2,
};
const List<String> _levels = ['lejos', 'cerca', 'muy_cerca'];
const int _never = -(1 << 40);

/// Clases COCO relevantes -> español. Lo que no esté aquí se descarta.
const Map<String, String> _translations = {
  'person': 'persona',
  'bicycle': 'bicicleta',
  'car': 'auto',
  'motorcycle': 'moto',
  'bus': 'autobús',
  'truck': 'camión',
  'train': 'tren',
  'boat': 'bote',
  'traffic light': 'semáforo',
  'fire hydrant': 'grifo',
  'stop sign': 'señal de pare',
  'parking meter': 'parquímetro',
  'bench': 'banca',
  'bird': 'ave',
  'cat': 'gato',
  'dog': 'perro',
  'horse': 'caballo',
  'sheep': 'oveja',
  'cow': 'vaca',
  'backpack': 'mochila',
  'umbrella': 'paraguas',
  'handbag': 'bolso',
  'suitcase': 'maleta',
  'chair': 'silla',
  'couch': 'sillón',
  'potted plant': 'planta',
  'bed': 'cama',
  'dining table': 'mesa',
  'tv': 'pantalla',
  'laptop': 'computadora portátil',
  'refrigerator': 'refrigerador',
  'sink': 'lavamanos',
};

const Map<String, String> _aliases = {'motorbike': 'motorcycle'};

const Map<String, String> _pluralOverrides = {
  'autobús': 'autobuses',
  'paraguas': 'paraguas',
  'lavamanos': 'lavamanos',
  'computadora portátil': 'computadoras portátiles',
};

const Set<String> _vehicleKeys = {'car', 'bus', 'truck', 'motorcycle', 'train'};
const Set<String> _nonObstructive = {'traffic light', 'stop sign', 'parking meter'};

String _normalize(String c) {
  final clean = c.toLowerCase().trim().replaceAll('_', ' ');
  return _aliases[clean] ?? clean;
}

String _pluralWord(String w) {
  if (_pluralOverrides.containsKey(w)) return _pluralOverrides[w]!;
  if (w.isEmpty) return w;
  if (w.endsWith('ón')) return '${w.substring(0, w.length - 2)}ones';
  if (w.endsWith('z')) return '${w.substring(0, w.length - 1)}ces';
  if (w.endsWith('s')) return w;
  if ('aeiouáéíóú'.contains(w[w.length - 1])) return '${w}s';
  return '${w}es';
}

/// Plural en español de un nombre (puede ser compuesto: 'señal de pare').
String pluralizeEs(String name) {
  name = name.toLowerCase().trim();
  if (_pluralOverrides.containsKey(name)) return _pluralOverrides[name]!;
  final words = name.split(' ');
  if (words.length > 1) {
    final idx = words.indexOf('de');
    if (idx > 0) {
      return [pluralizeEs(words.sublist(0, idx).join(' ')), ...words.sublist(idx)]
          .join(' ');
    }
    return words.map(_pluralWord).join(' ');
  }
  return _pluralWord(name);
}

// ---------------------------------------------------------------------------
// Geometría / NMS
// ---------------------------------------------------------------------------
double _iou(List<double> a, List<double> b) {
  final xa = a[0] > b[0] ? a[0] : b[0];
  final ya = a[1] > b[1] ? a[1] : b[1];
  final xb = a[2] < b[2] ? a[2] : b[2];
  final yb = a[3] < b[3] ? a[3] : b[3];
  final iw = xb - xa, ih = yb - ya;
  final inter = (iw > 0 ? iw : 0) * (ih > 0 ? ih : 0);
  double ar(List<double> r) {
    final w = r[2] - r[0], h = r[3] - r[1];
    return (w > 0 ? w : 0) * (h > 0 ? h : 0);
  }

  final union = ar(a) + ar(b) - inter;
  return union > 0 ? inter / union : 0.0;
}

List<double> _box(RawDetection d) => [d.left, d.top, d.right, d.bottom];

List<RawDetection> _nms(List<RawDetection> dets, double thr) {
  final ordered = [...dets]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <RawDetection>[];
  for (final d in ordered) {
    final key = _normalize(d.className);
    final dup = kept.any(
        (k) => _normalize(k.className) == key && _iou(_box(k), _box(d)) > thr);
    if (!dup) kept.add(d);
  }
  return kept;
}

// ---------------------------------------------------------------------------
// Distancia / posición con histéresis
// ---------------------------------------------------------------------------
int _levelIndex(double area, double bottom, double s) {
  if ((bottom > 0.85 * s && area > 0.20 * s) || area > 0.50 * s) return 2;
  if (bottom > 0.60 * s || area > 0.10 * s) return 1;
  return 0;
}

int _hysteresis(int? prev, int Function(double) fn) {
  final base = fn(1.0);
  if (prev == null) return base;
  final up = fn(1.1), down = fn(0.9);
  if (up > prev) return up;
  if (down < prev) return down;
  return prev;
}

String _posHysteresis(double xc, String? prev, {double margin = 0.04}) {
  var lo = 0.38, hi = 0.62;
  if (prev == 'izquierda') {
    lo += margin;
  } else if (prev == 'centro' || prev == 'derecha') {
    lo -= margin;
  }
  if (prev == 'derecha') {
    hi -= margin;
  } else if (prev == 'centro' || prev == 'izquierda') {
    hi += margin;
  }
  if (xc < lo) return 'izquierda';
  if (xc > hi) return 'derecha';
  return 'centro';
}

class _Track {
  _Track(this.key, this.box, this.area, this.bottom, this.xc);
  final String key;
  List<double> box;
  double area, bottom, xc;
  int? level;
  String? pos;
  int missed = 0;
}

class _Item {
  _Item(this.obj, this.area);
  final SceneObject obj;
  final double area;
}

int _cmpPriority(_Item a, _Item b) {
  final r = (_riskOrder[b.obj.risk] ?? 0).compareTo(_riskOrder[a.obj.risk] ?? 0);
  if (r != 0) return r;
  final d = (_distOrder[b.obj.distancia] ?? 0).compareTo(_distOrder[a.obj.distancia] ?? 0);
  if (d != 0) return d;
  return b.area.compareTo(a.area);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _where(String pos) => pos == 'centro' ? 'al centro' : 'a la $pos';

/// Estado por sesión (tracker EMA + histéresis + debouncer).
class SceneAnalyzer {
  SceneAnalyzer({double minConfidence = 0.35}) : _minConf = minConfidence;

  final double _minConf;

  static const double _emaAlpha = 0.5;
  static const double _matchIou = 0.3;
  static const int _maxMissed = 5;
  static const int _altoCooldown = 2500;
  static const int _changeCooldown = 3800;
  static const int _repeatCooldown = 6500;

  List<_Track> _tracks = [];
  Set<String> _lastSig = {};
  int _lastTime = _never;
  final Map<String, int> _altoLast = {};

  void reset() {
    _tracks = [];
    _lastSig = {};
    _lastTime = _never;
    _altoLast.clear();
  }

  SceneResult analyse(List<RawDetection> detections, {required int nowMs}) {
    final dets = _nms(
      detections
          .where((d) =>
              d.confidence >= _minConf &&
              _translations.containsKey(_normalize(d.className)))
          .toList(),
      0.5,
    );

    // Emparejar con tracks (misma clase + IoU).
    final pairs = <List<num>>[];
    for (var i = 0; i < dets.length; i++) {
      final key = _normalize(dets[i].className);
      for (var j = 0; j < _tracks.length; j++) {
        if (_tracks[j].key == key) {
          final v = _iou(_box(dets[i]), _tracks[j].box);
          if (v > _matchIou) pairs.add([v, i, j]);
        }
      }
    }
    pairs.sort((a, b) => b[0].compareTo(a[0]));
    final usedD = <int>{}, usedT = <int>{};
    final matches = <int, _Track>{};
    for (final p in pairs) {
      final i = p[1] as int, j = p[2] as int;
      if (usedD.contains(i) || usedT.contains(j)) continue;
      usedD.add(i);
      usedT.add(j);
      matches[i] = _tracks[j];
    }

    final items = <_Item>[];
    final newTracks = <_Track>[];
    for (var i = 0; i < dets.length; i++) {
      final d = dets[i];
      final b = _box(d);
      final w = b[2] - b[0], h = b[3] - b[1];
      final area = (w > 0 ? w : 0.0) * (h > 0 ? h : 0.0);
      final bottom = b[3];
      final xc = (b[0] + b[2]) / 2.0;
      var t = matches[i];
      if (t == null) {
        t = _Track(_normalize(d.className), b, area, bottom, xc);
        newTracks.add(t);
      } else {
        t.area = _emaAlpha * area + (1 - _emaAlpha) * t.area;
        t.bottom = _emaAlpha * bottom + (1 - _emaAlpha) * t.bottom;
        t.xc = _emaAlpha * xc + (1 - _emaAlpha) * t.xc;
        t.box = b;
        t.missed = 0;
      }
      items.add(_classify(d, t));
    }
    final matchedIds = matches.values.toSet();
    for (final t in _tracks) {
      if (!matchedIds.contains(t)) t.missed++;
    }
    _tracks = [..._tracks.where((t) => t.missed <= _maxMissed), ...newTracks];

    items.sort(_cmpPriority);
    final objs = items.map((e) => e.obj).toList();
    if (items.isEmpty) {
      return SceneResult(
        objects: const [],
        top: null,
        description: 'Camino despejado',
        risk: 'Bajo',
        distancia: 'despejado',
        announce: _announceClear(nowMs),
      );
    }
    final top = objs.first;
    return SceneResult(
      objects: objs,
      top: top,
      description: _describe(items),
      risk: top.risk, // el top ya es el de mayor riesgo
      distancia: top.distancia,
      announce: _announce(objs, nowMs),
    );
  }

  _Item _classify(RawDetection d, _Track t) {
    final key = t.key;
    t.pos = _posHysteresis(t.xc, t.pos);
    final pos = t.pos!;
    final area = t.area, bottom = t.bottom;
    t.level = _hysteresis(t.level, (s) => _levelIndex(area, bottom, s));
    final level = _levels[t.level!];
    final nonObs = _nonObstructive.contains(key);

    String advice;
    if (area > 0.60) {
      advice = 'Paso bloqueado. Detente';
    } else if (nonObs) {
      advice = '';
    } else if (pos == 'centro') {
      advice = t.xc <= 0.50 ? 'Desvíate a la derecha' : 'Desvíate a la izquierda';
    } else if (pos == 'izquierda') {
      advice = 'Mantente a la derecha';
    } else {
      advice = 'Mantente a la izquierda';
    }

    String risk, distancia;
    if (nonObs) {
      risk = 'Bajo';
      distancia = level == 'lejos' ? 'lejos' : 'cerca';
    } else if (level == 'muy_cerca') {
      risk = _vehicleKeys.contains(key) ? 'Alto' : 'Medio';
      distancia = 'muy_cerca';
    } else if (level == 'cerca') {
      risk = 'Medio';
      distancia = 'cerca';
    } else {
      risk = 'Bajo';
      distancia = 'lejos';
    }

    final b = _box(d);
    return _Item(
      SceneObject(
        label: _translations[key]!,
        pos: pos,
        risk: risk,
        distancia: distancia,
        left: b[0],
        top: b[1],
        right: b[2],
        bottom: b[3],
        advice: advice,
      ),
      area,
    );
  }

  // ---- Descripción ----
  String _describe(List<_Item> ordered) {
    final top = ordered.first.obj;
    if (top.risk == 'Alto' || top.risk == 'Medio') {
      final lab = _cap(top.label);
      final dist = top.distancia == 'muy_cerca' ? 'muy cerca' : 'cerca';
      final adv = top.advice.isNotEmpty ? ' ${top.advice}.' : '';
      final head = '$lab $dist ${_where(top.pos)}.';
      return top.risk == 'Alto' ? '¡Cuidado! $head$adv' : '$head$adv';
    }
    // Todo Bajo: resumen agrupado por posición.
    final byPos = <String, List<String>>{
      'centro': [],
      'derecha': [],
      'izquierda': [],
    };
    for (final it in ordered) {
      byPos[it.obj.pos]!.add(it.obj.label);
    }
    final sections = <String>[];
    if (byPos['centro']!.isNotEmpty) {
      sections.add('Al frente ${_group(byPos['centro']!)}');
    }
    if (byPos['derecha']!.isNotEmpty) {
      sections.add('${_group(byPos['derecha']!)} a la derecha');
    }
    if (byPos['izquierda']!.isNotEmpty) {
      sections.add('${_group(byPos['izquierda']!)} a la izquierda');
    }
    return '${_cap(sections.join('. '))}.';
  }

  String _group(List<String> labels) {
    final counts = <String, int>{};
    for (final l in labels) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    final items = counts.entries
        .map((e) => e.value > 1 ? '${e.value} ${pluralizeEs(e.key)}' : e.key)
        .toList();
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }

  // ---- Debouncer ----
  bool _announceClear(int now) {
    // Solo se anuncia al pasar de "algo" a "nada"; no se repite.
    if (_lastSig.isEmpty) return false;
    if (now - _lastTime > _changeCooldown) {
      _lastSig = {};
      _lastTime = now;
      return true;
    }
    return false;
  }

  bool _announce(List<SceneObject> objs, int now) {
    String k(SceneObject o) => '${o.label}|${o.pos}';
    final keys = objs.map(k).toSet();
    final altoKeys = objs.where((o) => o.risk == 'Alto').map(k).toSet();

    if (altoKeys.isNotEmpty) {
      final due =
          altoKeys.where((x) => now - (_altoLast[x] ?? _never) >= _altoCooldown).toList();
      _altoLast.removeWhere((_, v) => now - v >= 30000);
      if (due.isNotEmpty) {
        for (final x in due) {
          _altoLast[x] = now;
        }
        _lastSig = keys;
        _lastTime = now;
        return true;
      }
      return false;
    }

    final elapsed = now - _lastTime;
    final changed = keys.length != _lastSig.length || !keys.containsAll(_lastSig);
    if (changed && elapsed > _changeCooldown) {
      _lastSig = keys;
      _lastTime = now;
      return true;
    }
    if (elapsed > _repeatCooldown) {
      _lastSig = keys;
      _lastTime = now;
      return true;
    }
    return false;
  }
}

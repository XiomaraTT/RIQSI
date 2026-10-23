// Lógica de escena en Dart puro (sin Flutter ni plugins).
// Port de server/riqsi_logic.py: distancia por borde inferior y área, riesgo,
// prioridad, NMS, tracker EMA + histéresis, debouncer de voz y descripción.
//
// Las clases válidas se cargan dinámicamente desde `assets/labels.txt`
// (ver [SceneAnalyzer.setLabels]) y corresponden al modelo YOLO propio.
//
// NOTA IMPORTANTE DE ACCESIBILIDAD:
// El modelo NO incluye clase "pared" ni "muro". Por seguridad del usuario
// con discapacidad visual, el sistema NUNCA asume ni anuncia por voz
// "Camino despejado", pues podría chocar contra una pared. En ausencia
// de detecciones se muestra el estado visual neutro [noObjectsText]
// sin emitir avisos de voz falsos.

/// Texto mostrado cuando no se reconoce ningún objeto del catálogo.
const String noObjectsText = 'Sin obstáculos detectados';

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

  /// Nombre de clase tal como lo da el modelo / `labels.txt`,
  /// p. ej. 'Silla', 'Puerta', 'escaleras'.
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

  /// En español y en minúsculas, p. ej. 'silla', 'escaleras'.
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
// Tablas de jerarquía y clasificación
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

/// Clases que representan peligro físico de caída o desnivel.
const Set<String> _highRiskKeys = {'escaleras'};

/// Obstáculos físicos en el camino peatonal.
const Set<String> _obstacleKeys = {'barandas', 'mesa', 'puerta', 'silla', 'persona', 'tacho'};

/// Umbrales de confianza mínimos por clase para prevenir falsos positivos.
/// Se toma el máximo entre este valor y el umbral global.
const Map<String, double> _classMinConfidence = {
  // Peligros: umbral equilibrado
  'escaleras': 0.55,
  'barandas': 0.50,
  'puerta': 0.45,
  'silla': 0.40,
  'persona': 0.30,
  'mochila': 0.35,
  'tacho': 0.45,
  // Clases de escritorio / objetos personales: protegidas contra falsas alarmas
  'pc': 0.60,
  'mesa': 0.60,
  'laptop': 0.65,
  'lentes': 0.70,
  'llave': 0.80,
  'billete': 0.80,
};

/// Fotogramas de confirmación por clase (las personas se anuncian más rápido).
const Map<String, int> _classConfirmFrames = {'persona': 2};

/// Confianza mínima requerida para escalar a riesgo 'Alto' (alerta prioritaria).
const double _highRiskMinConfidence = 0.65;

/// Área mínima de la caja (fracción del cuadro) para descartar ruido diminuto.
const double _minBoxArea = 0.003;

/// Área máxima de la caja para descartar falsas detecciones por cámara tapada.
const double _maxBoxArea = 0.92;

/// Variantes de nombres para normalización.
const Map<String, String> _aliases = {
  'escalera': 'escaleras',
  'baranda': 'barandas',
  'tachos': 'tacho',
  'papelera': 'tacho',
  'basurero': 'tacho',
  'computadora': 'pc',
  'ordenador': 'pc',
};

const Map<String, String> _pluralOverrides = {
  'autobús': 'autobuses',
  'paraguas': 'paraguas',
  'lavamanos': 'lavamanos',
  'computadora portátil': 'computadoras portátiles',
  'laptop': 'laptops',
  'carnet': 'carnets',
  'pc': 'computadoras',
  'tacho': 'tachos',
};

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

/// Plural en español de un nombre (admite compuestos).
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

/// Nombre natural hablado para síntesis de voz (TTS).
String _spokenLabel(String label) {
  final clean = label.toLowerCase().trim();
  if (clean == 'pc') return 'computadora';
  return clean;
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

List<RawDetection> _nms(List<RawDetection> dets, double thr, [String Function(String)? resolveClass]) {
  final ordered = [...dets]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <RawDetection>[];
  for (final d in ordered) {
    final key = resolveClass != null ? resolveClass(d.className) : _normalize(d.className);
    final dup = kept.any(
        (k) => (resolveClass != null ? resolveClass(k.className) : _normalize(k.className)) == key && _iou(_box(k), _box(d)) > thr);
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
  int hits = 1;
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

/// Analizador de escena en tiempo real con filtro de falsas alarmas,
/// histéresis espacial y debouncer de voz.
class SceneAnalyzer {
  SceneAnalyzer({
    double minConfidence = defaultMinConfidence,
    double nmsIou = defaultNmsIou,
    Iterable<String>? labels,
    int confirmFrames = defaultConfirmFrames,
  })  : _minConf = minConfidence,
        _nmsIou = nmsIou,
        _confirmFrames = confirmFrames < 1 ? 1 : confirmFrames {
    if (labels != null) setLabels(labels);
  }

  /// Confianza mínima por defecto.
  static const double defaultMinConfidence = 0.25;

  /// IoU de NMS por clase.
  static const double defaultNmsIou = 0.45;

  /// Fotogramas consecutivos necesarios para confirmar un objeto nuevo.
  /// 1 permite respuesta instantánea al enfocar un obstáculo.
  static const int defaultConfirmFrames = 3;

  double _minConf;
  final double _nmsIou;
  final int _confirmFrames;

  /// Lista ordenada de clases (para mapear por índice si el modelo emite enteros).
  List<String> _labelsList = [];

  /// Clases conocidas (normalizadas), cargadas desde `labels.txt`.
  Set<String> _known = {};

  static const double _emaAlpha = 0.5;
  static const double _matchIou = 0.3;
  static const int _maxMissed = 5;

  /// Cooldown entre avisos repetidos del mismo peligro Alto (2.0 s).
  static const int _altoCooldown = 2000;

  /// Cooldown mínimo al cambiar la escena antes de nuevo aviso por voz (1.2 s).
  static const int _changeCooldown = 1800;

  /// Intervalo máximo para refrescar la descripción si la escena sigue igual (6.5 s).
  static const int _repeatCooldown = 6500;

  List<_Track> _tracks = [];
  Set<String> _lastSig = {};
  int _lastTime = _never;
  final Map<String, int> _altoLast = {};

  /// Confianza mínima actual (ajustable según la sensibilidad del usuario).
  double get minConfidence => _minConf;
  set minConfidence(double value) => _minConf = value.clamp(0.0, 1.0);

  /// Clases que acepta el analizador, normalizadas.
  Set<String> get labels => Set.unmodifiable(_known);

  /// Define las clases válidas. Con conjunto vacío acepta cualquier clase.
  void setLabels(Iterable<String> labels) {
    _labelsList = labels.map(_normalize).where((l) => l.isNotEmpty).toList();
    _known = _labelsList.toSet();
  }

  /// Resuelve la clase a partir del nombre o de su índice entero de salida.
  String _resolveClassName(String raw) {
    final trimmed = raw.trim();
    final idx = int.tryParse(trimmed);
    if (idx != null && idx >= 0 && idx < _labelsList.length) {
      return _labelsList[idx];
    }
    return _normalize(trimmed);
  }

  bool _accepts(String key) => _known.isEmpty || _known.contains(key);

  /// Filtro estricto de entrada para descartar detecciones espurias y ruido.
  bool _passesFilters(RawDetection d) {
    final key = _resolveClassName(d.className);
    if (!_accepts(key)) return false;

    // Umbral de clase específico vs umbral general
    final classMin = _classMinConfidence[key];
    final needed = classMin != null && classMin > _minConf ? classMin : _minConf;
    if (d.confidence < needed) return false;

    // Validación de dimensiones y área de la caja
    final w = d.right - d.left;
    final h = d.bottom - d.top;
    if (w <= 0 || h <= 0) return false;
    final area = w * h;
    return area >= _minBoxArea && area <= _maxBoxArea;
  }

  void reset() {
    _tracks = [];
    _lastSig = {};
    _lastTime = _never;
    _altoLast.clear();
  }

  SceneResult analyse(List<RawDetection> detections, {required int nowMs}) {
    // 1. Filtrado de ruido y confianza mínima
    final validDets = detections.where(_passesFilters).toList();

    // 2. NMS (supresión de no-máximos)
    final dets = _nms(validDets, _nmsIou, _resolveClassName);

    // 3. Emparejar con tracks existentes (misma clase + IoU suficiente)
    final pairs = <List<num>>[];
    for (var i = 0; i < dets.length; i++) {
      final key = _resolveClassName(dets[i].className);
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
        t = _Track(_resolveClassName(d.className), b, area, bottom, xc);
        newTracks.add(t);
      } else {
        // Suavizado EMA de posición y dimensiones
        t.area = _emaAlpha * area + (1 - _emaAlpha) * t.area;
        t.bottom = _emaAlpha * bottom + (1 - _emaAlpha) * t.bottom;
        t.xc = _emaAlpha * xc + (1 - _emaAlpha) * t.xc;
        t.box = b;
        t.missed = 0;
        t.hits++;
      }

      // Confirmación temporal: descartar objetos de 1 solo cuadro para evitar falsas alarmas
      final need = _confirmFrames < (_classConfirmFrames[t.key] ?? _confirmFrames)
          ? _confirmFrames
          : (_classConfirmFrames[t.key] ?? _confirmFrames);
      if (t.hits < need) continue;

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
        description: noObjectsText,
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
      risk: top.risk,
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

    final isHighRiskClass = _highRiskKeys.contains(key);
    // Solo eleva a riesgo 'Alto' si la confianza de detección supera el umbral estricto
    final highRisk = isHighRiskClass && d.confidence >= _highRiskMinConfidence;
    final isObstacle = _obstacleKeys.contains(key);
    final nonObs = !isHighRiskClass && !isObstacle;

    String advice;
    if (nonObs) {
      advice = '';
    } else if (isHighRiskClass && level != 'lejos') {
      advice = 'Detente y avanza con cuidado';
    } else if (area > 0.60) {
      advice = 'Paso bloqueado. Detente';
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
      risk = highRisk ? 'Alto' : 'Medio';
      distancia = 'muy_cerca';
    } else if (level == 'cerca') {
      risk = highRisk ? 'Alto' : 'Medio';
      distancia = 'cerca';
    } else {
      risk = 'Bajo';
      distancia = 'lejos';
    }

    final b = _box(d);
    return _Item(
      SceneObject(
        label: key,
        pos: pos,
        risk: risk,
        distancia: distancia,
        left: b[0].clamp(0.0, 1.0),
        top: b[1].clamp(0.0, 1.0),
        right: b[2].clamp(0.0, 1.0),
        bottom: b[3].clamp(0.0, 1.0),
        advice: advice,
      ),
      area,
    );
  }

  // ---- Descripción hablada ----
  String _describe(List<_Item> ordered) {
    final top = ordered.first.obj;
    if (top.risk == 'Alto' || top.risk == 'Medio') {
      final lab = _cap(_spokenLabel(top.label));
      final dist = top.distancia == 'muy_cerca' ? 'muy cerca' : 'cerca';
      final adv = top.advice.isNotEmpty ? ' ${top.advice}.' : '';
      final head = '$lab $dist ${_where(top.pos)}.';
      return top.risk == 'Alto' ? '¡Cuidado! $head$adv' : '$head$adv';
    }

    // Objetos de riesgo Bajo: resumen agrupado por posición sin tono de alerta
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
      final spoken = _spokenLabel(l);
      counts[spoken] = (counts[spoken] ?? 0) + 1;
    }
    final items = counts.entries
        .map((e) => e.value > 1 ? '${e.value} ${pluralizeEs(e.key)}' : e.key)
        .toList();
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }

  // ---- Debouncer de voz ----

  /// En ausencia de objetos, NUNCA se emite aviso de voz porque el modelo
  /// no detecta paredes y decir "camino despejado" sería engañoso.
  bool _announceClear(int now) {
    if (_lastSig.isNotEmpty && now - _lastTime > _changeCooldown) {
      _lastSig = {};
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

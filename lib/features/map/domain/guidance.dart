import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'entities/walking_route.dart';

export 'entities/walking_route.dart';

// ---------------------------------------------------------------------------
// Textos en español
// ---------------------------------------------------------------------------

/// Redondea metros para decirlos en voz: <100 m de 5 en 5, si no de 10 en 10.
int roundMeters(double meters) {
  if (meters <= 0) return 0;
  if (meters < 10) return meters.round();
  if (meters < 100) return (meters / 5).round() * 5;
  return (meters / 10).round() * 10;
}

/// "120 metros", "1,5 kilómetros".
String formatDistance(double meters) {
  if (meters >= 1000) {
    final km = (meters / 100).round() / 10;
    final txt = km == km.roundToDouble()
        ? km.toInt().toString()
        : km.toString().replaceAll('.', ',');
    return km == 1 ? '1 kilómetro' : '$txt kilómetros';
  }
  final m = roundMeters(meters);
  return m == 1 ? '1 metro' : '$m metros';
}

String _turnPhrase(String? modifier) {
  switch (modifier) {
    case 'right':
      return 'Gira a la derecha';
    case 'left':
      return 'Gira a la izquierda';
    case 'slight right':
      return 'Gira ligeramente a la derecha';
    case 'slight left':
      return 'Gira ligeramente a la izquierda';
    case 'sharp right':
      return 'Gira completamente a la derecha';
    case 'sharp left':
      return 'Gira completamente a la izquierda';
    case 'uturn':
      return 'Da media vuelta';
    default:
      return 'Sigue recto';
  }
}

/// Convierte un paso de OSRM (maneuver.type / modifier, name, distance) a una
/// instrucción en español.
String spanishInstruction({
  required String type,
  String? modifier,
  String name = '',
  double distance = 0,
  int? exit,
}) {
  final street = name.trim();
  switch (type) {
    case 'arrive':
      return 'Has llegado a tu destino';
    case 'depart':
      final d = distance > 0 ? ' ${formatDistance(distance)}' : '';
      return 'Sigue recto$d${street.isNotEmpty ? ' por $street' : ''}';
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
      final salida = exit != null ? ', toma la salida $exit' : '';
      return 'Entra a la rotonda$salida'
          '${street.isNotEmpty ? ' hacia $street' : ''}';
    case 'exit roundabout':
    case 'exit rotary':
      return 'Sal de la rotonda${street.isNotEmpty ? ' hacia $street' : ''}';
  }
  final phrase = _turnPhrase(modifier);
  if (phrase == 'Sigue recto') {
    final d = distance > 0 ? ' ${formatDistance(distance)}' : '';
    return 'Sigue recto$d${street.isNotEmpty ? ' por $street' : ''}';
  }
  return '$phrase${street.isNotEmpty ? ' en $street' : ''}';
}

// ---------------------------------------------------------------------------
// Motor de guía
// ---------------------------------------------------------------------------

enum GuidanceEventType { start, prepare, turn, arrived, offRoute }

/// Algo que hay que anunciar (voz + vibración opcional).
class GuidanceEvent {
  final GuidanceEventType type;
  final String message;

  /// Lado del giro para la vibración (solo en anuncios de giro a ~15 m).
  final TurnSide haptic;

  const GuidanceEvent(this.type, this.message, {this.haptic = TurnSide.none});

  @override
  String toString() => 'GuidanceEvent($type, "$message", $haptic)';
}

/// Estado de la guía tras una lectura de GPS.
class GuidanceSnapshot {
  /// Índice (en route.steps) de la próxima maniobra.
  final int nextStepIndex;
  final RouteStep nextStep;
  final double distanceToNext;
  final double distanceToDestination;

  /// Distancia (m) entre el usuario y la polilínea.
  final double offRouteMeters;
  final bool arrived;
  final bool needsReroute;
  final List<GuidanceEvent> events;

  const GuidanceSnapshot({
    required this.nextStepIndex,
    required this.nextStep,
    required this.distanceToNext,
    required this.distanceToDestination,
    required this.offRouteMeters,
    required this.arrived,
    required this.needsReroute,
    required this.events,
  });
}

/// Motor puro (sin Flutter ni red): dada la ruta y cada posición, decide
/// el paso actual, la distancia al próximo giro y qué anunciar.
class GuidanceEngine {
  final WalkingRoute route;
  final double prepareDistance;
  final double turnDistance;
  final double arrivalDistance;
  final double offRouteDistance;
  final int offRouteReadings;

  /// Lecturas con peor precisión que esto no cuentan para el desvío.
  final double maxAccuracyForOffRoute;

  late final List<_P> _pts;
  late final List<double> _cum;
  late final List<double> _maneuverAlong;
  late final double _lat0;
  late final double _lon0;

  int _next = 1;
  final Set<int> _prepared = {};
  int _offCount = 0;
  bool _arrived = false;
  bool _awaitingReroute = false;
  GuidanceSnapshot? _last;

  GuidanceEngine(
    this.route, {
    this.prepareDistance = 50,
    this.turnDistance = 15,
    this.arrivalDistance = 15,
    this.offRouteDistance = 35,
    this.offRouteReadings = 2,
    this.maxAccuracyForOffRoute = 50,
  }) {
    final geom = route.geometry.isNotEmpty
        ? route.geometry
        : route.steps.map((s) => s.location).toList();
    _lat0 = geom.first.latitude;
    _lon0 = geom.first.longitude;
    _pts = geom.map(_project).toList();
    _cum = List<double>.filled(_pts.length, 0);
    for (var i = 1; i < _pts.length; i++) {
      _cum[i] = _cum[i - 1] + _pts[i].dist(_pts[i - 1]);
    }
    // Posición de cada maniobra a lo largo de la polilínea (búsqueda hacia
    // adelante: OSRM pone cada maniobra sobre un vértice de la geometría).
    _maneuverAlong = [];
    var from = 0;
    for (final s in route.steps) {
      final p = _project(s.location);
      var best = from;
      var bestD = double.infinity;
      for (var i = from; i < _pts.length; i++) {
        final d = _pts[i].dist(p);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      _maneuverAlong.add(_cum[best]);
      from = best;
    }
    if (route.steps.length < 2) _next = route.steps.length - 1;
  }

  double get totalLength => _cum.isEmpty ? 0 : _cum.last;
  bool get arrived => _arrived;
  int get nextStepIndex => _next;
  RouteStep get nextStep => route.steps[_next];
  GuidanceSnapshot? get lastSnapshot => _last;

  /// Anuncio inicial (al empezar la ruta o tras recalcularla).
  GuidanceEvent start({String? destinationName, bool reroute = false}) {
    final first = route.steps.first;
    final firstText = first.isDeparture || route.steps.length == 1
        ? first.instruction
        : route.steps[_next].instruction;
    if (reroute) {
      return GuidanceEvent(
        GuidanceEventType.start,
        'Ruta recalculada. $firstText.',
      );
    }
    final dest = (destinationName ?? '').trim();
    final minutes = math.max(1, (route.duration / 60).round());
    return GuidanceEvent(
      GuidanceEventType.start,
      'Ruta a pie${dest.isNotEmpty ? ' hacia $dest' : ''} iniciada. '
      '${formatDistance(route.distance)}, unos $minutes '
      '${minutes == 1 ? 'minuto' : 'minutos'}. $firstText.',
    );
  }

  /// Texto para el botón "Repetir".
  String repeatText() {
    if (_arrived) return 'Has llegado a tu destino.';
    final step = nextStep;
    final d = _last?.distanceToNext;
    if (step.isArrival) {
      return d == null
          ? 'Sigue la ruta hasta tu destino.'
          : 'Tu destino está a ${formatDistance(d)}.';
    }
    if (d == null) return '${step.instruction}.';
    return 'En ${formatDistance(d)}, ${_lowerFirst(step.instruction)}.';
  }

  /// Procesa una lectura de GPS.
  GuidanceSnapshot update(LatLng position, {double? accuracy}) {
    final events = <GuidanceEvent>[];
    final proj = _projectOnRoute(_project(position));
    final along = proj.along;
    final cross = proj.cross;
    final toDest = math.max(0.0, totalLength - along);

    if (_arrived || _awaitingReroute) {
      return _snap(along, cross, toDest, events);
    }

    // --- Desvío ---
    final reliable =
        accuracy == null || accuracy <= maxAccuracyForOffRoute;
    if (cross > offRouteDistance && reliable) {
      _offCount++;
      if (_offCount >= offRouteReadings) {
        _offCount = 0;
        _awaitingReroute = true;
        events.add(const GuidanceEvent(
          GuidanceEventType.offRoute,
          'Te has desviado. Recalculando ruta.',
        ));
        return _snap(along, cross, toDest, events);
      }
    } else if (cross <= offRouteDistance) {
      _offCount = 0;
    }

    // --- Llegada ---
    final destPoint = _project(route.steps.last.location);
    final straightToDest = _project(position).dist(destPoint);
    final last = route.steps.length - 1;
    if (_next >= last &&
        (toDest <= arrivalDistance || straightToDest <= arrivalDistance)) {
      _arrived = true;
      events.add(const GuidanceEvent(
        GuidanceEventType.arrived,
        'Has llegado a tu destino.',
      ));
      return _snap(along, cross, 0, events);
    }

    // --- Giro inminente (~15 m): anunciar y pasar al siguiente paso ---
    var remaining = _maneuverAlong[_next] - along;
    if (_next < last && remaining <= turnDistance) {
      final step = route.steps[_next];
      final follow = step.distance > 0 && step.isTurn
          ? ' y sigue ${formatDistance(step.distance)}'
          : '';
      events.add(GuidanceEvent(
        GuidanceEventType.turn,
        'Ahora, ${_lowerFirst(step.instruction)}$follow.',
        haptic: step.side,
      ));
      _prepared.add(_next);
      _next++;
      remaining = _maneuverAlong[_next] - along;
    }

    // --- Aviso previo (~50 m) ---
    if (!_prepared.contains(_next) &&
        remaining <= prepareDistance &&
        remaining > turnDistance) {
      final step = route.steps[_next];
      _prepared.add(_next);
      if (step.isArrival) {
        events.add(GuidanceEvent(
          GuidanceEventType.prepare,
          'Tu destino está a ${formatDistance(remaining)}.',
        ));
      } else if (step.isTurn) {
        events.add(GuidanceEvent(
          GuidanceEventType.prepare,
          'En ${formatDistance(remaining)}, ${_lowerFirst(step.instruction)}.',
        ));
      }
    }

    return _snap(along, cross, toDest, events);
  }

  GuidanceSnapshot _snap(
    double along,
    double cross,
    double toDest,
    List<GuidanceEvent> events,
  ) {
    final s = GuidanceSnapshot(
      nextStepIndex: _next,
      nextStep: route.steps[_next],
      distanceToNext: _arrived
          ? 0
          : math.max(0.0, _maneuverAlong[_next] - along),
      distanceToDestination: toDest,
      offRouteMeters: cross,
      arrived: _arrived,
      needsReroute: _awaitingReroute,
      events: events,
    );
    _last = s;
    return s;
  }

  // --- Geometría plana local (equirectangular, suficiente a escala urbana) --

  _P _project(LatLng p) {
    const mPerDegLat = 110574.0;
    final mPerDegLon = 111320.0 * math.cos(_lat0 * math.pi / 180);
    return _P(
      (p.longitude - _lon0) * mPerDegLon,
      (p.latitude - _lat0) * mPerDegLat,
    );
  }

  ({double along, double cross}) _projectOnRoute(_P p) {
    if (_pts.length == 1) return (along: 0, cross: p.dist(_pts.first));
    var bestCross = double.infinity;
    var bestAlong = 0.0;
    for (var i = 0; i < _pts.length - 1; i++) {
      final a = _pts[i];
      final b = _pts[i + 1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final q = _P(a.x + t * dx, a.y + t * dy);
      final d = p.dist(q);
      if (d < bestCross) {
        bestCross = d;
        bestAlong = _cum[i] + t * math.sqrt(len2);
      }
    }
    return (along: bestAlong, cross: bestCross);
  }
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

class _P {
  final double x;
  final double y;
  const _P(this.x, this.y);
  double dist(_P o) {
    final dx = x - o.x;
    final dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

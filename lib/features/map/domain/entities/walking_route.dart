import 'package:latlong2/latlong.dart';

/// Lado del giro, para el patrón de vibración y el icono.
enum TurnSide { none, left, right }

/// Un paso de la ruta a pie (equivale a un `step` de OSRM).
///
/// [location] es el punto donde ocurre la maniobra; [distance] son los
/// metros que se recorren DESPUÉS de la maniobra hasta el siguiente paso.
class RouteStep {
  final String type;
  final String? modifier;
  final String name;
  final double distance;
  final LatLng location;
  final int? exit;

  /// Instrucción en español lista para decir por voz.
  final String instruction;

  const RouteStep({
    required this.type,
    required this.modifier,
    required this.name,
    required this.distance,
    required this.location,
    required this.instruction,
    this.exit,
  });

  bool get isArrival => type == 'arrive';
  bool get isDeparture => type == 'depart';

  TurnSide get side {
    final m = modifier ?? '';
    if (m.contains('right')) return TurnSide.right;
    if (m.contains('left')) return TurnSide.left;
    return TurnSide.none;
  }

  /// Maniobra que exige girar (no solo "sigue recto").
  bool get isTurn =>
      !isArrival &&
      !isDeparture &&
      (side != TurnSide.none ||
          modifier == 'uturn' ||
          type.contains('roundabout') ||
          type.contains('rotary'));
}

/// Ruta peatonal completa: polilínea + pasos.
class WalkingRoute {
  final List<LatLng> geometry;
  final List<RouteStep> steps;

  /// Distancia total en metros y duración estimada en segundos.
  final double distance;
  final double duration;

  const WalkingRoute({
    required this.geometry,
    required this.steps,
    required this.distance,
    required this.duration,
  });
}

/// Lugar encontrado por la búsqueda (Nominatim).
class Place {
  final String name;
  final String address;
  final LatLng location;

  /// Distancia en línea recta desde el usuario (si se conoce).
  final double? distanceMeters;

  const Place({
    required this.name,
    required this.address,
    required this.location,
    this.distanceMeters,
  });

  Place withDistance(double meters) => Place(
    name: name,
    address: address,
    location: location,
    distanceMeters: meters,
  );
}

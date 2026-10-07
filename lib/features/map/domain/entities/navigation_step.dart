import 'package:latlong2/latlong.dart';

enum NavDirection {
  straight,
  right,
  left,
  back,
  arrived,
}

class NavigationStep {
  final String id;
  final NavDirection direction;
  final String instruction;
  final int distanceMeters;
  final String streetName;
  final String? warning;
  final LatLng? point;

  const NavigationStep({
    required this.id,
    required this.direction,
    required this.instruction,
    required this.distanceMeters,
    required this.streetName,
    this.warning,
    this.point,
  });

  String get directionTitle {
    switch (direction) {
      case NavDirection.straight:
        return "DE FRENTE";
      case NavDirection.right:
        return "GIRA A LA DERECHA";
      case NavDirection.left:
        return "GIRA A LA IZQUIERDA";
      case NavDirection.back:
        return "DA MEDIA VUELTA (ATRÁS)";
      case NavDirection.arrived:
        return "HAS LLEGADO";
    }
  }

  String get spokenText {
    switch (direction) {
      case NavDirection.straight:
        return "Continúa de frente por $distanceMeters metros en $streetName. $instruction";
      case NavDirection.right:
        return "En $distanceMeters metros, gira a la derecha hacia $streetName. $instruction";
      case NavDirection.left:
        return "En $distanceMeters metros, gira a la izquierda hacia $streetName. $instruction";
      case NavDirection.back:
        return "Alerta: Da media vuelta. Ve hacia atrás para retomar tu ruta en $streetName. $instruction";
      case NavDirection.arrived:
        return "¡Has llegado a tu destino! $instruction";
    }
  }

  factory NavigationStep.fromJson(Map<String, dynamic> json) {
    NavDirection parseDirection(String? dir) {
      final d = dir?.toLowerCase().trim() ?? '';
      if (d.contains('right') || d.contains('derecha')) return NavDirection.right;
      if (d.contains('left') || d.contains('izquierda')) return NavDirection.left;
      if (d.contains('back') || d.contains('atras') || d.contains('atrás') || d.contains('uturn')) return NavDirection.back;
      if (d.contains('arrive') || d.contains('llegada') || d.contains('fin')) return NavDirection.arrived;
      return NavDirection.straight;
    }

    return NavigationStep(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      direction: parseDirection(json['direction']?.toString() ?? json['maneuver']?.toString()),
      instruction: json['instruction']?.toString() ?? 'Continúa en tu camino',
      distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? (json['distance'] as num?)?.toInt() ?? 20,
      streetName: json['street_name']?.toString() ?? json['street']?.toString() ?? 'Vía peatonal',
      warning: json['warning']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction.name,
    'instruction': instruction,
    'distance_meters': distanceMeters,
    'street_name': streetName,
    'warning': warning,
  };
}

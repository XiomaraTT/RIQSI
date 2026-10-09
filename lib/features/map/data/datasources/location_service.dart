import 'package:geolocator/geolocator.dart';

enum LocationAccess { granted, serviceOff, denied, deniedForever, unavailable }

/// Envoltorio fino de geolocator (permiso + stream de posición, alta precisión).
class LocationService {
  const LocationService();

  Future<LocationAccess> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      switch (perm) {
        case LocationPermission.denied:
          return LocationAccess.denied;
        case LocationPermission.deniedForever:
          return LocationAccess.deniedForever;
        case LocationPermission.unableToDetermine:
          return LocationAccess.unavailable;
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          return LocationAccess.granted;
      }
    } catch (_) {
      return LocationAccess.unavailable;
    }
  }

  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    ),
  );

  Future<Position?> lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> openSettings(LocationAccess access) async {
    try {
      if (access == LocationAccess.serviceOff) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }

  static String messageFor(LocationAccess access) {
    switch (access) {
      case LocationAccess.granted:
        return '';
      case LocationAccess.serviceOff:
        return 'El GPS está apagado. Actívalo para usar el mapa.';
      case LocationAccess.denied:
        return 'Sin permiso de ubicación. Toca "Activar ubicación" para permitirlo.';
      case LocationAccess.deniedForever:
        return 'El permiso de ubicación está bloqueado. Actívalo en los ajustes de la app.';
      case LocationAccess.unavailable:
        return 'No se pudo acceder a la ubicación de este dispositivo.';
    }
  }
}

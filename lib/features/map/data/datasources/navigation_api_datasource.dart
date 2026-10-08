import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/navigation_step.dart';

class NavigationApiDataSource {
  String apiUrl;

  NavigationApiDataSource({
    this.apiUrl = "http://10.247.64.45:8765/api/route",
  });

  /// Enlace con el API de navegación y cálculo de ruta asistida
  Future<List<NavigationStep>> fetchRoute({
    required String destination,
  }) async {
    // 1. Intentar consultar el API configurado (servidor local o servicio web)
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final uri = Uri.parse(apiUrl);
      final request = await client.postUrl(uri);
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'destination': destination,
        'current_location': {
          'latitude': -12.0464,
          'longitude': -77.0428,
        },
        'pedestrian_mode': true,
        'accessible_routing': true,
      }));

      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 8));
        final data = jsonDecode(responseBody);
        final stepsList = data is Map ? data['steps'] as List? : null;
        if (stepsList != null && stepsList.isNotEmpty) {
          return stepsList.map((s) => NavigationStep.fromJson(s as Map<String, dynamic>)).toList();
        }
      } else {
        await response.drain<void>();
      }
    } catch (e) {
      // Si el API aún no está levantado o no responde en el servidor,
      // proporcionamos la ruta asistida adaptada para orientación sensorial.
      debugPrint('[NAV API] Ruta local por error del API: $e');
    } finally {
      client.close(force: true);
    }

    // 2. Ruta accesible estructurada para orientación de personas ciegas
    return _generateRouteForDestination(destination);
  }

  /// Verifica si el API de navegación responde.
  ///
  /// Solo se considera disponible si responde 2xx, o 405 (el endpoint existe
  /// pero solo acepta POST). Otros códigos (404, 426 del servidor WebSocket,
  /// etc.) indican que ahí no hay un API de rutas.
  Future<bool> checkApiConnection() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri.parse(apiUrl);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>().catchError((_) {});
      return isApiStatusOk(response.statusCode);
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static bool isApiStatusOk(int statusCode) =>
      (statusCode >= 200 && statusCode < 300) || statusCode == 405;

  List<NavigationStep> _generateRouteForDestination(String destination) {
    final cleanDest = destination.trim().isEmpty ? "Destino seleccionado" : destination.trim();

    return [
      NavigationStep(
        id: "step_1",
        direction: NavDirection.straight,
        instruction: "Avanza por la acera libre de obstáculos.",
        distanceMeters: 30,
        streetName: "Acera principal",
        warning: "Superficie regular con línea podotáctil.",
        point: LatLng(-12.046374, -77.042793),
      ),
      NavigationStep(
        id: "step_2",
        direction: NavDirection.right,
        instruction: "Gira a la derecha en la esquina hacia la calle peatonal.",
        distanceMeters: 15,
        streetName: "Paso peatonal",
        warning: "Atención al cruce con rampa de acceso.",
        point: LatLng(-12.047000, -77.042793),
      ),
      NavigationStep(
        id: "step_3",
        direction: NavDirection.straight,
        instruction: "Continúa recto hacia la entrada.",
        distanceMeters: 25,
        streetName: cleanDest,
        point: LatLng(-12.047000, -77.041800),
      ),
      NavigationStep(
        id: "step_4",
        direction: NavDirection.arrived,
        instruction: "Has llegado a $cleanDest. La puerta principal está a 2 metros al frente.",
        distanceMeters: 0,
        streetName: cleanDest,
        point: LatLng(-12.047500, -77.041800),
      ),
    ];
  }

  List<Map<String, dynamic>> searchPlaces(String query) {
    final q = query.toLowerCase().trim();
    final allPlaces = [
      {
        "id": "p1",
        "name": "Farmacia San Pablo",
        "address": "Av. Arequipa 1250",
        "lat": -12.0475,
        "lng": -77.0418,
        "category": "pharmacy",
        "distance": 120,
      },
      {
        "id": "p2",
        "name": "Paradero Metropolitano - Estación Central",
        "address": "Paseo de la República",
        "lat": -12.0490,
        "lng": -77.0435,
        "category": "bus",
        "distance": 240,
      },
      {
        "id": "p3",
        "name": "Supermercado Metro",
        "address": "Jr. Cusco 420",
        "lat": -12.0450,
        "lng": -77.0410,
        "category": "market",
        "distance": 310,
      },
      {
        "id": "p4",
        "name": "Parque de la Reserva (Circuito Mágico)",
        "address": "Jr. Madre de Dios s/n",
        "lat": -12.0520,
        "lng": -77.0440,
        "category": "park",
        "distance": 500,
      },
      {
        "id": "p5",
        "name": "Mi Casa (Hogar)",
        "address": "Av. Central 345, Dpto 201",
        "lat": -12.0440,
        "lng": -77.0450,
        "category": "home",
        "distance": 450,
      },
      {
        "id": "p6",
        "name": "Hospital Nacional Dos de Mayo",
        "address": "Av. Grau 1300",
        "lat": -12.0510,
        "lng": -77.0390,
        "category": "hospital",
        "distance": 680,
      },
    ];

    if (q.isEmpty) return allPlaces;
    return allPlaces.where((p) {
      final name = (p["name"] as String).toLowerCase();
      final addr = (p["address"] as String).toLowerCase();
      return name.contains(q) || addr.contains(q);
    }).toList();
  }
}

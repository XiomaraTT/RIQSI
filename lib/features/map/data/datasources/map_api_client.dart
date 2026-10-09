import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../domain/guidance.dart';

/// Error de red/servicio con un mensaje listo para mostrar y decir por voz.
class MapApiException implements Exception {
  final String message;
  const MapApiException(this.message);
  @override
  String toString() => message;
}

const String kNoInternetMessage = 'Sin internet: el mapa necesita datos.';

/// Cliente de OpenStreetMap: búsqueda y dirección (Nominatim) y rutas a pie
/// (OSRM). El [http.Client] se inyecta para poder testear sin red.
class MapApiClient {
  static const userAgent = 'RIQSI/1.0 (app accesible)';
  static const nominatimHost = 'nominatim.openstreetmap.org';
  static const osrmBase =
      'https://routing.openstreetmap.de/routed-foot/route/v1/foot';

  final http.Client _client;
  final Duration timeout;

  /// Nominatim exige como máximo 1 petición por segundo.
  final Duration minNominatimInterval;
  DateTime? _lastNominatim;

  MapApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
    this.minNominatimInterval = const Duration(seconds: 1),
  }) : _client = client ?? http.Client();

  void close() => _client.close();

  Map<String, String> get _headers => const {
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };

  Future<dynamic> _getJson(Uri uri, {bool nominatim = false}) async {
    if (nominatim) {
      final last = _lastNominatim;
      if (last != null) {
        final wait = minNominatimInterval - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastNominatim = DateTime.now();
    }
    final http.Response res;
    try {
      res = await _client.get(uri, headers: _headers).timeout(timeout);
    } on TimeoutException {
      throw const MapApiException(
        'El servicio de mapas no responde. Revisa tu conexión e intenta de nuevo.',
      );
    } catch (_) {
      throw const MapApiException(kNoInternetMessage);
    }
    if (res.statusCode == 429) {
      throw const MapApiException(
        'Demasiadas búsquedas seguidas. Espera un momento.',
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MapApiException(
        'El servicio de mapas falló (código ${res.statusCode}).',
      );
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const MapApiException('Respuesta inválida del servicio de mapas.');
    }
  }

  /// Busca lugares. Con [near], prioriza (o con [bounded], limita) a una caja
  /// de ~[radiusKm] km alrededor y ordena por cercanía.
  Future<List<Place>> searchPlaces(
    String query, {
    LatLng? near,
    bool bounded = false,
    double radiusKm = 5,
    int limit = 6,
  }) async {
    final params = <String, String>{
      'format': 'jsonv2',
      'q': query,
      'limit': '$limit',
      'accept-language': 'es',
    };
    if (near != null) {
      final dLat = radiusKm / 111.0;
      final dLon = radiusKm / 111.0;
      params['viewbox'] = '${near.longitude - dLon},${near.latitude + dLat},'
          '${near.longitude + dLon},${near.latitude - dLat}';
      params['bounded'] = bounded ? '1' : '0';
    }
    final uri = Uri.https(nominatimHost, '/search', params);
    final json = await _getJson(uri, nominatim: true);
    var places = parseNominatimSearch(json);
    if (near != null) {
      const dist = Distance();
      places = places
          .map((p) => p.withDistance(dist(near, p.location)))
          .toList()
        ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    }
    return places;
  }

  /// Dirección legible de una coordenada ("Av. Arequipa 1250, Miraflores").
  Future<String> reverse(LatLng point) async {
    final uri = Uri.https(nominatimHost, '/reverse', {
      'format': 'jsonv2',
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'accept-language': 'es',
    });
    final json = await _getJson(uri, nominatim: true);
    return parseNominatimReverse(json);
  }

  /// Ruta a pie de [from] a [to].
  Future<WalkingRoute> walkingRoute(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      '$osrmBase/${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );
    final json = await _getJson(uri);
    return parseOsrmRoute(json);
  }
}

// ---------------------------------------------------------------------------
// Parseo (funciones puras, testeadas con JSON fijo)
// ---------------------------------------------------------------------------

LatLng _lonLat(dynamic pair) {
  final l = pair as List;
  return LatLng((l[1] as num).toDouble(), (l[0] as num).toDouble());
}

/// Convierte la respuesta de OSRM en una [WalkingRoute] con instrucciones
/// en español.
WalkingRoute parseOsrmRoute(dynamic json) {
  if (json is! Map || json['code'] != 'Ok') {
    final code = json is Map ? json['code'] : null;
    if (code == 'NoRoute' || code == 'NoSegment') {
      throw const MapApiException(
        'No encontré una ruta a pie hasta ese lugar.',
      );
    }
    throw const MapApiException('No se pudo calcular la ruta.');
  }
  final routes = json['routes'] as List? ?? const [];
  if (routes.isEmpty) {
    throw const MapApiException('No encontré una ruta a pie hasta ese lugar.');
  }
  final r = routes.first as Map;
  final coords = ((r['geometry'] as Map?)?['coordinates'] as List?) ?? const [];
  final geometry = coords.map(_lonLat).toList();

  final steps = <RouteStep>[];
  for (final leg in (r['legs'] as List? ?? const [])) {
    for (final s in ((leg as Map)['steps'] as List? ?? const [])) {
      final step = s as Map;
      final m = step['maneuver'] as Map;
      final type = m['type']?.toString() ?? 'continue';
      final modifier = m['modifier']?.toString();
      final name = step['name']?.toString() ?? '';
      final distance = (step['distance'] as num?)?.toDouble() ?? 0;
      final exit = (m['exit'] as num?)?.toInt();
      steps.add(RouteStep(
        type: type,
        modifier: modifier,
        name: name,
        distance: distance,
        exit: exit,
        location: _lonLat(m['location']),
        instruction: spanishInstruction(
          type: type,
          modifier: modifier,
          name: name,
          distance: distance,
          exit: exit,
        ),
      ));
    }
  }
  if (steps.isEmpty) {
    throw const MapApiException('La ruta llegó sin indicaciones.');
  }
  return WalkingRoute(
    geometry: geometry.isNotEmpty
        ? geometry
        : steps.map((s) => s.location).toList(),
    steps: steps,
    distance: (r['distance'] as num?)?.toDouble() ?? 0,
    duration: (r['duration'] as num?)?.toDouble() ?? 0,
  );
}

/// Convierte la respuesta de /search (jsonv2) en lugares.
List<Place> parseNominatimSearch(dynamic json) {
  if (json is! List) return const [];
  final out = <Place>[];
  for (final e in json) {
    if (e is! Map) continue;
    final lat = double.tryParse(e['lat']?.toString() ?? '');
    final lon = double.tryParse(e['lon']?.toString() ?? '');
    if (lat == null || lon == null) continue;
    final display = e['display_name']?.toString() ?? '';
    final parts = display
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    var name = e['name']?.toString().trim() ?? '';
    if (name.isEmpty) name = parts.isNotEmpty ? parts.first : 'Lugar sin nombre';
    final rest = parts.where((p) => p != name).take(3).join(', ');
    out.add(Place(name: name, address: rest, location: LatLng(lat, lon)));
  }
  return out;
}

/// Convierte la respuesta de /reverse en una frase con calle y distrito.
String parseNominatimReverse(dynamic json) {
  if (json is! Map || json['error'] != null) {
    throw const MapApiException('No pude identificar dónde estás.');
  }
  final a = (json['address'] as Map?) ?? const {};
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = a[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  final road = pick(['road', 'pedestrian', 'footway', 'path', 'square']);
  final number = pick(['house_number']);
  final district = pick([
    'suburb',
    'city_district',
    'district',
    'borough',
    'quarter',
    'neighbourhood',
    'town',
    'village',
  ]);
  final city = pick(['city', 'town', 'municipality', 'state']);

  final parts = <String>[];
  if (road != null) parts.add(number != null ? '$road $number' : road);
  if (district != null) parts.add(district);
  if (city != null && city != district) parts.add(city);
  if (parts.isEmpty) {
    final display = json['display_name']?.toString() ?? '';
    final p = display.split(',').map((s) => s.trim()).take(3).join(', ');
    if (p.isEmpty) {
      throw const MapApiException('No pude identificar dónde estás.');
    }
    return 'Estás cerca de $p.';
  }
  return 'Estás en ${parts.join(', ')}.';
}

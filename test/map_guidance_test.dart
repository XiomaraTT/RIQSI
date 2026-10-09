import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:riqsi/features/map/data/datasources/map_api_client.dart';
import 'package:riqsi/features/map/domain/guidance.dart';

// Ruta sintética: 200 m al norte por Av. Arequipa, giro a la derecha y
// 100 m al este por Jr. Cusco hasta el destino.
const lat0 = -12.0464;
const lon0 = -77.0428;
const mLat = 110574.0;
final mLon = 111320.0 * math.cos(lat0 * math.pi / 180);

LatLng north(double m, {double eastOffset = 0}) =>
    LatLng(lat0 + m / mLat, lon0 + eastOffset / mLon);
LatLng cornerEast(double m) => LatLng(lat0 + 200 / mLat, lon0 + m / mLon);

List<double> lonLat(LatLng p) => [p.longitude, p.latitude];

Map<String, dynamic> osrmSample() => {
  'code': 'Ok',
  'routes': [
    {
      'distance': 300.0,
      'duration': 240.0,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          lonLat(north(0)),
          lonLat(north(100)),
          lonLat(north(200)),
          lonLat(cornerEast(100)),
        ],
      },
      'legs': [
        {
          'steps': [
            {
              'distance': 200.0,
              'name': 'Av. Arequipa',
              'maneuver': {
                'type': 'depart',
                'location': lonLat(north(0)),
              },
            },
            {
              'distance': 100.0,
              'name': 'Jr. Cusco',
              'maneuver': {
                'type': 'turn',
                'modifier': 'right',
                'location': lonLat(north(200)),
              },
            },
            {
              'distance': 0.0,
              'name': 'Jr. Cusco',
              'maneuver': {
                'type': 'arrive',
                'location': lonLat(cornerEast(100)),
              },
            },
          ],
        },
      ],
    },
  ],
};

const nominatimSearchSample = '''
[
  {"place_id": 1, "lat": "-12.0470", "lon": "-77.0420", "category": "amenity",
   "type": "pharmacy", "name": "Inkafarma",
   "display_name": "Inkafarma, 1250, Avenida Arequipa, Santa Beatriz, Lima, Perú"},
  {"place_id": 2, "lat": "-12.0600", "lon": "-77.0400", "category": "amenity",
   "type": "pharmacy", "name": "",
   "display_name": "Botica Central, Jirón Cusco, Lima, Perú"}
]
''';

const nominatimReverseSample = '''
{"place_id": 9, "lat": "-12.1200", "lon": "-77.0300",
 "display_name": "1250, Avenida Arequipa, Miraflores, Lima, Perú",
 "address": {"house_number": "1250", "road": "Avenida Arequipa",
             "suburb": "Miraflores", "city": "Lima", "country": "Perú"}}
''';

void main() {
  group('Instrucciones en español', () {
    test('giros con nombre de calle', () {
      expect(
        spanishInstruction(type: 'turn', modifier: 'right', name: 'Av. Arequipa'),
        'Gira a la derecha en Av. Arequipa',
      );
      expect(
        spanishInstruction(type: 'end of road', modifier: 'left', name: ''),
        'Gira a la izquierda',
      );
      expect(
        spanishInstruction(type: 'turn', modifier: 'slight right', name: 'Jr. Ica'),
        'Gira ligeramente a la derecha en Jr. Ica',
      );
      expect(spanishInstruction(type: 'turn', modifier: 'uturn'), 'Da media vuelta');
    });

    test('seguir recto, salida, llegada y rotonda', () {
      expect(
        spanishInstruction(type: 'continue', modifier: 'straight', distance: 118.6),
        'Sigue recto 120 metros',
      );
      expect(
        spanishInstruction(type: 'depart', name: 'Av. Grau', distance: 42),
        'Sigue recto 40 metros por Av. Grau',
      );
      expect(spanishInstruction(type: 'arrive'), 'Has llegado a tu destino');
      expect(
        spanishInstruction(type: 'roundabout', exit: 2, name: 'Av. Brasil'),
        'Entra a la rotonda, toma la salida 2 hacia Av. Brasil',
      );
      expect(formatDistance(1520), '1,5 kilómetros');
    });
  });

  group('Parseo', () {
    test('respuesta OSRM', () {
      final route = parseOsrmRoute(osrmSample());
      expect(route.geometry, hasLength(4));
      expect(route.steps, hasLength(3));
      expect(route.distance, 300);
      expect(route.steps[0].instruction, 'Sigue recto 200 metros por Av. Arequipa');
      expect(route.steps[1].instruction, 'Gira a la derecha en Jr. Cusco');
      expect(route.steps[1].side, TurnSide.right);
      expect(route.steps[2].isArrival, isTrue);
      expect(route.steps[1].location.latitude, closeTo(north(200).latitude, 1e-9));
    });

    test('OSRM sin ruta lanza un error legible', () {
      expect(
        () => parseOsrmRoute({'code': 'NoRoute', 'routes': []}),
        throwsA(isA<MapApiException>()),
      );
    });

    test('búsqueda Nominatim', () {
      final places = parseNominatimSearch(jsonDecode(nominatimSearchSample));
      expect(places, hasLength(2));
      expect(places[0].name, 'Inkafarma');
      expect(places[0].address, '1250, Avenida Arequipa, Santa Beatriz');
      expect(places[0].location.latitude, -12.047);
      expect(places[1].name, 'Botica Central');
    });

    test('reverse Nominatim: calle y distrito', () {
      expect(
        parseNominatimReverse(jsonDecode(nominatimReverseSample)),
        'Estás en Avenida Arequipa 1250, Miraflores, Lima.',
      );
      expect(
        () => parseNominatimReverse({'error': 'Unable to geocode'}),
        throwsA(isA<MapApiException>()),
      );
    });
  });

  group('Motor de guía', () {
    late GuidanceEngine engine;
    setUp(() => engine = GuidanceEngine(parseOsrmRoute(osrmSample())));

    test('anuncio inicial', () {
      final e = engine.start(destinationName: 'Farmacia');
      expect(e.message, contains('hacia Farmacia'));
      expect(e.message, contains('Sigue recto 200 metros por Av. Arequipa'));
      expect(engine.start(reroute: true).message, startsWith('Ruta recalculada'));
    });

    test('avisa a ~50 m y a ~15 m del giro, con vibración derecha', () {
      var s = engine.update(north(100));
      expect(s.events, isEmpty);
      expect(s.distanceToNext, closeTo(100, 1));
      expect(s.nextStepIndex, 1);

      s = engine.update(north(155));
      expect(s.events, hasLength(1));
      expect(s.events.single.type, GuidanceEventType.prepare);
      expect(s.events.single.message, 'En 45 metros, gira a la derecha en Jr. Cusco.');

      // No se repite el aviso previo.
      expect(engine.update(north(165)).events, isEmpty);

      s = engine.update(north(188));
      final turn = s.events.firstWhere((e) => e.type == GuidanceEventType.turn);
      expect(turn.message, 'Ahora, gira a la derecha en Jr. Cusco y sigue 100 metros.');
      expect(turn.haptic, TurnSide.right);
      expect(s.nextStepIndex, 2);
      expect(engine.repeatText(), contains('Tu destino está a'));
    });

    test('llegada a menos de 15 m del destino', () {
      engine.update(north(190));
      final pre = engine.update(cornerEast(55));
      expect(pre.events.single.message, 'Tu destino está a 45 metros.');
      final s = engine.update(cornerEast(90));
      expect(s.arrived, isTrue);
      expect(s.events.single.type, GuidanceEventType.arrived);
      expect(s.events.single.message, 'Has llegado a tu destino.');
      expect(engine.update(cornerEast(95)).events, isEmpty);
    });

    test('desvío > 35 m en 2 lecturas seguidas pide re-ruta', () {
      expect(engine.update(north(80, eastOffset: -60)).events, isEmpty);
      final s = engine.update(north(85, eastOffset: -60));
      expect(s.needsReroute, isTrue);
      expect(s.events.single.type, GuidanceEventType.offRoute);
      expect(s.events.single.message, contains('Recalculando ruta'));
      // Tras pedir re-ruta, no emite más eventos hasta recibir la nueva ruta.
      expect(engine.update(north(90)).events, isEmpty);
    });

    test('una lectura desviada aislada o imprecisa no re-rutea', () {
      engine.update(north(80, eastOffset: -60));
      engine.update(north(85)); // vuelve a la ruta: reinicia el contador
      expect(engine.update(north(90, eastOffset: -60)).needsReroute, isFalse);
      expect(
        engine.update(north(95, eastOffset: -60), accuracy: 80).needsReroute,
        isFalse,
      );
    });
  });

  group('MapApiClient (HTTP inyectado)', () {
    test('busca con User-Agent, parámetros y orden por cercanía', () async {
      late http.Request seen;
      final client = MapApiClient(
        client: MockClient((req) async {
          seen = req;
          return http.Response.bytes(utf8.encode(nominatimSearchSample), 200);
        }),
        minNominatimInterval: Duration.zero,
      );
      final places = await client.searchPlaces(
        'farmacia',
        near: north(0),
        bounded: true,
      );
      expect(seen.headers['User-Agent'], 'RIQSI/1.0 (app accesible)');
      expect(seen.url.host, 'nominatim.openstreetmap.org');
      expect(seen.url.queryParameters['format'], 'jsonv2');
      expect(seen.url.queryParameters['accept-language'], 'es');
      expect(seen.url.queryParameters['limit'], '6');
      expect(seen.url.queryParameters['bounded'], '1');
      expect(seen.url.queryParameters['viewbox'], isNotNull);
      expect(places.first.name, 'Inkafarma');
      expect(places.first.distanceMeters, lessThan(places.last.distanceMeters!));
    });

    test('ruta OSRM a pie', () async {
      late Uri url;
      final client = MapApiClient(
        client: MockClient((req) async {
          url = req.url;
          return http.Response(jsonEncode(osrmSample()), 200);
        }),
      );
      final route = await client.walkingRoute(north(0), cornerEast(100));
      expect(url.host, 'routing.openstreetmap.de');
      expect(url.path, startsWith('/routed-foot/route/v1/foot/'));
      expect(url.queryParameters['steps'], 'true');
      expect(url.queryParameters['geometries'], 'geojson');
      expect(route.steps, hasLength(3));
    });

    test('sin internet: error claro, sin crashear', () async {
      final client = MapApiClient(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        client.reverse(north(0)),
        throwsA(
          isA<MapApiException>().having(
            (e) => e.message,
            'message',
            kNoInternetMessage,
          ),
        ),
      );
    });

    test('respeta 1 petición por segundo en Nominatim', () async {
      final times = <DateTime>[];
      final client = MapApiClient(
        client: MockClient((_) async {
          times.add(DateTime.now());
          return http.Response('[]', 200);
        }),
        minNominatimInterval: const Duration(milliseconds: 300),
      );
      await client.searchPlaces('a');
      await client.searchPlaces('b');
      expect(
        times[1].difference(times[0]).inMilliseconds,
        greaterThanOrEqualTo(290),
      );
    });
  });
}

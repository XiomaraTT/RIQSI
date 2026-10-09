import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:riqsi/features/map/data/datasources/location_service.dart';
import 'package:riqsi/features/map/presentation/screens/mapa_screen.dart';
import 'package:riqsi/state/app_state.dart';

class _DeniedLocation extends LocationService {
  const _DeniedLocation();
  @override
  Future<LocationAccess> ensurePermission() async => LocationAccess.serviceOff;
}

void main() {
  testWidgets('sin GPS muestra el aviso y el botón para activarlo', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(
          home: MapaScreen(locationService: _DeniedLocation()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('El GPS está apagado. Actívalo para usar el mapa.'),
      findsOneWidget,
    );
    expect(find.text('Activar ubicación'), findsOneWidget);
    expect(find.text('© OpenStreetMap · rutas OSRM'), findsOneWidget);
    // Ya no existen los botones falsos de dirección.
    expect(find.text('DERECHA'), findsNothing);
    expect(find.text('FRENTE'), findsNothing);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:riqsi/main.dart';
import 'package:riqsi/state/app_state.dart';

void main() {
  testWidgets('Riqsi app smoke test and immersive mode state test', (WidgetTester tester) async {
    final appState = AppState();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const RiqsiApp(),
      ),
    );

    // Verify that Splash screen has the title text "RIQSI" and slogan.
    expect(find.text('RIQSI'), findsOneWidget);
    expect(find.text('Conoce tu entorno. Muévete con confianza.'), findsOneWidget);

    // Test immersive mode toggle
    expect(appState.isImmersiveMode, false);
    appState.toggleImmersiveMode();
    expect(appState.isImmersiveMode, true);
    appState.toggleImmersiveMode();
    expect(appState.isImmersiveMode, false);

    // Advance clock past splash timer so no timers are pending
    await tester.pump(const Duration(seconds: 4));
  });

  test('Navigation and Mapa directional guidance test', () {
    final appState = AppState();
    expect(appState.currentNavStep != null, true);
    expect(appState.currentNavStep!.direction, NavDirection.straight);

    // Test De Frente
    appState.setNavDirection(NavDirection.straight);
    expect(appState.currentNavStep!.direction, NavDirection.straight);
    expect(appState.currentNavStep!.directionTitle, "DE FRENTE");

    // Test Derecha
    appState.setNavDirection(NavDirection.right);
    expect(appState.currentNavStep!.direction, NavDirection.right);
    expect(appState.currentNavStep!.directionTitle, "GIRA A LA DERECHA");

    // Test Izquierda
    appState.setNavDirection(NavDirection.left);
    expect(appState.currentNavStep!.direction, NavDirection.left);
    expect(appState.currentNavStep!.directionTitle, "GIRA A LA IZQUIERDA");

    // Test Atrás
    appState.setNavDirection(NavDirection.back);
    expect(appState.currentNavStep!.direction, NavDirection.back);
    expect(appState.currentNavStep!.directionTitle, "DA MEDIA VUELTA (ATRÁS)");
  });
}

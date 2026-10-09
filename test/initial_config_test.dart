import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:riqsi/core/theme/riqsi_theme.dart';
import 'package:riqsi/features/onboarding/presentation/screens/initial_config_screen.dart';
import 'package:riqsi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Confirmar guarda el nombre (opcional) y entra a Inicio, no a Mapa',
      (tester) async {
    final state = AppState(
      ttsRepository: RecordingTtsRepository(),
      vibrationRepository: NoopVibrationRepository(),
      splashDuration: const Duration(hours: 1),
    );
    state.setTab(1); // aunque antes se hubiera quedado en otra pestaña
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: RiqsiTheme.darkTheme,
          home: const InitialConfigScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('¿Cómo te llamas?'), findsOneWidget);
    expect(find.text('Probar voz'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Ana ');
    await tester.tap(find.text('Confirmar y Continuar'));
    await tester.pump();
    // La navegación ocurre tras el frame del toque.
    expect(state.currentScreen, isNot(AppScreen.mainLayout));
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.currentScreen, AppScreen.mainLayout);
    expect(state.currentTab, 0);
    expect(state.userName, 'Ana');
    state.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:riqsi/core/theme/riqsi_theme.dart';
import 'package:riqsi/features/assistant/presentation/screens/main_layout.dart';
import 'package:riqsi/features/settings/presentation/screens/ayuda_screen.dart';
import 'package:riqsi/features/settings/presentation/screens/perfil_screen.dart';
import 'package:riqsi/state/app_state.dart';

Future<void> _pump(WidgetTester tester, AppState state, Widget child) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: RiqsiTheme.darkTheme, home: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('Perfil cumple guias de accesibilidad', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, AppState(), const PerfilScreen());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tester.pump(
      const Duration(seconds: 4),
    ); // vence el timer del splash de AppState
    handle.dispose();
  });

  testWidgets('Ayuda cumple guias de accesibilidad', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, AppState(), const AyudaScreen());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tester.pump(
      const Duration(seconds: 4),
    ); // vence el timer del splash de AppState
    handle.dispose();
  });

  testWidgets(
    'MainLayout (pestana Inicio) tiene objetivos tactiles etiquetados',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, AppState(), const MainLayout());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.pump(
        const Duration(seconds: 4),
      ); // vence el timer del splash de AppState
      handle.dispose();
    },
  );
}

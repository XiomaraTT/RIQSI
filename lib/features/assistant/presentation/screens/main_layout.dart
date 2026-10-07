import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

// Screens
import 'asistente_screen.dart';
import '../../../map/presentation/screens/mapa_screen.dart';
import '../../../settings/presentation/screens/perfil_screen.dart';
import '../widgets/alerta_overlay.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    // List of screens corresponding to bottom nav tabs
    final List<Widget> screens = [
      const AsistenteScreen(),
      const MapaScreen(),
      const PerfilScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Current Tab Screen Content
          IndexedStack(
            index: state.currentTab,
            children: screens,
          ),

          // 2. High Risk Alert Overlay (Flashed full-screen on danger detection)
          if (state.assistanceState == AssistanceState.riskDetected)
            const AlertaOverlay(),
        ],
      ),
      bottomNavigationBar: Semantics(
        label: "Barra de navegación principal",
        child: Container(
          decoration: BoxDecoration(
            color: RiqsiTheme.darkBg.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: RiqsiTheme.textSecondary.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              indicatorColor: RiqsiTheme.accentCyan.withValues(alpha: 0.15),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final isSelected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? RiqsiTheme.accentCyan : RiqsiTheme.textSecondary,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final isSelected = states.contains(WidgetState.selected);
                return IconThemeData(
                  size: 32,
                  color: isSelected ? RiqsiTheme.accentCyan : RiqsiTheme.textSecondary,
                );
              }),
            ),
            child: NavigationBar(
              height: 80,
              backgroundColor: Colors.transparent,
              selectedIndex: state.currentTab,
              onDestinationSelected: (index) {
                state.setTab(index);
                String tabName = "";
                if (index == 0) tabName = "Inicio, Asistente Visual 0.5x";
                if (index == 1) tabName = "Mapa y Navegación Asistida";
                if (index == 2) tabName = "Configuración y Perfil";
                state.speak("Pestaña $tabName seleccionada.");
                state.vibrate(40);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.remove_red_eye_outlined),
                  selectedIcon: Icon(Icons.remove_red_eye_rounded),
                  label: "Inicio",
                  tooltip: "Inicio - Visión 0.5x",
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: "Mapa",
                  tooltip: "Mapa y Navegación Asistida",
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: "Perfil",
                  tooltip: "Perfil y Configuración",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

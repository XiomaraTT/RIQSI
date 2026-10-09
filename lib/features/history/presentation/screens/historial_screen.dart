import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

class HistorialScreen extends StatelessWidget {
  const HistorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final historyList = state.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Historial de Detecciones",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // List Header / Helper description
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Toca cualquier tarjeta del historial para volver a escuchar la descripción por voz.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: RiqsiTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Detections List
            Expanded(
              child: historyList.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      itemCount: historyList.length,
                      itemBuilder: (context, index) {
                        final event = historyList[index];
                        return _buildHistoryCard(context, state, event);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.history_toggle_off_rounded,
            size: 64,
            color: RiqsiTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            "Historial Vacío",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: RiqsiTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Las detecciones aparecerán aquí una vez inicies la asistencia.",
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    BuildContext context,
    AppState state,
    DetectionEvent event,
  ) {
    // Determine risk tags
    Color riskColor;
    IconData riskIcon;
    if (event.riskLevel == 'Alto') {
      riskColor = RiqsiTheme.alertHigh;
      riskIcon = Icons.warning_rounded;
    } else if (event.riskLevel == 'Medio') {
      riskColor = RiqsiTheme.alertMedium;
      riskIcon = Icons.info_rounded;
    } else {
      riskColor = RiqsiTheme.alertLow;
      riskIcon = Icons.check_circle_rounded;
    }

    // Format hour
    final String timeStr =
        "${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}";

    return Semantics(
      button: true,
      label:
          "Detección a las $timeStr. ${event.label} ${_posText(event.relativePosition)}. Riesgo ${event.riskLevel}.",
      hint: "Toca dos veces para escuchar la descripción de voz nuevamente",
      excludeSemantics: true,
      onTap: () {
        state.speak(event.description);
        state.vibrate(80);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: InkWell(
          onTap: () {
            state.speak(event.description);
            state.vibrate(80);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: RiqsiTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: event.riskLevel == 'Alto'
                    ? RiqsiTheme.alertHigh.withValues(alpha: 0.5)
                    : RiqsiTheme.textSecondary.withValues(alpha: 0.1),
                width: event.riskLevel == 'Alto' ? 2.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Time tag (Cyan style)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: RiqsiTheme.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: RiqsiTheme.accentCyan,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Main Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.navigation_outlined,
                            size: 16,
                            color: RiqsiTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              "Posición: ${event.relativePosition}",
                              style: const TextStyle(
                                color: RiqsiTheme.textSecondary,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Risk Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(riskIcon, color: riskColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        event.riskLevel,
                        style: TextStyle(
                          color: riskColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Posición hablada: "adelante" para el centro, "a la izquierda/derecha".
String _posText(String pos) {
  final p = pos.toLowerCase();
  if (p.isEmpty || p == 'adelante' || p == 'centro') return 'adelante';
  return 'a la $p';
}

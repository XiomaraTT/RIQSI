import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/accessibility/a11y_tap.dart';
import '../../../../core/accessibility/ui_speech.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context, listen: false);

    // Controles reales de la app (los comandos de voz aún no existen)
    final List<Map<String, String>> controls = [
      {"cmd": "Botón central", "desc": "Inicia o detiene la asistencia visual"},
      {
        "cmd": "Repetir última descripción",
        "desc": "Vuelve a pronunciar lo último que Riqsi detectó",
      },
      {
        "cmd": "Silenciar o activar voz",
        "desc": "Botón de volumen en la parte superior del inicio",
      },
      {
        "cmd": "Vibración",
        "desc": "Activa o desactiva las vibraciones de aviso",
      },
      {
        "cmd": "Mapa",
        "desc": "Busca un destino y recibe indicaciones paso a paso",
      },
      {
        "cmd": "Perfil",
        "desc": "Ajusta velocidad de voz, volumen y sensibilidad",
      },
    ];

    // List of step-by-step instructions
    final List<String> steps = [
      "Apunta la cámara del celular hacia tu entorno.",
      "Presiona el gran botón central para iniciar la asistencia.",
      "Riqsi analizará en tiempo real lo que observa.",
      "Escucha las indicaciones de voz y siente las vibraciones.",
      "Si detecta un posible peligro, emitirá una alerta visual y auditiva.",
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Instrucciones y Ayuda",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: A11yTap(
          label: "Volver a la pantalla de configuración",
          onTap: () {
            Navigator.pop(context);
            speakUi(context, "Regresando a configuración.");
          },
          child: const Icon(
            Icons.arrow_back_ios_rounded,
            color: RiqsiTheme.accentCyan,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          children: [
            // Title 1
            Semantics(
              header: true,
              child: Text(
                "Instrucciones de Uso",
                style: TextStyle(
                  color: RiqsiTheme.accentCyan,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Numbered Steps
            ...List.generate(steps.length, (index) {
              return Semantics(
                label: "Paso ${index + 1}: ${steps[index]}",
                excludeSemantics: true,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: RiqsiTheme.darkSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: RiqsiTheme.textSecondary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: RiqsiTheme.accentCyan,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "${index + 1}",
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          steps[index],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 28),

            // Title 2
            Semantics(
              header: true,
              child: Text(
                "Controles de la aplicación",
                style: TextStyle(
                  color: RiqsiTheme.accentCyan,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Los comandos de voz estarán disponibles próximamente. Por ahora, usa estos controles. Toca uno para escuchar su función.",
              style: TextStyle(color: RiqsiTheme.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 12),

            // Voice Command Cards
            ...controls.map((command) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: "${command['cmd']}. ${command['desc']}",
                  onTap: () => state.vibrate(60),
                  child: InkWell(
                    onTap: () {
                      speakUi(context, "${command['cmd']}. ${command['desc']}");
                      state.vibrate(60);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: RiqsiTheme.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: RiqsiTheme.accentCyan.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  command['cmd']!,
                                  style: const TextStyle(
                                    color: RiqsiTheme.accentCyan,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  command['desc']!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.volume_up_rounded,
                            color: RiqsiTheme.accentCyan,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

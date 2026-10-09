import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

class AlertaOverlay extends StatefulWidget {
  const AlertaOverlay({super.key});

  /// Etiqueta de distancia a partir del evento; null si es desconocida.
  static String? distanceLabel(String? distancia) {
    switch (distancia) {
      case 'muy_cerca':
        return 'MUY CERCA';
      case 'cerca':
        return 'CERCA';
      case 'lejos':
        return 'LEJOS';
      default:
        return null;
    }
  }

  @override
  State<AlertaOverlay> createState() => _AlertaOverlayState();
}

class _AlertaOverlayState extends State<AlertaOverlay>
    with SingleTickerProviderStateMixin {
  // Pulso suave entre dos rojos oscuros (nunca alterna rojo/negro a pantalla
  // completa). Texto blanco >= 4.5:1 sobre ambos.
  static const Color _pulseA = Color(0xFF9E1B00);
  static const Color _pulseB = Color(0xFFC22A00);

  late final AnimationController _controller;
  late final Animation<Color?> _colorAnimation;
  String? _lastAnnounced;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400), // ~0.7 Hz, suave
    );
    _colorAnimation = ColorTween(
      begin: _pulseA,
      end: _pulseB,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _announce(String text) {
    if (_lastAnnounced == text) return;
    _lastAnnounced = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        TextDirection.ltr,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final detection = state.activeDetection;
    final label = detection?.label ?? "Objeto";
    final pos = (detection?.relativePosition ?? "").toLowerCase();
    final displayText = (pos.isEmpty || pos == "adelante" || pos == "centro")
        ? "$label adelante"
        : "$label a la $pos";
    final distText = AlertaOverlay.distanceLabel(detection?.distancia);
    final spoken = distText == null
        ? "Cuidado. $displayText."
        : "Cuidado. $displayText. ${distText.toLowerCase()}.";
    _announce(spoken);

    // BlockSemantics: TalkBack solo ve esta alerta, no lo que hay debajo.
    return BlockSemantics(
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, child) {
          return Scaffold(
            backgroundColor: _reduceMotion ? _pulseB : _colorAnimation.value,
            body: child,
          );
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Icono decorativo
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.report_gmailerrorred_rounded,
                      size: 96,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // Texto de la alerta, como región viva para el lector de pantalla
                Semantics(
                  liveRegion: true,
                  container: true,
                  label: spoken,
                  child: ExcludeSemantics(
                    child: Column(
                      children: [
                        Text(
                          "¡CUIDADO!",
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          displayText,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        if (distText != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              distText,
                              style: const TextStyle(
                                color: RiqsiTheme.accentCyan,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Botón grande de descarte
                Semantics(
                  button: true,
                  label: "Entendido, descartar alerta y reanudar asistencia",
                  excludeSemantics: true,
                  onTap: () => Provider.of<AppState>(
                    context,
                    listen: false,
                  ).dismissAlert(),
                  child: Container(
                    width: double.infinity,
                    height: 80,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ElevatedButton(
                      onPressed: () {
                        Provider.of<AppState>(
                          context,
                          listen: false,
                        ).dismissAlert();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 6,
                      ),
                      child: const Text(
                        "Entendido",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
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

import 'package:flutter/material.dart';
import '../../../../core/theme/riqsi_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        liveRegion: true,
        container: true,
        label:
            "Riqsi, asistente de visión, cargando. Conoce tu entorno. Muévete con confianza.",
        excludeSemantics: true,
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    // Glowing Andean Geometric Logo Icon (Cyan style)
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: RiqsiTheme.darkSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: RiqsiTheme.accentCyan,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: RiqsiTheme.accentCyan.withValues(alpha: 0.3),
                            blurRadius: 25,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Andean cross (Chakana) inspired geometry or simple visual eye
                          const Icon(
                            Icons.remove_red_eye_rounded,
                            size: 68,
                            color: RiqsiTheme.accentCyan,
                          ),
                          // Outer rotating target lines
                          Positioned(
                            top: 14,
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: CircularProgressIndicator(
                              value: 0.25,
                              strokeWidth: 2,
                              color: RiqsiTheme.accentCyan.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),

                    // App Title
                    Text(
                      "RIQSI",
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: 48,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w900,
                            color: RiqsiTheme.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 12),

                    // Slogan
                    Text(
                      "Conoce tu entorno. Muévete con confianza.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: RiqsiTheme.accentCyan,
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),

                    // Subtle Pulsing Loading Indicator
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        color: RiqsiTheme.accentCyan,
                        strokeWidth: 3.5,
                      ),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

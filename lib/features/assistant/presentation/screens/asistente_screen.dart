import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/accessibility/a11y_tap.dart';
import '../../../../core/accessibility/ui_speech.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import '../widgets/yolo_camera_view.dart';
import '../widgets/ar_hud_reticle.dart';

class AsistenteScreen extends StatefulWidget {
  const AsistenteScreen({super.key});

  @override
  State<AsistenteScreen> createState() => _AsistenteScreenState();
}

class _AsistenteScreenState extends State<AsistenteScreen> {
  bool _showControls = true;
  bool _isUltraWide = false; // Por defecto: lente principal 1x (más nitidez y mejor detección)

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final isScanning = state.isAssisting;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cámara con detección en el celular (solo activa al asistir).
          YoloCameraView(state: state, isUltraWide: _isUltraWide),

          // 2. Retícula HUD
          if (isScanning) ArHudReticle(state: state, isScanning: isScanning),

          // 3. Tocar la pantalla oculta/muestra los controles. Para TalkBack
          // se excluye: los controles son accesibles por exploración.
          ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() => _showControls = !_showControls);
                speakUi(
                  context,
                  _showControls ? "Controles visibles" : "Controles ocultos",
                );
                state.vibrate(30);
              },
            ),
          ),

          if (_showControls) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(child: _buildTopHud(state)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: SafeArea(child: _buildBottomControls(state, isScanning)),
            ),
          ] else
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: FloatingActionButton(
                  backgroundColor: Colors.black.withValues(alpha: 0.75),
                  foregroundColor: RiqsiTheme.accentCyan,
                  shape: const CircleBorder(
                    side: BorderSide(color: RiqsiTheme.accentCyan, width: 1.5),
                  ),
                  tooltip: "Mostrar controles",
                  onPressed: () {
                    setState(() => _showControls = true);
                    state.vibrate(30);
                  },
                  child: const ExcludeSemantics(
                    child: Icon(Icons.tune_rounded),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(AppState state) {
    if (!state.isAssisting) return RiqsiTheme.textSecondary;
    if (state.activeDetection == null) return RiqsiTheme.alertLow;
    return RiqsiTheme.riskColor(state.statusRisk);
  }

  IconData _statusIcon(AppState state) {
    if (!state.isAssisting) return Icons.pause_circle_outline_rounded;
    if (state.activeDetection == null) return Icons.check_circle_outline_rounded;
    return state.statusRisk == 'Alto'
        ? Icons.warning_rounded
        : Icons.visibility_rounded;
  }

  /// Barra superior: botones rápidos y estado grande y legible.
  Widget _buildTopHud(AppState state) {
    final color = _statusColor(state);
    final subtitle = state.isAssisting
        ? state.lastSpokenDescription
        : (state.hasUserName
            ? "${state.greeting} Pulsa Iniciar para comenzar."
            : "Pulsa Iniciar para comenzar.");

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildLensChip(state),
              const Spacer(),
              _buildGlassIconButton(
                icon: state.volume > 0
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                tooltip: state.volume > 0 ? "Silenciar voz" : "Activar voz",
                isActive: state.volume > 0,
                onPressed: () {
                  final newVal = state.volume > 0 ? 0.0 : 0.8;
                  state.updateVolume(newVal);
                  speakUi(context, newVal > 0 ? "Voz activada" : "");
                  state.vibrate(40);
                },
              ),
              const SizedBox(width: 6),
              _buildGlassIconButton(
                icon: state.vibrationEnabled
                    ? Icons.vibration_rounded
                    : Icons.mobile_off_rounded,
                tooltip: state.vibrationEnabled
                    ? "Desactivar vibración"
                    : "Activar vibración",
                isActive: state.vibrationEnabled,
                onPressed: () {
                  state.toggleVibration(!state.vibrationEnabled);
                  state.vibrate(40);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            container: true,
            label: subtitle.isEmpty
                ? state.statusHeadline
                : "${state.statusHeadline}. $subtitle",
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(_statusIcon(state), color: color, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.statusHeadline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    // Dibujo de 44dp dentro de un área táctil de 48dp.
    return A11yTap(
      label: tooltip,
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? RiqsiTheme.accentCyan : Colors.white70,
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? RiqsiTheme.accentCyan : Colors.white70,
          size: 22,
        ),
      ),
    );
  }

  /// Selector de lente: 0.5x (gran angular) o 1x (principal). Cambia la
  /// cámara que usa el detector.
  Widget _buildLensChip(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white54, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLensOption(
            label: "0.5x",
            semanticLabel: "Cámara gran angular 0.5x",
            isSelected: _isUltraWide,
            onTap: () => _selectLens(state, true),
          ),
          _buildLensOption(
            label: "1x",
            semanticLabel: "Cámara principal 1x",
            isSelected: !_isUltraWide,
            onTap: () => _selectLens(state, false),
          ),
        ],
      ),
    );
  }

  void _selectLens(AppState state, bool ultraWide) {
    if (_isUltraWide == ultraWide) return;
    setState(() => _isUltraWide = ultraWide);
    speakUi(context, ultraWide ? "Cámara gran angular" : "Cámara principal");
    state.vibrate(40);
  }

  Widget _buildLensOption({
    required String label,
    required String semanticLabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return A11yTap(
      label: semanticLabel,
      selected: isSelected,
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? RiqsiTheme.accentCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  /// Controles inferiores: botón principal grande y repetir voz.
  Widget _buildBottomControls(AppState state, bool isScanning) {
    final mainColor = isScanning ? RiqsiTheme.alertHigh : RiqsiTheme.accentCyan;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: isScanning
                  ? "Detener asistencia visual"
                  : "Iniciar asistencia visual",
              hint: isScanning
                  ? "Detiene la cámara y la detección"
                  : "Enciende la cámara y avisa de los obstáculos",
              excludeSemantics: true,
              onTap: state.toggleAssistance,
              child: Material(
                color: mainColor,
                borderRadius: BorderRadius.circular(40),
                elevation: 6,
                shadowColor: mainColor.withValues(alpha: 0.6),
                child: InkWell(
                  onTap: state.toggleAssistance,
                  borderRadius: BorderRadius.circular(40),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isScanning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 44,
                          color: isScanning ? Colors.white : Colors.black,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isScanning ? "Detener" : "Iniciar",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isScanning ? Colors.white : Colors.black,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          A11yTap(
            label: "Repetir última descripción",
            onTap: () {
              state.repeatLastSpoken();
              state.vibrate(40);
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                shape: BoxShape.circle,
                border: Border.all(color: RiqsiTheme.accentCyan, width: 2),
              ),
              child: const Icon(
                Icons.replay_rounded,
                color: RiqsiTheme.accentCyan,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import '../widgets/camera_simulator.dart';
import '../widgets/ar_hud_reticle.dart';

class AsistenteScreen extends StatefulWidget {
  const AsistenteScreen({super.key});

  @override
  State<AsistenteScreen> createState() => _AsistenteScreenState();
}

class _AsistenteScreenState extends State<AsistenteScreen> {
  bool _showControls = true;
  bool _isUltraWide = true; // Por defecto: 0.5x Ultra-Gran Angular

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final isScanning = state.assistanceState != AssistanceState.inactive;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-screen Camera Viewport with 0.5x ultra-wide lens
          CameraSimulator(
            state: state,
            isUltraWide: _isUltraWide,
          ),

          // 2. AR HUD Targeting Reticle & Scanning Beam
          ArHudReticle(
            state: state,
            isScanning: isScanning,
          ),

          // 3. Gesture Detector (Single tap to toggle HUD controls for clean view)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setState(() {
                _showControls = !_showControls;
              });
              state.speak(
                _showControls
                    ? "Controles visibles"
                    : "Controles ocultos",
              );
              state.vibrate(30);
            },
          ),

          // 4. Floating HUD Overlays (Top Status Bar, Bottom Subtitles & Action Buttons)
          if (_showControls) ...[
            // Top Floating HUD
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _buildTopStatusBar(state),
              ),
            ),

            // Bottom Floating HUD
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: SafeArea(
                child: _buildBottomControls(state, isScanning),
              ),
            ),
          ] else ...[
            // Quick button to restore controls when hidden
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: FloatingActionButton.small(
                  backgroundColor: Colors.black.withValues(alpha: 0.75),
                  foregroundColor: RiqsiTheme.accentCyan,
                  shape: const CircleBorder(
                    side: BorderSide(color: RiqsiTheme.accentCyan, width: 1.5),
                  ),
                  tooltip: "Mostrar controles",
                  onPressed: () {
                    setState(() {
                      _showControls = true;
                    });
                    state.vibrate(30);
                  },
                  child: const Icon(Icons.tune_rounded),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Top Status Bar Floating HUD
  Widget _buildTopStatusBar(AppState state) {
    final statusColor = state.assistanceState == AssistanceState.riskDetected
        ? RiqsiTheme.alertHigh
        : (state.assistanceState == AssistanceState.objectDetected
            ? RiqsiTheme.accentCyan
            : (state.assistanceState == AssistanceState.analyzing
                ? Colors.greenAccent
                : Colors.white70));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // Offline indicator if disconnected
          if (!state.isConnected)
            Container(
              margin: const EdgeInsets.only(right: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: RiqsiTheme.alertMedium.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: RiqsiTheme.alertMedium),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: RiqsiTheme.alertMedium),
                  SizedBox(width: 4),
                  Text("OFFLINE", style: TextStyle(color: RiqsiTheme.alertMedium, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),

          // Status Capsule
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.6), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.currentStatusMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: RiqsiTheme.accentCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: RiqsiTheme.accentCyan.withValues(alpha: 0.6), width: 1),
                        ),
                        child: Text(
                          _isUltraWide ? "0.5x ULTRA" : "1.0x NORMAL",
                          style: const TextStyle(
                            color: RiqsiTheme.accentCyan,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Voice Mute/Unmute toggle
          _buildGlassIconButton(
            icon: state.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            tooltip: state.volume > 0 ? "Silenciar voz" : "Activar voz",
            isActive: state.volume > 0,
            onPressed: () {
              final newVal = state.volume > 0 ? 0.0 : 0.8;
              state.updateVolume(newVal);
              state.speak(newVal > 0 ? "Voz activada" : "");
              state.vibrate(40);
            },
          ),

          const SizedBox(width: 6),

          // Vibration toggle
          _buildGlassIconButton(
            icon: state.vibrationEnabled ? Icons.vibration_rounded : Icons.portable_wifi_off_rounded,
            tooltip: state.vibrationEnabled ? "Desactivar vibración" : "Activar vibración",
            isActive: state.vibrationEnabled,
            onPressed: () {
              state.toggleVibration(!state.vibrationEnabled);
              state.vibrate(40);
            },
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? RiqsiTheme.accentCyan : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: isActive ? RiqsiTheme.accentCyan : Colors.white54,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// Bottom Controls Floating HUD
  Widget _buildBottomControls(AppState state, bool isScanning) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Live Subtitle / Description Card (Glassmorphism)
          if (state.lastSpokenDescription.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: RiqsiTheme.accentCyan.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.record_voice_over_rounded, color: RiqsiTheme.accentCyan, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state.lastSpokenDescription,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            state.repeatLastSpoken();
                            state.vibrate(40);
                          },
                          icon: const Icon(Icons.replay_rounded, color: RiqsiTheme.accentCyan),
                          tooltip: "Repetir voz",
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 2. Camera Lens Selector (0.5x Ultra-Wide vs 1.0x Main)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: _buildLensSwitcher(state),
          ),

          // 3. Action Controls Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Espaciador izquierdo para equilibrar con el botón derecho (56px)
              const SizedBox(width: 56),
              const Spacer(),

              // GIANT Center Action Button (Start / Stop con la flecha)
              Semantics(
                button: true,
                label: isScanning ? "Detener asistencia visual" : "Iniciar asistencia visual",
                hint: isScanning ? "Detiene el escaneo continuo" : "Inicia el escaneo continuo de cámara",
                child: InkWell(
                  onTap: state.toggleAssistance,
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: isScanning ? RiqsiTheme.alertHigh : RiqsiTheme.accentCyan,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isScanning ? RiqsiTheme.alertHigh : RiqsiTheme.accentCyan).withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Icon(
                      isScanning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 58,
                      color: isScanning ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Replay last spoken description
              Semantics(
                button: true,
                label: "Repetir última descripción",
                child: InkWell(
                  onTap: () {
                    state.repeatLastSpoken();
                    state.vibrate(40);
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                      border: Border.all(color: RiqsiTheme.accentCyan, width: 2),
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: RiqsiTheme.accentCyan,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Helper accessibility hint
          const Text(
            "Toca la pantalla para ocultar o mostrar los controles",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLensSwitcher(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white24,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLensOption(
            label: "0.5x",
            subtitle: "Ultra-Wide",
            isSelected: _isUltraWide,
            onTap: () {
              if (!_isUltraWide) {
                setState(() => _isUltraWide = true);
                state.speak("Cámara ultra gran angular");
                state.vibrate(40);
              }
            },
          ),
          const SizedBox(width: 4),
          _buildLensOption(
            label: "1.0x",
            subtitle: "Principal",
            isSelected: !_isUltraWide,
            onTap: () {
              if (_isUltraWide) {
                setState(() => _isUltraWide = false);
                state.speak("Cámara principal");
                state.vibrate(40);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLensOption({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? RiqsiTheme.accentCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: RiqsiTheme.accentCyan.withValues(alpha: 0.5),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

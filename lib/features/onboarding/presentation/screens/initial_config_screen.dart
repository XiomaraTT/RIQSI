import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../../../core/accessibility/ui_speech.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import '../../../assistant/presentation/widgets/accessible_button.dart';

class InitialConfigScreen extends StatefulWidget {
  const InitialConfigScreen({super.key});

  @override
  State<InitialConfigScreen> createState() => _InitialConfigScreenState();
}

class _InitialConfigScreenState extends State<InitialConfigScreen> {
  String? _lastChangedSetting;
  late final TextEditingController _nameController = TextEditingController(
    text: context.read<AppState>().userName,
  );
  bool _leaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Guarda el nombre y entra a la pantalla principal. La navegación se
  /// hace tras el frame actual para que el toque del botón (que está a la
  /// altura de la barra inferior) no llegue a la barra de pestañas.
  void _confirm(AppState state) {
    if (_leaving) return;
    _leaving = true;
    FocusScope.of(context).unfocus();
    state.updateUserName(_nameController.text);
    speakUi(
      context,
      "${state.greeting} Configuración guardada. Estás en Inicio: "
      "pulsa Iniciar para que Riqsi observe tu camino.",
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        state.navigateToScreen(AppScreen.mainLayout);
      });
    });
  }

  void _showSettingConfirmation(String settingName) {
    setState(() {
      _lastChangedSetting = settingName;
    });

    final state = Provider.of<AppState>(context, listen: false);
    state.vibrate(50);

    Timer? timer;
    timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (_lastChangedSetting == settingName) {
            _lastChangedSetting = null;
          }
        });
      }
      timer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Configuración Inicial",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Confirmation alert overlay at top
            Semantics(
              liveRegion: true,
              container: true,
              label: _lastChangedSetting != null
                  ? "$_lastChangedSetting modificado"
                  : null,
              excludeSemantics: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _lastChangedSetting != null ? 50 : 0,
                width: double.infinity,
                color: RiqsiTheme.accentCyan,
                alignment: Alignment.center,
                child: _lastChangedSetting != null
                    ? Text(
                        "✓ $_lastChangedSetting modificado",
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Personaliza tu experiencia",
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Dinos tu nombre si quieres y ajusta la voz y la vibración antes de comenzar.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),

                    // 0. Nombre (opcional)
                    const Text(
                      "¿Cómo te llamas?",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      maxLength: 40,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        labelText: "Tu nombre (opcional)",
                        labelStyle: const TextStyle(
                          color: RiqsiTheme.textSecondary,
                          fontSize: 16,
                        ),
                        hintText: "Ej.: Ana",
                        hintStyle: const TextStyle(
                          color: RiqsiTheme.textSecondary,
                          fontSize: 18,
                        ),
                        counterText: "",
                        filled: true,
                        fillColor: RiqsiTheme.darkSurface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: RiqsiTheme.textSecondary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: RiqsiTheme.accentCyan,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Si lo dejas vacío, Riqsi te saludará sin nombre.",
                      style: TextStyle(
                        color: RiqsiTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 1. Voice Speed Slider
                    _buildSectionHeader(
                      "Velocidad de voz",
                      "${state.voiceSpeed.toStringAsFixed(1)}x",
                    ),
                    Slider(
                      semanticFormatterCallback: (v) =>
                          "Velocidad de voz ${v.toStringAsFixed(1)} equis",
                      value: state.voiceSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      onChanged: (val) {
                        state.updateVoiceSpeed(val);
                      },
                      onChangeEnd: (val) {
                        _showSettingConfirmation(
                          "Velocidad de voz a ${val.toStringAsFixed(1)}x",
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // 2. Volume Slider
                    _buildSectionHeader(
                      "Volumen de voz",
                      "${(state.volume * 100).toInt()}%",
                    ),
                    Slider(
                      semanticFormatterCallback: (v) =>
                          "Volumen de voz ${(v * 100).toInt()} por ciento",
                      value: state.volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      onChanged: (val) {
                        state.updateVolume(val);
                      },
                      onChangeEnd: (val) {
                        _showSettingConfirmation(
                          "Volumen de voz al ${(val * 100).toInt()}%",
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Probar voz (junto a los ajustes de voz)
                    OutlinedButton.icon(
                      onPressed: () {
                        state.testVoice();
                        _showSettingConfirmation("Prueba de voz reproducida");
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(64),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        foregroundColor: RiqsiTheme.accentCyan,
                        side: const BorderSide(
                          color: RiqsiTheme.accentCyan,
                          width: 2,
                        ),
                      ),
                      icon: const Icon(Icons.volume_up_rounded, size: 26),
                      label: const Text(
                        "Probar voz",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 3. Vibration Switch
                    MergeSemantics(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: RiqsiTheme.darkSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: RiqsiTheme.textSecondary.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Vibración de Alertas",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.vibrationEnabled
                                      ? "Activada"
                                      : "Desactivada",
                                  style: const TextStyle(
                                    color: RiqsiTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            Semantics(
                              label: "Vibración de alertas",
                              child: Switch(
                                value: state.vibrationEnabled,
                                onChanged: (val) {
                                  state.toggleVibration(val);
                                  _showSettingConfirmation(
                                    val
                                        ? "Vibración activada"
                                        : "Vibración desactivada",
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 4. Alert Frequency Row Selector
                    const Text(
                      "Frecuencia de alertas",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildFrequencySelector(state),
                    const SizedBox(height: 32),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Giant Confirm Button at Bottom
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: RiqsiTheme.textSecondary.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: AccessibleButton(
                label: "Confirmar y Continuar",
                onPressed: () => _confirm(state),
                semanticHint:
                    "Guardar configuración actual e ir a la pantalla principal",
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: RiqsiTheme.accentCyan,
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencySelector(AppState state) {
    final frequencies = ["Baja", "Media", "Alta"];
    return Row(
      children: frequencies.map((freq) {
        final isSelected = state.alertFrequency == freq;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Semantics(
              button: true,
              label: "Frecuencia de alertas $freq",
              selected: isSelected,
              excludeSemantics: true,
              onTap: () {
                state.updateAlertFrequency(freq);
                _showSettingConfirmation("Frecuencia a $freq");
              },
              child: InkWell(
                onTap: () {
                  state.updateAlertFrequency(freq);
                  _showSettingConfirmation("Frecuencia a $freq");
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? RiqsiTheme.accentCyan
                        : RiqsiTheme.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? RiqsiTheme.accentCyan
                          : RiqsiTheme.textSecondary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      freq,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

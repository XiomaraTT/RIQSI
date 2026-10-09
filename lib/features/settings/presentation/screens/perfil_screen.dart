import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../../../../core/accessibility/a11y_tap.dart';
import '../../../../core/accessibility/ui_speech.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import 'ayuda_screen.dart';

/// Texto legible de la velocidad: 1 -> "1x", 1.5 -> "1.5x", 2 -> "2x".
String formatSpeed(double speed) {
  final isInt = speed == speed.roundToDouble();
  return "${isInt ? speed.toStringAsFixed(0) : speed.toString()}x";
}

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    final String volumePercentage = "${(state.volume * 100).toInt()}%";
    final String speedLabel = formatSpeed(state.voiceSpeed);
    final String vibrationLabel = state.vibrationEnabled
        ? "Activada"
        : "Desactivada";

    return Scaffold(
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
          children: [
            const Text(
              "CONFIGURACIÓN",
              style: TextStyle(
                color: RiqsiTheme.accentCyan,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Semantics(
              header: true,
              child: Text(
                "Perfil",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 16),

            _buildProfileRow(context, state),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF1B2C3F), height: 1),
            const SizedBox(height: 16),

            _buildSectionHeader("PREFERENCIAS"),

            _buildPreferenceRow(
              label: "Idioma",
              value: state.language,
              onTap: () {
                announceUi(context, "Idioma fijado en Español.");
              },
            ),
            _buildPreferenceRow(
              label: "Velocidad de voz",
              value: speedLabel,
              onTap: () {
                double newSpeed = 1.0;
                if (state.voiceSpeed == 1.0) {
                  newSpeed = 2.0;
                } else if (state.voiceSpeed == 2.0) {
                  newSpeed = 1.5;
                }
                state.updateVoiceSpeed(newSpeed);
                announceUi(
                  context,
                  "Velocidad de voz a ${formatSpeed(newSpeed)}.",
                );
              },
            ),
            _buildPreferenceRow(
              label: "Volumen",
              value: volumePercentage,
              onTap: () {
                double newVol = 0.5;
                if (state.volume == 0.5) {
                  newVol = 0.8;
                } else if (state.volume == 0.8) {
                  newVol = 1.0;
                }
                state.updateVolume(newVol);
                announceUi(
                  context,
                  "Volumen al ${(newVol * 100).toInt()} por ciento.",
                );
              },
            ),
            _buildPreferenceRow(
              label: "Vibración",
              value: vibrationLabel,
              onTap: () {
                // Se calcula el valor NUEVO antes de cambiarlo.
                final newValue = !state.vibrationEnabled;
                state.toggleVibration(newValue);
                announceUi(
                  context,
                  newValue ? "Vibración activada." : "Vibración desactivada.",
                );
              },
            ),
            _buildPreferenceRow(
              label: "Sensibilidad",
              value: state.sensitivity == "Alta" ? "70%" : state.sensitivity,
              onTap: () {
                String newSens = "70%";
                if (state.sensitivity == "70%" || state.sensitivity == "Alta") {
                  newSens = "90%";
                } else if (state.sensitivity == "90%") {
                  newSens = "50%";
                }
                state.updateSensitivity(newSens);
                announceUi(
                  context,
                  "Sensibilidad de detección fijada al $newSens.",
                );
              },
            ),
            // La opción "Alto contraste" era decorativa (no cambiaba nada) y se
            // quitó para no engañar al usuario.

            const SizedBox(height: 16),
            const Divider(color: Color(0xFF1B2C3F), height: 1),
            const SizedBox(height: 16),

            _buildSectionHeader("SOPORTE"),

            _buildSupportRow(
              label: "Ayuda y comandos",
              onTap: () {
                speakUi(context, "Abriendo pantalla de ayuda.");
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AyudaScreen()),
                );
              },
            ),
            _buildSupportRow(
              label: "Acerca de Riqsi",
              onTap: () {
                speakUi(
                  context,
                  "Riqsi es un asistente inteligente de visión del entorno para la autonomía de personas con discapacidad visual.",
                );
                _showAboutDialog(context);
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: const TextStyle(
            color: RiqsiTheme.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileRow(BuildContext context, AppState state) {
    final String displayName =
        state.hasUserName ? state.userName : "Sin nombre";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF0C1622),
                shape: BoxShape.circle,
                border: Border.all(color: RiqsiTheme.accentCyan, width: 1.5),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: RiqsiTheme.accentCyan,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.hasUserName
                      ? "Usuario activo"
                      : "Toca el lápiz para añadir tu nombre",
                  style: const TextStyle(
                    color: RiqsiTheme.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          A11yTap(
            label: "Editar nombre",
            onTap: () => _showNameEditDialog(context, state),
            child: const Icon(
              Icons.edit_rounded,
              color: RiqsiTheme.accentCyan,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: "$label, valor actual $value",
      hint: "Toca dos veces para modificar esta preferencia",
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: RiqsiTheme.textSecondary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
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

  Widget _buildSupportRow({
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      hint: "Toca dos veces para abrir esta sección",
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: RiqsiTheme.accentCyan,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNameEditDialog(BuildContext context, AppState state) {
    final initial = state.userName;
    showDialog<void>(
      context: context,
      builder: (_) => _TextEditDialog(
        title: "Editar Nombre",
        label: "Nombre",
        hint: "Escribe tu nombre",
        initialValue: initial,
        keyboardType: TextInputType.name,
        // Vacío está permitido: se usa un saludo genérico.
        validator: (v) =>
            v.trim().length > 40 ? "El nombre es demasiado largo." : null,
        onSave: (v) {
          final name = v.trim();
          state.updateUserName(name);
          announceUi(
            context,
            name.isEmpty ? "Nombre borrado." : "Nombre cambiado a $name.",
          );
        },
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: RiqsiTheme.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Acerca de Riqsi",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          content: const Text(
            "Riqsi es un asistente visual diseñado para brindar autonomía y acompañamiento a personas con discapacidad visual.\n\nUtiliza la cámara y visión artificial del entorno para detectar obstáculos y riesgos en tiempo real.",
            style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cerrar",
                style: TextStyle(
                  color: RiqsiTheme.accentCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Diálogo de edición de un texto con validación accesible. El controlador
/// vive y se libera en su propio State.
class _TextEditDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String initialValue;
  final TextInputType? keyboardType;
  final String? Function(String) validator;
  final ValueChanged<String> onSave;

  const _TextEditDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.validator,
    required this.onSave,
    this.keyboardType,
  });

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.validator(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      SemanticsService.sendAnnouncement(
        View.of(context),
        error,
        TextDirection.ltr,
      );
      return;
    }
    widget.onSave(_controller.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: RiqsiTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: RiqsiTheme.textSecondary),
          errorText: _error,
          errorMaxLines: 3,
          errorStyle: const TextStyle(color: Color(0xFFFF8A80), fontSize: 16),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: RiqsiTheme.accentCyan),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: RiqsiTheme.accentCyan, width: 2),
          ),
          hintText: widget.hint,
          hintStyle: const TextStyle(color: RiqsiTheme.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(context),
          child: const Text(
            "Cancelar",
            style: TextStyle(color: RiqsiTheme.textSecondary, fontSize: 16),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: RiqsiTheme.accentCyan,
            minimumSize: const Size(48, 48),
          ),
          onPressed: _submit,
          child: const Text(
            "Guardar",
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

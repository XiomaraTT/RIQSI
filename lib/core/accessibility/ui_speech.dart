import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';

/// Habla un texto de interfaz (eco de UI) con el TTS propio de la app,
/// salvo que un lector de pantalla (TalkBack/VoiceOver) esté activo: en ese
/// caso el lector ya anuncia la etiqueta y hablar dos veces satura al usuario.
///
/// No usar para alertas de peligro: esas las gestiona AppState siempre.
void speakUi(BuildContext context, String text) {
  if (text.isEmpty) return;
  if (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false) return;
  context.read<AppState>().speak(text);
}

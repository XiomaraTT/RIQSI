/// Prioridad de una frase.
///
/// - [alert]: alertas de peligro (riesgo Alto, pérdida de conexión). Cortan
///   cualquier frase normal y no pueden ser cortadas por frases normales.
/// - [normal]: frases de interfaz/estado. Cortan otra frase normal, pero si
///   hay una alerta sonando o pendiente esperan a que termine.
enum SpeechPriority { normal, alert }

abstract class TtsRepository {
  Future<void> speak(
    String text,
    double rate,
    double volume, {
    SpeechPriority priority = SpeechPriority.normal,
  });

  /// Detiene la frase actual y vacía la cola (incluidas alertas).
  Future<void> stop();
}

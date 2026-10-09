/// Valores canónicos de `distancia` (analizador de escena en el celular).
class Proximity {
  static const muyCerca = 'muy_cerca';
  static const cerca = 'cerca';
  static const lejos = 'lejos';
  static const despejado = 'despejado';

  /// Normaliza la distancia recibida. Versiones antiguas
  /// enviaban "inmediato" para huecos: se trata como "muy_cerca".
  /// Devuelve null si el valor es desconocido.
  static String? normalize(String? raw) {
    final v = raw?.trim().toLowerCase();
    switch (v) {
      case muyCerca:
      case 'inmediato':
        return muyCerca;
      case cerca:
      case lejos:
      case despejado:
        return v;
      default:
        return null;
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Archivo de clases del modelo propio (una clase por línea, en el mismo
/// orden que los índices de salida del modelo `[1, 4 + nc, 8400]`).
const String riqsiLabelsAsset = 'assets/labels.txt';

/// Convierte el contenido de `labels.txt` en la lista de clases: ignora
/// líneas vacías, espacios y saltos de línea de Windows.
List<String> parseLabels(String raw) => raw
    .split(RegExp(r'\r?\n'))
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList(growable: false);

/// Lee las clases del modelo desde [riqsiLabelsAsset] (no hay lista en duro).
///
/// Devuelve una lista vacía si el asset no existe o no se puede leer; el
/// analizador de escena acepta entonces cualquier clase que mande el modelo.
Future<List<String>> loadModelLabels({
  AssetBundle? bundle,
  String asset = riqsiLabelsAsset,
}) async {
  try {
    final raw = await (bundle ?? rootBundle).loadString(asset);
    final labels = parseLabels(raw);
    debugPrint('[MODEL] ${labels.length} clases cargadas desde $asset');
    return labels;
  } catch (e) {
    debugPrint('[MODEL] No se pudo leer $asset: $e');
    return const [];
  }
}

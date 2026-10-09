// STUB mínimo para compilar: el integrador lo reemplaza por la versión real
// (misma API). No añadir lógica aquí.

/// Detección cruda del modelo, con la caja normalizada (0..1).
class RawDetection {
  const RawDetection({
    required this.className,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  final String className;
  final double confidence;
  final double left, top, right, bottom;
}

class SceneObject {
  const SceneObject({
    required this.label,
    required this.pos,
    required this.risk,
    required this.distancia,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.advice,
  });
  final String label;
  final String pos; // 'izquierda' | 'centro' | 'derecha'
  final String risk; // 'Alto' | 'Medio' | 'Bajo'
  final String distancia; // 'muy_cerca' | 'cerca' | 'lejos' | 'despejado'
  final double left, top, right, bottom;
  final String advice;
}

class SceneResult {
  const SceneResult({
    required this.objects,
    required this.top,
    required this.description,
    required this.risk,
    required this.distancia,
    required this.announce,
  });
  final List<SceneObject> objects;
  final SceneObject? top;
  final String description;
  final String risk;
  final String distancia;
  final bool announce;
  bool get isClear => objects.isEmpty;
}

class SceneAnalyzer {
  SceneAnalyzer({this.minConfidence = 0.35});
  final double minConfidence;
  String? _lastKey;

  SceneResult analyse(List<RawDetection> detections, {required int nowMs}) {
    final objects = <SceneObject>[
      for (final d in detections)
        if (d.confidence >= minConfidence)
          SceneObject(
            label: d.className,
            pos: (d.left + d.right) / 2 < 0.33
                ? 'izquierda'
                : ((d.left + d.right) / 2 > 0.66 ? 'derecha' : 'centro'),
            risk: (d.bottom - d.top) > 0.6 ? 'Alto' : 'Medio',
            distancia: (d.bottom - d.top) > 0.6 ? 'muy_cerca' : 'cerca',
            left: d.left,
            top: d.top,
            right: d.right,
            bottom: d.bottom,
            advice: '',
          ),
    ];
    final top = objects.isEmpty ? null : objects.first;
    final key = top == null ? null : '${top.label}|${top.pos}|${top.distancia}';
    final announce = key != null && key != _lastKey;
    _lastKey = key;
    return SceneResult(
      objects: objects,
      top: top,
      description: top == null ? '' : '${top.label} ${top.pos}',
      risk: top?.risk ?? 'Bajo',
      distancia: top?.distancia ?? 'despejado',
      announce: announce,
    );
  }

  void reset() => _lastKey = null;
}

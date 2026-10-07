class DetectedObject {
  final String label;
  final String relativePosition;
  final String riskLevel;
  final String distancia;
  final List<int> box;
  final List<double> boxNorm;

  DetectedObject({
    required this.label,
    required this.relativePosition,
    required this.riskLevel,
    this.distancia = "lejos",
    required this.box,
    this.boxNorm = const [],
  });
}

class AppSettings {
  final double voiceSpeed;
  final double volume;
  final bool vibrationEnabled;
  final String alertFrequency;
  final String sensitivity;
  final String language;
  /// Nombre del usuario; vacío si no lo indicó (saludo genérico).
  final String userName;

  AppSettings({
    required this.voiceSpeed,
    required this.volume,
    required this.vibrationEnabled,
    required this.alertFrequency,
    required this.sensitivity,
    required this.language,
    required this.userName,
  });

  AppSettings copyWith({
    double? voiceSpeed,
    double? volume,
    bool? vibrationEnabled,
    String? alertFrequency,
    String? sensitivity,
    String? language,
    String? userName,
  }) {
    return AppSettings(
      voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      volume: volume ?? this.volume,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      alertFrequency: alertFrequency ?? this.alertFrequency,
      sensitivity: sensitivity ?? this.sensitivity,
      language: language ?? this.language,
      userName: userName ?? this.userName,
    );
  }

  static AppSettings get defaults => AppSettings(
        voiceSpeed: 1.0,
        volume: 0.8,
        vibrationEnabled: true,
        alertFrequency: 'Alta',
        sensitivity: 'Alta',
        language: 'Español',
        userName: '',
      );

  Map<String, dynamic> toMap() => {
        'voiceSpeed': voiceSpeed,
        'volume': volume,
        'vibrationEnabled': vibrationEnabled,
        'alertFrequency': alertFrequency,
        'sensitivity': sensitivity,
        'language': language,
        'userName': userName,
      };

  /// Lee un mapa persistido; los campos ausentes o inválidos toman el valor
  /// por defecto.
  factory AppSettings.fromMap(Map<String, dynamic> map) {
    final d = AppSettings.defaults;
    double numOr(dynamic v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    String strOr(dynamic v, String fallback) => v is String ? v : fallback;
    return AppSettings(
      voiceSpeed: numOr(map['voiceSpeed'], d.voiceSpeed),
      volume: numOr(map['volume'], d.volume),
      vibrationEnabled: map['vibrationEnabled'] is bool
          ? map['vibrationEnabled'] as bool
          : d.vibrationEnabled,
      alertFrequency: strOr(map['alertFrequency'], d.alertFrequency),
      sensitivity: strOr(map['sensitivity'], d.sensitivity),
      language: strOr(map['language'], d.language),
      userName: _migrateName(strOr(map['userName'], d.userName)),
    );
  }

  /// Nombres de ejemplo que versiones anteriores guardaban de fábrica: se
  /// tratan como "sin nombre".
  static const _legacyDefaultNames = {
    'Xiomara Torres',
    'María González',
    'Usuario Riqsi',
  };

  static String _migrateName(String name) =>
      _legacyDefaultNames.contains(name.trim()) ? '' : name;
}

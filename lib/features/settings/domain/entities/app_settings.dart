class AppSettings {
  final double voiceSpeed;
  final double volume;
  final bool vibrationEnabled;
  final String alertFrequency;
  final String sensitivity;
  final String language;
  final String userName;
  final String serverIp;

  AppSettings({
    required this.voiceSpeed,
    required this.volume,
    required this.vibrationEnabled,
    required this.alertFrequency,
    required this.sensitivity,
    required this.language,
    required this.userName,
    required this.serverIp,
  });

  AppSettings copyWith({
    double? voiceSpeed,
    double? volume,
    bool? vibrationEnabled,
    String? alertFrequency,
    String? sensitivity,
    String? language,
    String? userName,
    String? serverIp,
  }) {
    return AppSettings(
      voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      volume: volume ?? this.volume,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      alertFrequency: alertFrequency ?? this.alertFrequency,
      sensitivity: sensitivity ?? this.sensitivity,
      language: language ?? this.language,
      userName: userName ?? this.userName,
      serverIp: serverIp ?? this.serverIp,
    );
  }

  static AppSettings get defaults => AppSettings(
        voiceSpeed: 1.0,
        volume: 0.8,
        vibrationEnabled: true,
        alertFrequency: 'Alta',
        sensitivity: 'Alta',
        language: 'Español',
        userName: 'Xiomara Torres',
        serverIp: '10.247.64.45',
      );

  Map<String, dynamic> toMap() => {
        'voiceSpeed': voiceSpeed,
        'volume': volume,
        'vibrationEnabled': vibrationEnabled,
        'alertFrequency': alertFrequency,
        'sensitivity': sensitivity,
        'language': language,
        'userName': userName,
        'serverIp': serverIp,
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
      userName: strOr(map['userName'], d.userName),
      serverIp: strOr(map['serverIp'], d.serverIp),
    );
  }
}

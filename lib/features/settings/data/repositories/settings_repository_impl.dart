import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  AppSettings _settings = AppSettings(
    voiceSpeed: 1.0,
    volume: 0.8,
    vibrationEnabled: true,
    alertFrequency: 'Alta',
    sensitivity: 'Alta',
    language: 'Español',
    userName: 'Xiomara Torres',
    serverIp: '10.247.64.45',
  );

  @override
  Future<AppSettings> getSettings() async {
    return _settings;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}

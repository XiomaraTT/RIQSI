import '../entities/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<void> saveSettings(AppSettings settings);

  /// Indica si el usuario ya completó el onboarding.
  Future<bool> isOnboardingSeen();
  Future<void> setOnboardingSeen(bool seen);
}

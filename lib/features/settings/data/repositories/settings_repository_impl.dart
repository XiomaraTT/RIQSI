import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

typedef PrefsProvider = Future<SharedPreferences> Function();

/// Ajustes persistidos en SharedPreferences. Si el almacenamiento no está
/// disponible (p.ej. en tests sin mock) se trabaja en memoria.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({PrefsProvider? prefs})
      : _prefsProvider = prefs ?? SharedPreferences.getInstance;

  static const settingsKey = 'riqsi.settings.v1';
  static const onboardingKey = 'riqsi.onboarding_seen';

  final PrefsProvider _prefsProvider;
  AppSettings _settings = AppSettings.defaults;
  bool _onboardingSeen = false;
  bool _loaded = false;

  Future<SharedPreferences?> _prefs() async {
    try {
      return await _prefsProvider();
    } catch (e) {
      debugPrint('[SETTINGS] Almacenamiento no disponible: $e');
      return null;
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await _prefs();
    if (prefs == null) return;
    try {
      final raw = prefs.getString(settingsKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is Map<String, dynamic>) {
          _settings = AppSettings.fromMap(data);
        }
      }
      _onboardingSeen = prefs.getBool(onboardingKey) ?? false;
    } catch (e) {
      debugPrint('[SETTINGS] Ajustes guardados ilegibles, se usan los de fábrica: $e');
    }
  }

  @override
  Future<AppSettings> getSettings() async {
    await _load();
    return _settings;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
    final prefs = await _prefs();
    try {
      await prefs?.setString(settingsKey, jsonEncode(settings.toMap()));
    } catch (e) {
      debugPrint('[SETTINGS] No se pudieron guardar los ajustes: $e');
    }
  }

  @override
  Future<bool> isOnboardingSeen() async {
    await _load();
    return _onboardingSeen;
  }

  @override
  Future<void> setOnboardingSeen(bool seen) async {
    _onboardingSeen = seen;
    final prefs = await _prefs();
    try {
      await prefs?.setBool(onboardingKey, seen);
    } catch (e) {
      debugPrint('[SETTINGS] No se pudo guardar el onboarding: $e');
    }
  }
}

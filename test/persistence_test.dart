import 'package:flutter_test/flutter_test.dart';
import 'package:riqsi/features/history/data/repositories/history_repository_impl.dart';
import 'package:riqsi/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:riqsi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

DetectionEvent _event(int i, {bool clear = false}) => DetectionEvent(
      id: 'e$i',
      label: 'Objeto $i',
      relativePosition: 'Adelante',
      riskLevel: 'Medio',
      timestamp: DateTime(2026, 1, 1, 12, 0, i % 60),
      description: 'Objeto $i adelante',
      isClear: clear,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsRepositoryImpl', () {
    test('sin datos guardados devuelve los valores por defecto', () async {
      final repo = SettingsRepositoryImpl();
      final s = await repo.getSettings();
      expect(s.userName, isEmpty, reason: 'sin nombre de fábrica');
      expect(await repo.isOnboardingSeen(), isFalse);
    });

    test('los ajustes y el onboarding sobreviven a un reinicio', () async {
      final repo = SettingsRepositoryImpl();
      final s = await repo.getSettings();
      await repo.saveSettings(
          s.copyWith(volume: 0.3, userName: 'Ana', vibrationEnabled: false));
      await repo.setOnboardingSeen(true);

      final reopened = SettingsRepositoryImpl();
      final loaded = await reopened.getSettings();
      expect(loaded.volume, 0.3);
      expect(loaded.userName, 'Ana');
      expect(loaded.vibrationEnabled, isFalse);
      expect(await reopened.isOnboardingSeen(), isTrue);
    });

    test('nombres de ejemplo antiguos se tratan como sin nombre', () {
      expect(AppSettings.fromMap({'userName': 'Xiomara Torres'}).userName,
          isEmpty);
      expect(AppSettings.fromMap({'userName': 'Luis'}).userName, 'Luis');
      expect(AppSettings.fromMap({'serverIp': '1.2.3.4'}).userName, isEmpty);
    });

    test('datos corruptos no rompen la carga', () async {
      SharedPreferences.setMockInitialValues(
          {SettingsRepositoryImpl.settingsKey: '{no json'});
      final s = await SettingsRepositoryImpl().getSettings();
      expect(s.voiceSpeed, AppSettings.defaults.voiceSpeed);
    });
  });

  group('HistoryRepositoryImpl', () {
    test('empieza vacío (sin eventos semilla falsos)', () async {
      expect(await HistoryRepositoryImpl().getHistory(), isEmpty);
    });

    test('ignora clear, respeta tope 100 y persiste', () async {
      final repo = HistoryRepositoryImpl();
      await repo.addEvent(_event(0, clear: true));
      for (var i = 1; i <= 105; i++) {
        await repo.addEvent(_event(i));
      }
      final list = await repo.getHistory();
      expect(list, hasLength(100));
      expect(list.first.id, 'e105');
      expect(list.any((e) => e.isClear), isFalse);

      final reopened = await HistoryRepositoryImpl().getHistory();
      expect(reopened, hasLength(100));
      expect(reopened.first.label, 'Objeto 105');
      expect(reopened.last.id, 'e6');
    });
  });

  group('AppState + onboarding', () {
    AppState build() => AppState(
          ttsRepository: RecordingTtsRepository(),
          vibrationRepository: NoopVibrationRepository(),
          splashDuration: Duration.zero,
        );

    test('primer arranque va al onboarding; el segundo, directo al inicio',
        () async {
      final first = build();
      await first.ready;
      await flush();
      expect(first.currentScreen, AppScreen.onboarding);

      // El usuario termina la configuración inicial.
      first.navigateToScreen(AppScreen.mainLayout);
      await flush();
      first.dispose();

      final second = build();
      await second.ready;
      await flush();
      expect(second.onboardingSeen, isTrue);
      expect(second.currentScreen, AppScreen.mainLayout);
      second.dispose();
    });

    test('los ajustes cambiados desde AppState se recuerdan', () async {
      final first = build();
      await first.ready;
      first.updateVoiceSpeed(1.5);
      first.toggleVibration(false);
      await flush();
      first.dispose();

      final second = build();
      await second.ready;
      expect(second.voiceSpeed, 1.5);
      expect(second.vibrationEnabled, isFalse);
      second.dispose();
    });
  });
}

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// Domain Entities
import '../features/assistant/domain/entities/detected_object.dart';
import '../features/assistant/domain/entities/detection_event.dart';
import '../features/assistant/domain/scene/scene_logic.dart';
import '../features/settings/domain/entities/app_settings.dart';
import '../features/map/domain/entities/navigation_step.dart';

// Domain Repositories
import '../features/assistant/domain/repositories/tts_repository.dart';
import '../features/assistant/domain/repositories/vibration_repository.dart';
import '../features/history/domain/repositories/history_repository.dart';
import '../features/settings/domain/repositories/settings_repository.dart';

// Data Layers
import '../features/assistant/data/repositories/tts_repository_impl.dart';
import '../features/assistant/data/repositories/vibration_repository_impl.dart';
import '../features/history/data/repositories/history_repository_impl.dart';
import '../features/settings/data/repositories/settings_repository_impl.dart';
import '../features/map/data/repositories/navigation_repository_impl.dart';

// Domain Use Cases
import '../features/assistant/domain/usecases/speak_text.dart';
import '../features/assistant/domain/usecases/vibrate_device.dart';
import '../features/history/domain/usecases/get_history.dart';
import '../features/history/domain/usecases/add_history.dart';
import '../features/settings/domain/usecases/get_settings.dart';
import '../features/settings/domain/usecases/save_settings.dart';

export '../features/assistant/domain/entities/detected_object.dart';
export '../features/assistant/domain/entities/detection_event.dart';
export '../features/assistant/domain/repositories/tts_repository.dart'
    show SpeechPriority;
export '../features/settings/domain/entities/app_settings.dart';
export '../features/map/domain/entities/navigation_step.dart';

enum AppScreen {
  splash,
  onboarding,
  initialConfig,
  mainLayout
}

enum AssistanceState {
  inactive,
  analyzing,
  objectDetected,
  riskDetected
}

class AppState extends ChangeNotifier {
  /// Intervalo mínimo entre resultados procesados (~8 por segundo).
  static const int minProcessIntervalMs = 120;

  /// Sin detecciones nuevas durante este tiempo, se vuelve a "Analizando".
  static const Duration detectionHoldTime = Duration(milliseconds: 1500);

  /// Tras "Entendido" en la alerta, el mismo peligro no vuelve a abrir la
  /// alerta a pantalla completa durante este tiempo (sí se sigue avisando).
  static const Duration alertDismissCooldown = Duration(seconds: 6);
  static const int maxHistoryEntries = HistoryRepository.maxEntries;

  // Infrastructure references
  late final TtsRepository _ttsRepository;
  late final VibrationRepository _vibrationRepository;
  late final HistoryRepository _historyRepository;
  late final SettingsRepository _settingsRepository;
  late final NavigationRepositoryImpl _navigationRepository;
  late final SceneAnalyzer _sceneAnalyzer;
  late final int Function() _nowMs;

  // Use case references
  late final SpeakText _speakText;
  late final VibrateDevice _vibrateDevice;
  late final GetHistory _getHistory;
  late final AddHistory _addHistory;
  late final GetSettings _getSettings;
  late final SaveSettings _saveSettings;

  // Presentation State
  AppScreen currentScreen = AppScreen.splash;
  int currentTab = 0; // 0: Inicio, 1: Mapa, 2: Perfil

  AppSettings? _settings;
  final List<DetectionEvent> _cachedHistory = [];
  late final Future<void> _ready;
  bool _onboardingSeen = false;

  AssistanceState assistanceState = AssistanceState.inactive;
  String currentStatusMessage = "Riqsi está listo";
  String lastSpokenDescription = "";

  bool hasCameraPermission = true;
  bool isCameraError = false;
  bool isImmersiveMode = false;
  DetectionEvent? activeDetection;

  // Detección en el celular
  final Stopwatch _clock = Stopwatch()..start();
  int? _lastProcessedMs;
  int _eventCounter = 0;
  String? _dismissedAlertKey;
  int? _dismissedAtMs;

  // Timers (todos cancelables en dispose)
  Timer? _splashTimer;
  Timer? _autoClearTimer;
  bool _disposed = false;

  // Navigation State (Pestaña Mapa para guía accesible)
  NavigationStep? currentNavStep;
  bool isNavigating = false;
  List<NavigationStep> currentRouteSteps = [];
  int currentStepIndex = 0;
  String activeDestination = "";
  bool isNavApiConnected = true;

  // Exposing settings attributes via getters for UI backwards-compatibility
  double get voiceSpeed => _settings?.voiceSpeed ?? 1.0;
  double get volume => _settings?.volume ?? 0.8;
  bool get vibrationEnabled => _settings?.vibrationEnabled ?? true;
  String get alertFrequency => _settings?.alertFrequency ?? 'Alta';
  String get sensitivity => _settings?.sensitivity ?? 'Alta';
  String get language => _settings?.language ?? 'Español';
  String get userName => _settings?.userName ?? '';
  bool get hasUserName => userName.trim().isNotEmpty;

  /// Saludo personalizado, o genérico si no hay nombre.
  String get greeting => hasUserName ? "Hola, ${userName.trim()}." : "Hola.";

  /// Historial (más reciente primero, máx. 100). Vista de solo lectura, sin
  /// copiar la lista en cada evento.
  List<DetectionEvent> get history => UnmodifiableListView(_cachedHistory);
  String get navigationApiUrl => _navigationRepository.getApiUrl();

  bool get onboardingSeen => _onboardingSeen;

  bool get isAssisting => assistanceState != AssistanceState.inactive;

  /// Volumen usado para alertas de peligro: nunca silencio, aunque el
  /// usuario haya silenciado la voz.
  double get alertVolume => volume <= 0.01 ? 1.0 : math.max(volume, 0.6);

  /// Estado grande de Inicio, p. ej. "Persona muy cerca · centro".
  String get statusHeadline {
    if (!isAssisting) return "Asistencia detenida";
    final d = activeDetection;
    if (d == null) return "Camino despejado";
    return headlineFor(d);
  }

  /// Riesgo del estado actual ('Alto' | 'Medio' | 'Bajo') o '' si no hay.
  String get statusRisk => activeDetection?.riskLevel ?? '';

  static String distanceLabel(String distancia) {
    switch (distancia) {
      case 'muy_cerca':
        return 'muy cerca';
      case 'cerca':
        return 'cerca';
      case 'lejos':
        return 'lejos';
      default:
        return '';
    }
  }

  static String headlineFor(DetectionEvent d) {
    final label = d.label.isEmpty
        ? 'Obstáculo'
        : d.label[0].toUpperCase() + d.label.substring(1);
    final dist = distanceLabel(d.distancia);
    final head = dist.isEmpty ? label : '$label $dist';
    return d.relativePosition.isEmpty ? head : '$head · ${d.relativePosition}';
  }

  AppState({
    TtsRepository? ttsRepository,
    VibrationRepository? vibrationRepository,
    HistoryRepository? historyRepository,
    SettingsRepository? settingsRepository,
    NavigationRepositoryImpl? navigationRepository,
    SceneAnalyzer? sceneAnalyzer,
    int Function()? clockMs,
    Duration splashDuration = const Duration(seconds: 3),
  }) {
    // DI setup
    _ttsRepository = ttsRepository ?? TtsRepositoryImpl();
    _vibrationRepository = vibrationRepository ?? VibrationRepositoryImpl();
    _historyRepository = historyRepository ?? HistoryRepositoryImpl();
    _settingsRepository = settingsRepository ?? SettingsRepositoryImpl();
    _navigationRepository = navigationRepository ?? NavigationRepositoryImpl();
    _sceneAnalyzer = sceneAnalyzer ?? SceneAnalyzer();
    _nowMs = clockMs ?? () => _clock.elapsedMilliseconds;

    _speakText = SpeakText(_ttsRepository);
    _vibrateDevice = VibrateDevice(_vibrationRepository);
    _getHistory = GetHistory(_historyRepository);
    _addHistory = AddHistory(_historyRepository);
    _getSettings = GetSettings(_settingsRepository);
    _saveSettings = SaveSettings(_settingsRepository);

    _initNavigation();
    _ready = _init();

    // Start splash screen countdown
    _splashTimer = Timer(splashDuration, () async {
      await _ready;
      if (_disposed || currentScreen != AppScreen.splash) return;
      navigateToScreen(
          _onboardingSeen ? AppScreen.mainLayout : AppScreen.onboarding);
    });
  }

  /// Completa cuando se cargaron ajustes, historial y flag de onboarding.
  Future<void> get ready => _ready;

  Future<void> _init() async {
    try {
      final loaded = await _getSettings.execute();
      // Si el usuario cambió algo antes de terminar la carga, se respeta.
      _settings ??= loaded;
      _onboardingSeen = await _settingsRepository.isOnboardingSeen();
      final stored = await _getHistory.execute();
      _cachedHistory
        ..clear()
        ..addAll(stored.where((e) => !e.isClear).take(maxHistoryEntries));
    } catch (e) {
      debugPrint('[APP] Error cargando datos locales: $e');
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void navigateToScreen(AppScreen screen) {
    currentScreen = screen;
    if (screen == AppScreen.mainLayout) {
      // Siempre se entra a la pantalla principal por la pestaña Inicio.
      currentTab = 0;
      if (!_onboardingSeen) {
        // Llegar a la pantalla principal marca el onboarding como visto.
        completeOnboarding();
      }
    }
    notifyListeners();
  }

  /// Marca el onboarding como visto (persistido) para no repetirlo.
  Future<void> completeOnboarding() async {
    _onboardingSeen = true;
    await _settingsRepository.setOnboardingSeen(true);
  }

  void setTab(int index) {
    currentTab = index;
    notifyListeners();
  }

  // Settings update wrappers
  AppSettings get _currentSettings => _settings ?? AppSettings.defaults;

  Future<void> _updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    await _saveSettings.execute(newSettings);
  }

  void updateVoiceSpeed(double val) {
    _updateSettings(_currentSettings.copyWith(voiceSpeed: val));
  }

  void updateVolume(double val) {
    _updateSettings(_currentSettings.copyWith(volume: val));
  }

  void toggleVibration(bool val) {
    _updateSettings(_currentSettings.copyWith(vibrationEnabled: val));
    if (!val) _vibrationRepository.stop();
  }

  void updateAlertFrequency(String val) {
    _updateSettings(_currentSettings.copyWith(alertFrequency: val));
  }

  void updateSensitivity(String val) {
    _updateSettings(_currentSettings.copyWith(sensitivity: val));
  }

  /// Guarda el nombre (vacío = sin nombre, saludo genérico).
  void updateUserName(String val) {
    _updateSettings(_currentSettings.copyWith(userName: val.trim()));
  }

  // ==========================================
  // VOZ Y VIBRACIÓN
  // ==========================================

  /// Frase normal de interfaz. Respeta el silencio (volumen 0) del usuario y
  /// no corta una alerta de peligro en curso.
  void speak(String text) {
    if (text.trim().isEmpty) return;
    lastSpokenDescription = text;
    notifyListeners();
    if (volume <= 0.01) return; // voz silenciada por el usuario
    _speakText.execute(text, voiceSpeed, volume);
  }

  /// Alerta de peligro: interrumpe cualquier frase normal y suena aunque el
  /// usuario haya silenciado la voz.
  void speakAlert(String text) {
    if (text.trim().isEmpty) return;
    lastSpokenDescription = text;
    notifyListeners();
    _speakText.execute(text, voiceSpeed, alertVolume,
        priority: SpeechPriority.alert);
  }

  void testVoice() {
    speak("Prueba de voz en Riqsi. Todo funciona correctamente.");
  }

  void vibrate(int durationMs) {
    if (!vibrationEnabled) return;
    _vibrateDevice.execute(durationMs);
  }

  void repeatLastSpoken() {
    if (lastSpokenDescription.isNotEmpty) {
      speak(lastSpokenDescription);
    } else {
      speak(currentStatusMessage);
    }
  }

  // ==========================================
  // ASISTENCIA (DETECCIÓN EN EL CELULAR)
  // ==========================================

  void toggleAssistance() {
    if (assistanceState == AssistanceState.inactive) {
      assistanceState = AssistanceState.analyzing;
      currentStatusMessage = "Analizando entorno...";
      _sceneAnalyzer.reset();
      _lastProcessedMs = null;
      _dismissedAlertKey = null;
      speak("Asistencia iniciada. Apunta el teléfono hacia adelante.");
      vibrate(150);
    } else {
      _vibrationRepository.stop(); // Detener vibración en bucle
      _autoClearTimer?.cancel();
      assistanceState = AssistanceState.inactive;
      currentStatusMessage = "Riqsi está listo";
      activeDetection = null;
      _speakText.stop();
      speak("Asistencia detenida.");
      vibrate(100);
    }
    notifyListeners();
  }

  void toggleImmersiveMode() => setImmersiveMode(!isImmersiveMode);

  void setImmersiveMode(bool value) {
    if (isImmersiveMode == value) return;
    isImmersiveMode = value;
    if (isImmersiveMode) {
      speak("Modo inmersivo activado. Pantalla completa.");
      vibrate(80);
    } else {
      speak("Modo inmersivo desactivado. Regresando a vista estándar.");
      vibrate(60);
    }
    notifyListeners();
  }

  /// Entrada de la cámara: detecciones crudas del modelo YOLO. Se procesan
  /// como máximo ~8 por segundo ([minProcessIntervalMs]); el resto se
  /// descarta.
  void onRawDetections(List<RawDetection> detections) {
    if (_disposed || assistanceState == AssistanceState.inactive) return;
    final now = _nowMs();
    final last = _lastProcessedMs;
    if (last != null && now - last < minProcessIntervalMs) return;
    _lastProcessedMs = now;

    final SceneResult result;
    try {
      result = _sceneAnalyzer.analyse(detections, nowMs: now);
    } catch (e) {
      debugPrint("[APP] Error analizando la escena: $e");
      return;
    }
    applyDetection(eventFromScene(
      result,
      id: 'det_${now}_${_eventCounter++}',
      at: DateTime.now(),
    ));
  }

  /// Convierte el resultado del analizador de escena en un evento de la app.
  static DetectionEvent eventFromScene(SceneResult r,
      {required String id, required DateTime at}) {
    final top = r.top;
    return DetectionEvent(
      id: id,
      label: top?.label ?? '',
      relativePosition: top?.pos ?? '',
      riskLevel: r.isClear ? 'Bajo' : r.risk,
      timestamp: at,
      description: r.description,
      distancia: r.isClear ? 'despejado' : r.distancia,
      announceVoice: r.announce,
      isClear: r.isClear,
      objects: [
        for (final o in r.objects)
          DetectedObject(
            label: o.label,
            relativePosition: o.pos,
            riskLevel: o.risk,
            distancia: o.distancia,
            box: const [],
            boxNorm: [o.left, o.top, o.right, o.bottom],
          ),
      ],
    );
  }

  /// Aplica un evento de detección: vibración por distancia, voz (solo si
  /// [DetectionEvent.announceVoice]), historial, estado visual y alerta a
  /// pantalla completa para riesgo Alto.
  void applyDetection(DetectionEvent event) {
    if (_disposed || assistanceState == AssistanceState.inactive) return;

    if (vibrationEnabled) {
      _vibrationRepository.triggerProximityFeedback(event.distancia);
    } else {
      _vibrationRepository.stop();
    }

    // Escena despejada: lo mostrado se borra solo tras [detectionHoldTime].
    if (event.isClear) return;

    final high = event.isHighRisk;
    final showOverlay = high && !_isAlertDismissed(event);
    assistanceState = showOverlay
        ? AssistanceState.riskDetected
        : AssistanceState.objectDetected;
    final headline = headlineFor(event);
    currentStatusMessage = high ? "¡Cuidado! $headline" : headline;
    activeDetection = event;

    if (event.announceVoice) {
      final text =
          event.description.isNotEmpty ? event.description : headline;
      if (high) {
        speakAlert(text);
      } else {
        speak(text);
      }
      _recordHistory(event);
    }

    _scheduleAutoClear(event);
    notifyListeners();
  }

  static String _alertKey(DetectionEvent e) =>
      "${e.label}|${e.relativePosition}";

  bool _isAlertDismissed(DetectionEvent event) {
    final at = _dismissedAtMs;
    return at != null &&
        _dismissedAlertKey == _alertKey(event) &&
        _nowMs() - at < alertDismissCooldown.inMilliseconds;
  }

  void _recordHistory(DetectionEvent event) {
    if (event.isClear) return;
    _cachedHistory.insert(0, event);
    if (_cachedHistory.length > maxHistoryEntries) {
      _cachedHistory.removeRange(maxHistoryEntries, _cachedHistory.length);
    }
    _addHistory.execute(event).catchError((Object e) {
      debugPrint("[APP] No se pudo guardar en el historial: $e");
    });
  }

  /// Un único timer cancelable para volver a "Analizando" tras un evento.
  void _scheduleAutoClear(DetectionEvent event) {
    _autoClearTimer?.cancel();
    _autoClearTimer = Timer(detectionHoldTime, () {
      if (activeDetection?.id != event.id) return;
      if (assistanceState == AssistanceState.objectDetected ||
          assistanceState == AssistanceState.riskDetected) {
        assistanceState = AssistanceState.analyzing;
        currentStatusMessage = "Analizando entorno...";
        activeDetection = null;
        notifyListeners();
      }
    });
  }

  void dismissAlert() {
    _autoClearTimer?.cancel();
    final current = activeDetection;
    if (current != null && current.isHighRisk) {
      _dismissedAlertKey = _alertKey(current);
      _dismissedAtMs = _nowMs();
    }
    activeDetection = null;
    if (assistanceState == AssistanceState.inactive) {
      notifyListeners();
      return;
    }
    assistanceState = AssistanceState.analyzing;
    currentStatusMessage = "Analizando entorno...";
    speak("Alerta entendida. Reanudando asistencia.");
    vibrate(100);
    notifyListeners();
  }

  // ==========================================
  // CÁMARA
  // ==========================================

  /// La cámara y el modelo se inicializaron correctamente.
  void reportCameraReady() {
    if (hasCameraPermission && !isCameraError) return;
    hasCameraPermission = true;
    isCameraError = false;
    notifyListeners();
  }

  /// El sistema denegó el permiso de cámara.
  void reportCameraPermissionDenied() {
    if (!hasCameraPermission) return;
    hasCameraPermission = false;
    isCameraError = false;
    speak("No hay permiso de cámara. Actívalo para que Riqsi pueda ver "
        "tu entorno.");
    notifyListeners();
  }

  /// La cámara o el modelo fallaron.
  void reportCameraError([String? detail]) {
    if (detail != null) debugPrint("[APP] Error de cámara: $detail");
    if (isCameraError) return;
    isCameraError = true;
    speak("Problema con la cámara o el modelo de detección.");
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _splashTimer?.cancel();
    _autoClearTimer?.cancel();
    _vibrationRepository.dispose();
    _ttsRepository.stop();
    super.dispose();
  }

  // ==========================================
  // MÉTODOS DE NAVEGACIÓN Y MAPA ASISTIDO
  // ==========================================

  void _initNavigation() {
    currentNavStep = const NavigationStep(
      id: 'init_step',
      direction: NavDirection.straight,
      instruction: 'Avanza en línea recta por la acera.',
      distanceMeters: 25,
      streetName: 'Ruta peatonal',
      warning: 'Camino despejado con línea podotáctil.',
    );
  }

  void setNavDirection(
    NavDirection direction, {
    String? customInstruction,
    int? distanceMeters,
    String? streetName,
  }) {
    final dist = distanceMeters ?? (currentNavStep?.distanceMeters ?? 20);
    final street = streetName ?? (currentNavStep?.streetName ?? "Ruta accesible");
    String inst = customInstruction ?? "";

    if (inst.isEmpty) {
      switch (direction) {
        case NavDirection.straight:
          inst = "Continúa de frente. Camino despejado.";
          break;
        case NavDirection.right:
          inst = "Gira a la derecha en la próxima esquina.";
          break;
        case NavDirection.left:
          inst = "Gira a la izquierda con precaución.";
          break;
        case NavDirection.back:
          inst = "Da media vuelta. Ve hacia atrás para retomar la orientación correcta.";
          break;
        case NavDirection.arrived:
          inst = "¡Has llegado a tu destino!";
          break;
      }
    }

    currentNavStep = NavigationStep(
      id: "step_${DateTime.now().millisecondsSinceEpoch}",
      direction: direction,
      instruction: inst,
      distanceMeters: dist,
      streetName: street,
    );

    // Audio-guía automática por voz
    speak(currentNavStep!.spokenText);

    // Patrón háptico sensorial diferenciado
    _triggerDirectionVibration(direction);

    notifyListeners();
  }

  void _triggerDirectionVibration(NavDirection dir) {
    if (!vibrationEnabled) return;
    switch (dir) {
      case NavDirection.straight:
        vibrate(120); // 1 pulso continuo suave
        break;
      case NavDirection.right:
        vibrate(80);
        Future.delayed(const Duration(milliseconds: 140), () => vibrate(120)); // 2 pulsos hacia la derecha
        break;
      case NavDirection.left:
        vibrate(80);
        Future.delayed(const Duration(milliseconds: 120), () {
          vibrate(80);
          Future.delayed(const Duration(milliseconds: 120), () => vibrate(80)); // 3 pulsos hacia la izquierda
        });
        break;
      case NavDirection.back:
        vibrate(400); // 1 pulso largo de retorno / alerta
        break;
      case NavDirection.arrived:
        vibrate(150);
        Future.delayed(const Duration(milliseconds: 200), () => vibrate(250));
        break;
    }
  }

  Future<void> startNavigation(String destination) async {
    isNavigating = true;
    activeDestination = destination;
    speak("Iniciando navegación accesible hacia $destination.");
    vibrate(60);
    notifyListeners();

    try {
      final steps = await _navigationRepository.getRoute(destination: destination);
      if (steps.isNotEmpty) {
        currentRouteSteps = steps;
        currentStepIndex = 0;
        currentNavStep = steps[0];
        speak("Ruta calculada. ${currentNavStep!.spokenText}");
        _triggerDirectionVibration(currentNavStep!.direction);
      }
    } catch (_) {
      speak("Modo de navegación local activo para $destination.");
    }

    notifyListeners();
  }

  void nextNavStep() {
    if (currentRouteSteps.isNotEmpty && currentStepIndex < currentRouteSteps.length - 1) {
      currentStepIndex++;
      currentNavStep = currentRouteSteps[currentStepIndex];
      speak("Siguiente indicación: ${currentNavStep!.spokenText}");
      _triggerDirectionVibration(currentNavStep!.direction);
      notifyListeners();
    } else if (currentRouteSteps.isNotEmpty && currentStepIndex == currentRouteSteps.length - 1) {
      speak("Has completado todos los pasos de la ruta hacia $activeDestination.");
      vibrate(200);
    }
  }

  void previousNavStep() {
    if (currentRouteSteps.isNotEmpty && currentStepIndex > 0) {
      currentStepIndex--;
      currentNavStep = currentRouteSteps[currentStepIndex];
      speak("Paso anterior: ${currentNavStep!.spokenText}");
      _triggerDirectionVibration(currentNavStep!.direction);
      notifyListeners();
    }
  }

  void stopNavigation() {
    isNavigating = false;
    activeDestination = "";
    currentRouteSteps.clear();
    currentStepIndex = 0;
    speak("Navegación detenida.");
    vibrate(50);
    notifyListeners();
  }

  void repeatNavInstruction() {
    if (currentNavStep != null) {
      speak(currentNavStep!.spokenText);
      _triggerDirectionVibration(currentNavStep!.direction);
    }
  }

  void updateNavApiUrl(String url) {
    _navigationRepository.setApiUrl(url);
    speak("Enlace API de navegación configurado.");
    vibrate(30);
    notifyListeners();
  }

  Future<bool> testNavApiConnection() async {
    speak("Comprobando enlace con el API de navegación...");
    final ok = await _navigationRepository.verifyApiConnection();
    isNavApiConnected = ok;
    speak(ok
        ? "Enlace con el API de navegación verificado exitosamente."
        : "Servidor del API no disponible en este momento. Modo autónomo activo.");
    vibrate(ok ? 80 : 300);
    notifyListeners();
    return ok;
  }
}

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// Domain Entities
import '../features/assistant/domain/entities/detection_event.dart';
import '../features/assistant/domain/entities/vision_connection_event.dart';
import '../features/settings/domain/entities/app_settings.dart';
import '../features/map/domain/entities/navigation_step.dart';

// Domain Repositories
import '../features/assistant/domain/repositories/tts_repository.dart';
import '../features/assistant/domain/repositories/vibration_repository.dart';
import '../features/history/domain/repositories/history_repository.dart';
import '../features/settings/domain/repositories/settings_repository.dart';

// Data Layers
import '../features/assistant/data/datasources/websocket_datasource.dart';
import '../features/assistant/data/repositories/vision_repository_impl.dart';
import '../features/assistant/data/repositories/tts_repository_impl.dart';
import '../features/assistant/data/repositories/vibration_repository_impl.dart';
import '../features/history/data/repositories/history_repository_impl.dart';
import '../features/settings/data/repositories/settings_repository_impl.dart';
import '../features/map/data/repositories/navigation_repository_impl.dart';

// Domain Use Cases
import '../features/assistant/domain/usecases/toggle_assistance.dart';
import '../features/assistant/domain/usecases/stream_frame.dart';
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

/// Estado de la conexión con el servidor de visión.
enum ServerConnectionStatus {
  /// Asistencia detenida: no hay conexión ni se intenta.
  idle,

  /// Primer intento de conexión tras iniciar la asistencia.
  connecting,

  /// Canal abierto.
  connected,

  /// Conexión perdida; reintentando con backoff.
  reconnecting,
}

class AppState extends ChangeNotifier {
  // Tiempos (ajustables en tests)
  static const Duration watchdogTimeout = Duration(seconds: 5);
  static const Duration highRiskRepeatInterval = Duration(seconds: 4);

  /// Mientras un frame no tenga respuesta, no se envía otro antes de este
  /// intervalo (el servidor procesa solo el último: no tiene sentido
  /// acumular frames en el socket).
  static const Duration unansweredFrameInterval = Duration(milliseconds: 700);
  static const int maxHistoryEntries = HistoryRepository.maxEntries;

  // Infrastructure references
  late final WebSocketDataSource _webSocketDataSource;
  late final VisionRepositoryImpl _visionRepository;
  late final TtsRepository _ttsRepository;
  late final VibrationRepository _vibrationRepository;
  late final HistoryRepository _historyRepository;
  late final SettingsRepository _settingsRepository;
  late final NavigationRepositoryImpl _navigationRepository;

  // Use case references
  late final ToggleAssistance _toggleAssistance;
  late final StreamFrame _streamFrame;
  late final SpeakText _speakText;
  late final VibrateDevice _vibrateDevice;
  late final GetHistory _getHistory;
  late final AddHistory _addHistory;
  late final GetSettings _getSettings;
  late final SaveSettings _saveSettings;

  // Presentation State
  AppScreen currentScreen = AppScreen.splash;
  int currentTab = 0; // 0: Inicio, 1: Historial, 2: Perfil

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

  // Conexión con el servidor de visión
  ServerConnectionStatus connectionStatus = ServerConnectionStatus.idle;
  bool _simulatedOffline = false;
  bool _connectionLostAnnounced = false;
  int _reconnectAttempt = 0;
  bool _frameInFlight = false;
  DateTime? _awaitingReplySince;
  DateTime? _lastFrameSentAt;

  // Anti-repetición de alertas de riesgo Alto cuando announce_voice=false
  String? _lastHighRiskKey;
  DateTime? _lastHighRiskSpokenAt;

  // Timers y suscripciones (todos cancelables en dispose)
  Timer? _splashTimer;
  Timer? _autoClearTimer;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  StreamSubscription<DetectionEvent>? _detectionSubscription;
  StreamSubscription<VisionConnectionEvent>? _connectionSubscription;
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
  String get userName => _settings?.userName ?? 'María González';
  String get serverIp => _settings?.serverIp ?? '10.247.64.45';

  /// Historial (más reciente primero, máx. 100). Vista de solo lectura, sin
  /// copiar la lista en cada evento.
  List<DetectionEvent> get history => UnmodifiableListView(_cachedHistory);
  String get navigationApiUrl => _navigationRepository.getApiUrl();

  /// true salvo que la conexión con el servidor esté caída (reconectando).
  bool get isConnected =>
      !_simulatedOffline &&
      connectionStatus != ServerConnectionStatus.reconnecting;

  bool get isReconnecting =>
      connectionStatus == ServerConnectionStatus.reconnecting;

  /// true cuando la cámara debe capturar y enviar un frame ahora.
  bool get canStreamFrames {
    if (assistanceState == AssistanceState.inactive ||
        connectionStatus != ServerConnectionStatus.connected ||
        _simulatedOffline ||
        _frameInFlight) {
      return false;
    }
    final last = _lastFrameSentAt;
    if (_awaitingReplySince != null &&
        last != null &&
        DateTime.now().difference(last) < unansweredFrameInterval) {
      return false; // aún esperando respuesta al frame anterior
    }
    return true;
  }

  bool get onboardingSeen => _onboardingSeen;

  /// Volumen usado para alertas de peligro: nunca silencio, aunque el
  /// usuario haya silenciado la voz.
  double get alertVolume => volume <= 0.01 ? 1.0 : math.max(volume, 0.6);

  AppState({
    WebSocketDataSource? webSocketDataSource,
    TtsRepository? ttsRepository,
    VibrationRepository? vibrationRepository,
    HistoryRepository? historyRepository,
    SettingsRepository? settingsRepository,
    NavigationRepositoryImpl? navigationRepository,
    Duration splashDuration = const Duration(seconds: 3),
  }) {
    // DI setup
    _webSocketDataSource = webSocketDataSource ?? WebSocketDataSource();
    _visionRepository = VisionRepositoryImpl(_webSocketDataSource);
    _ttsRepository = ttsRepository ?? TtsRepositoryImpl();
    _vibrationRepository = vibrationRepository ?? VibrationRepositoryImpl();
    _historyRepository = historyRepository ?? HistoryRepositoryImpl();
    _settingsRepository = settingsRepository ?? SettingsRepositoryImpl();
    _navigationRepository = navigationRepository ?? NavigationRepositoryImpl();

    _toggleAssistance = ToggleAssistance(_visionRepository);
    _streamFrame = StreamFrame(_visionRepository);
    _speakText = SpeakText(_ttsRepository);
    _vibrateDevice = VibrateDevice(_vibrationRepository);
    _getHistory = GetHistory(_historyRepository);
    _addHistory = AddHistory(_historyRepository);
    _getSettings = GetSettings(_settingsRepository);
    _saveSettings = SaveSettings(_settingsRepository);

    // Una sola suscripción para toda la vida de AppState: no hay carreras
    // entre conexiones (los eventos de canales viejos ya los filtra el
    // datasource y aquí se ignoran si la asistencia está detenida).
    _detectionSubscription =
        _visionRepository.detections.listen(_handleDetectionEvent);
    _connectionSubscription =
        _visionRepository.connectionEvents.listen(_handleConnectionEvent);

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
    if (screen == AppScreen.mainLayout && !_onboardingSeen) {
      // Llegar a la pantalla principal marca el onboarding como visto.
      completeOnboarding();
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

  void updateUserName(String val) {
    _updateSettings(_currentSettings.copyWith(userName: val));
  }

  /// Valida una dirección de servidor (IPv4 o nombre de equipo, sin esquema
  /// ni puerto). Devuelve null si es válida o un mensaje de error en español.
  static String? validateServerAddress(String raw) {
    final v = raw.trim();
    if (v.isEmpty) {
      return 'La dirección del servidor no puede estar vacía.';
    }
    if (v.length > 253) {
      return 'La dirección del servidor es demasiado larga.';
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(v)) {
      final parts = v.split('.');
      final ok = parts.length == 4 &&
          parts.every((p) =>
              p.isNotEmpty && p.length <= 3 && int.parse(p) <= 255);
      return ok
          ? null
          : 'La dirección IP no es válida. Usa el formato 192.168.1.15.';
    }
    final label = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');
    if (v.split('.').every(label.hasMatch)) return null;
    return 'La dirección no es válida. Escribe una IP como 192.168.1.15 '
        'o un nombre de equipo, sin http ni puerto.';
  }

  /// Cambia la dirección del servidor. Devuelve null si se aplicó o el
  /// mensaje de error (también se anuncia por voz) si no es válida.
  /// Si la asistencia está activa, reconecta con la nueva dirección.
  String? updateServerIp(String val) {
    final error = validateServerAddress(val);
    if (error != null) {
      speak(error);
      return error;
    }
    final host = val.trim();
    _updateSettings(_currentSettings.copyWith(serverIp: host));
    speak("Servidor configurado en la dirección $host");

    if (assistanceState != AssistanceState.inactive) {
      _reconnectAttempt = 0;
      _awaitingReplySince = null;
      if (connectionStatus == ServerConnectionStatus.connected) {
        connectionStatus = ServerConnectionStatus.connecting;
      }
      _openConnection();
    }
    notifyListeners();
    return null;
  }

  // ==========================================
  // FRAMES Y VOZ
  // ==========================================

  /// Envía un frame al servidor. No acumula: si el anterior aún no terminó
  /// de entregarse, o no hay conexión, devuelve false sin enviar.
  Future<bool> sendFrameBytes(List<int> bytes) async {
    if (!canStreamFrames) return false;
    _frameInFlight = true;
    try {
      final sent = await _streamFrame.execute(bytes);
      if (sent) {
        final now = DateTime.now();
        _lastFrameSentAt = now;
        _awaitingReplySince ??= now;
      }
      return sent;
    } catch (err) {
      debugPrint("[APP] Error enviando frame: $err");
      return false;
    } finally {
      _frameInFlight = false;
    }
  }

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
  // ASISTENCIA Y CONEXIÓN
  // ==========================================

  void toggleAssistance() {
    if (assistanceState == AssistanceState.inactive) {
      assistanceState = AssistanceState.analyzing;
      currentStatusMessage = "Analizando entorno...";
      connectionStatus = ServerConnectionStatus.connecting;
      _connectionLostAnnounced = false;
      _reconnectAttempt = 0;
      _awaitingReplySince = null;
      speak("Asistencia iniciada. Conectando al servidor de visión.");
      vibrate(150);
      _startWatchdog();
      _openConnection();
    } else {
      _closeConnection();
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

  void toggleImmersiveMode() {
    isImmersiveMode = !isImmersiveMode;
    if (isImmersiveMode) {
      speak("Modo inmersivo activado. Pantalla completa.");
      vibrate(80);
    } else {
      speak("Modo inmersivo desactivado. Regresando a vista estándar.");
      vibrate(60);
    }
    notifyListeners();
  }

  void setImmersiveMode(bool value) {
    if (isImmersiveMode != value) {
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
  }

  /// Retardo de reconexión: 1, 2, 4, 8 s y luego 10 s como máximo.
  static Duration reconnectDelayFor(int attempt) {
    const steps = [1, 2, 4, 8];
    final seconds = attempt < steps.length ? steps[attempt] : 10;
    return Duration(seconds: seconds);
  }

  void _openConnection() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _toggleAssistance.connect(serverIp).catchError((Object err) {
      debugPrint("[APP] Error conectando al servidor: $err");
      _handleConnectionLost();
    });
  }

  void _closeConnection() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _awaitingReplySince = null;
    _connectionLostAnnounced = false;
    _reconnectAttempt = 0;
    connectionStatus = ServerConnectionStatus.idle;
    _toggleAssistance.disconnect();
  }

  void _handleConnectionEvent(VisionConnectionEvent event) {
    if (assistanceState == AssistanceState.inactive) return;
    if (event.isConnected) {
      debugPrint("[APP] Conectado al servidor de visión");
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectAttempt = 0;
      _awaitingReplySince = null;
      connectionStatus = ServerConnectionStatus.connected;
      if (_connectionLostAnnounced) {
        _connectionLostAnnounced = false;
        currentStatusMessage = "Analizando entorno...";
        speak("Conexión recuperada.");
        vibrate(100);
      }
      notifyListeners();
    } else {
      debugPrint("[APP] Conexión cerrada: ${event.error ?? 'cierre limpio'}");
      _handleConnectionLost();
    }
  }

  void _handleConnectionLost() {
    if (assistanceState == AssistanceState.inactive) return;
    connectionStatus = ServerConnectionStatus.reconnecting;
    _awaitingReplySince = null;
    _vibrationRepository.stop(); // la proximidad anterior ya no es fiable
    currentStatusMessage = "Sin conexión. Reconectando...";
    if (!_connectionLostAnnounced) {
      // Se anuncia una sola vez por caída, no en cada reintento.
      _connectionLostAnnounced = true;
      speakAlert("Sin conexión con el servidor. Intentando reconectar.");
      vibrate(400);
    }
    _scheduleReconnect();
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    final delay = reconnectDelayFor(_reconnectAttempt);
    _reconnectAttempt++;
    debugPrint("[APP] Reintento de conexión en ${delay.inSeconds} s");
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_disposed || assistanceState == AssistanceState.inactive) return;
      _openConnection();
    });
  }

  /// Watchdog: si se enviaron frames y el servidor no responde nada en
  /// [watchdogTimeout], se da la conexión por perdida. (Se mide desde el
  /// primer frame sin respuesta, para no dar falsos positivos cuando la
  /// cámara no está enviando; los sockets muertos sin tráfico los detecta
  /// el ping del canal.)
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      checkWatchdog();
    });
  }

  @visibleForTesting
  void checkWatchdog([DateTime? now]) {
    if (assistanceState == AssistanceState.inactive ||
        connectionStatus != ServerConnectionStatus.connected) {
      return;
    }
    final since = _awaitingReplySince;
    if (since == null) return;
    if ((now ?? DateTime.now()).difference(since) >= watchdogTimeout) {
      debugPrint("[APP] Watchdog: el servidor no responde");
      _toggleAssistance.disconnect();
      _handleConnectionLost();
    }
  }

  void _handleDetectionEvent(DetectionEvent event) {
    if (assistanceState == AssistanceState.inactive) return;
    _awaitingReplySince = null; // el servidor está vivo

    if (vibrationEnabled) {
      _vibrationRepository.triggerProximityFeedback(event.distancia);
    } else {
      _vibrationRepository.stop();
    }

    // 'clear' solo sirve para frenar la vibración: no cambia la pantalla
    // ni se guarda en el historial.
    if (event.isClear) return;

    if (event.isHighRisk) {
      triggerHighRiskAlert(event);
    } else {
      triggerObjectDetection(event);
    }
  }

  void triggerObjectDetection(DetectionEvent event) {
    assistanceState = AssistanceState.objectDetected;
    currentStatusMessage = "${event.label} detectado";
    activeDetection = event;

    // Solo hablar (y guardar) si el servidor indicó anunciar voz
    if (event.announceVoice && event.description.isNotEmpty) {
      speak(event.description);
      _recordHistory(event);
    }

    _scheduleAutoClear(event, const Duration(seconds: 4));
    notifyListeners();
  }

  void triggerHighRiskAlert(DetectionEvent event) {
    assistanceState = AssistanceState.riskDetected;
    currentStatusMessage = "¡Cuidado! Peligro detectado";
    activeDetection = event;

    if (_shouldAnnounceHighRisk(event)) {
      final text = event.description.isNotEmpty
          ? event.description
          : "¡Cuidado! ${event.label} ${event.relativePosition}".trim();
      speakAlert(text);
      _recordHistory(event);
    }

    _scheduleAutoClear(event, const Duration(milliseconds: 4500));
    notifyListeners();
  }

  /// El riesgo Alto siempre se anuncia aunque announce_voice sea false
  /// (el cooldown del servidor es para Medio/Bajo). Para no repetir la
  /// misma alerta en cada frame, se limita localmente a una vez cada
  /// [highRiskRepeatInterval] por objeto/posición.
  bool _shouldAnnounceHighRisk(DetectionEvent event, [DateTime? now]) {
    final t = now ?? DateTime.now();
    final key = "${event.label}|${event.relativePosition}";
    final last = _lastHighRiskSpokenAt;
    final repeated = key == _lastHighRiskKey &&
        last != null &&
        t.difference(last) < highRiskRepeatInterval;
    if (repeated && !event.announceVoice) return false;
    _lastHighRiskKey = key;
    _lastHighRiskSpokenAt = t;
    return true;
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
  void _scheduleAutoClear(DetectionEvent event, Duration after) {
    _autoClearTimer?.cancel();
    _autoClearTimer = Timer(after, () {
      if (activeDetection?.id != event.id) return;
      if (assistanceState == AssistanceState.objectDetected ||
          assistanceState == AssistanceState.riskDetected) {
        assistanceState = AssistanceState.analyzing;
        currentStatusMessage = isReconnecting
            ? "Sin conexión. Reconectando..."
            : "Analizando entorno...";
        activeDetection = null;
        notifyListeners();
      }
    });
  }

  void dismissAlert() {
    _autoClearTimer?.cancel();
    activeDetection = null;
    if (assistanceState == AssistanceState.inactive) {
      notifyListeners();
      return;
    }
    assistanceState = AssistanceState.analyzing;
    currentStatusMessage = "Analizando entorno...";
    speak("Alerta entendida. Reanudando asistencia.");
    vibrate(100);

    if (isReconnecting) {
      // Reintento inmediato en lugar de esperar al backoff.
      _reconnectAttempt = 0;
      _openConnection();
    }
    notifyListeners();
  }

  // ==========================================
  // CÁMARA
  // ==========================================

  /// La cámara se inicializó correctamente.
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
    speak("No hay permiso de cámara. Actívalo en los ajustes del teléfono "
        "para que Riqsi pueda ver tu entorno.");
    notifyListeners();
  }

  /// La cámara falló (inicialización o capturas seguidas).
  void reportCameraError([String? detail]) {
    if (detail != null) debugPrint("[APP] Error de cámara: $detail");
    if (isCameraError) return;
    isCameraError = true;
    speak("Problema con la cámara. Reintentando.");
    notifyListeners();
  }

  void simulateCameraError() {
    isCameraError = !isCameraError;
    notifyListeners();
  }

  void simulateOffline() {
    _simulatedOffline = !_simulatedOffline;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _splashTimer?.cancel();
    _autoClearTimer?.cancel();
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _detectionSubscription?.cancel();
    _connectionSubscription?.cancel();
    _vibrationRepository.dispose();
    _ttsRepository.stop();
    _visionRepository.dispose();
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

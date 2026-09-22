import 'package:flutter/material.dart';
import 'dart:async';

// Domain Entities
import '../features/assistant/domain/entities/detection_event.dart';
import '../features/settings/domain/entities/app_settings.dart';

// Data Layers
import '../features/assistant/data/datasources/websocket_datasource.dart';
import '../features/assistant/data/repositories/vision_repository_impl.dart';
import '../features/assistant/data/repositories/tts_repository_impl.dart';
import '../features/assistant/data/repositories/vibration_repository_impl.dart';
import '../features/history/data/repositories/history_repository_impl.dart';
import '../features/settings/data/repositories/settings_repository_impl.dart';

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
export '../features/settings/domain/entities/app_settings.dart';

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
  // Infrastructure references
  late final WebSocketDataSource _webSocketDataSource;
  late final VisionRepositoryImpl _visionRepository;
  late final TtsRepositoryImpl _ttsRepository;
  late final VibrationRepositoryImpl _vibrationRepository;
  late final HistoryRepositoryImpl _historyRepository;
  late final SettingsRepositoryImpl _settingsRepository;

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
  List<DetectionEvent> _cachedHistory = [];
  StreamSubscription<DetectionEvent>? _detectionSubscription;
  
  AssistanceState assistanceState = AssistanceState.inactive;
  String currentStatusMessage = "Riqsi está listo";
  String lastSpokenDescription = "";
  
  bool hasCameraPermission = true;
  bool isCameraError = false;
  bool isConnected = true;
  DetectionEvent? activeDetection;

  // Exposing settings attributes via getters for UI backwards-compatibility
  double get voiceSpeed => _settings?.voiceSpeed ?? 1.0;
  double get volume => _settings?.volume ?? 0.8;
  bool get vibrationEnabled => _settings?.vibrationEnabled ?? true;
  String get alertFrequency => _settings?.alertFrequency ?? 'Alta';
  String get sensitivity => _settings?.sensitivity ?? 'Alta';
  String get language => _settings?.language ?? 'Español';
  String get userName => _settings?.userName ?? 'María González';
  String get serverIp => _settings?.serverIp ?? '192.168.0.3';
  List<DetectionEvent> get history => List.unmodifiable(_cachedHistory);

  AppState() {
    // DI setup
    _webSocketDataSource = WebSocketDataSource();
    _visionRepository = VisionRepositoryImpl(_webSocketDataSource);
    _ttsRepository = TtsRepositoryImpl();
    _vibrationRepository = VibrationRepositoryImpl();
    _historyRepository = HistoryRepositoryImpl();
    _settingsRepository = SettingsRepositoryImpl();

    _toggleAssistance = ToggleAssistance(_visionRepository);
    _streamFrame = StreamFrame(_visionRepository);
    _speakText = SpeakText(_ttsRepository);
    _vibrateDevice = VibrateDevice(_vibrationRepository);
    _getHistory = GetHistory(_historyRepository);
    _addHistory = AddHistory(_historyRepository);
    _getSettings = GetSettings(_settingsRepository);
    _saveSettings = SaveSettings(_settingsRepository);

    _init();

    // Start splash screen countdown
    Timer(const Duration(seconds: 3), () {
      navigateToScreen(AppScreen.onboarding);
    });
  }

  Future<void> _init() async {
    _settings = await _getSettings.execute();
    _cachedHistory = await _getHistory.execute();
    notifyListeners();
  }

  void navigateToScreen(AppScreen screen) {
    currentScreen = screen;
    notifyListeners();
  }

  void setTab(int index) {
    currentTab = index;
    notifyListeners();
  }

  // Settings update wrappers
  Future<void> _updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _saveSettings.execute(newSettings);
    notifyListeners();
  }

  void updateVoiceSpeed(double val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(voiceSpeed: val));
    }
  }

  void updateVolume(double val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(volume: val));
    }
  }

  void toggleVibration(bool val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(vibrationEnabled: val));
    }
  }

  void updateAlertFrequency(String val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(alertFrequency: val));
    }
  }

  void updateSensitivity(String val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(sensitivity: val));
    }
  }
  
  void updateUserName(String val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(userName: val));
    }
  }

  void updateServerIp(String val) {
    if (_settings != null) {
      _updateSettings(_settings!.copyWith(serverIp: val));
      speak("Servidor configurado en la dirección IP $val");
    }
  }

  void sendFrameBytes(List<int> bytes) {
    if (isConnected && assistanceState != AssistanceState.inactive) {
      _streamFrame.execute(bytes).catchError((err) {
        print("Error streaming frame: $err");
      });
    }
  }

  void speak(String text) {
    lastSpokenDescription = text;
    notifyListeners();
    _speakText.execute(text, voiceSpeed, volume);
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

  void toggleAssistance() {
    if (assistanceState == AssistanceState.inactive) {
      assistanceState = AssistanceState.analyzing;
      currentStatusMessage = "Analizando entorno...";
      speak("Asistencia iniciada. Conectando al servidor de visión.");
      vibrate(150);
      _connectWebSocket();
    } else {
      _disconnectWebSocket();
      _vibrationRepository.stop(); // Detener vibración en bucle
      assistanceState = AssistanceState.inactive;
      currentStatusMessage = "Riqsi está listo";
      activeDetection = null;
      speak("Asistencia detenida.");
      vibrate(100);
    }
    notifyListeners();
  }

  void _connectWebSocket() {
    _disconnectWebSocket();
    isConnected = true;
    notifyListeners();

    _toggleAssistance.connect(serverIp).then((_) {
      _detectionSubscription = _visionRepository.detections.listen(
        (event) {
          _handleDetectionEvent(event);
        },
        onError: (error) {
          print("WebSocket error: $error");
          _handleWsDisconnect(true);
        },
        onDone: () {
          print("WebSocket done");
          _handleWsDisconnect(false);
        },
      );
      print("WebSocket connected successfully");
    }).catchError((err) {
      print("WebSocket connect error: $err");
      _handleWsDisconnect(true);
    });
  }

  void _disconnectWebSocket() {
    _detectionSubscription?.cancel();
    _detectionSubscription = null;
    _toggleAssistance.disconnect();
  }

  void _handleWsDisconnect(bool isError) {
    _disconnectWebSocket();
    isConnected = false;
    
    if (assistanceState != AssistanceState.inactive) {
      currentStatusMessage = isError ? "Servidor sin conexión" : "Servidor desconectado";
      speak(isError ? "Conexión con el servidor de visión perdida." : "Servidor de visión desconectado.");
      notifyListeners();
    }
  }

  void _handleDetectionEvent(DetectionEvent event) {
    isConnected = true;

    if (vibrationEnabled) {
      _vibrationRepository.triggerProximityFeedback(event.distancia);
    } else {
      _vibrationRepository.stop();
    }

    if (event.riskLevel == "Alto") {
      triggerHighRiskAlert(event);
    } else {
      triggerObjectDetection(event);
    }
  }

  void triggerObjectDetection(DetectionEvent event) {
    assistanceState = AssistanceState.objectDetected;
    currentStatusMessage = "${event.label} detectado";
    activeDetection = event;

    _addHistory.execute(event).then((_) => _refreshHistory());

    // Solo hablar si detector.py indicó anunciar voz
    if (event.announceVoice && event.description.isNotEmpty) {
      speak(event.description);
    }

    Timer(const Duration(seconds: 4), () {
      if (assistanceState == AssistanceState.objectDetected && activeDetection?.id == event.id) {
        assistanceState = AssistanceState.analyzing;
        currentStatusMessage = "Analizando entorno...";
        activeDetection = null;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void triggerHighRiskAlert(DetectionEvent event) {
    assistanceState = AssistanceState.riskDetected;
    currentStatusMessage = "¡Cuidado! Peligro detectado";
    activeDetection = event;

    _addHistory.execute(event).then((_) => _refreshHistory());

    // Solo hablar si detector.py indicó anunciar voz
    if (event.announceVoice && event.description.isNotEmpty) {
      speak(event.description);
    }

    notifyListeners();

    Timer(const Duration(milliseconds: 4500), () {
      if (assistanceState == AssistanceState.riskDetected && activeDetection?.id == event.id) {
        assistanceState = AssistanceState.analyzing;
        currentStatusMessage = "Analizando entorno...";
        activeDetection = null;
        notifyListeners();
      }
    });
  }

  Future<void> _refreshHistory() async {
    _cachedHistory = await _getHistory.execute();
    notifyListeners();
  }

  void dismissAlert() {
    assistanceState = AssistanceState.analyzing;
    currentStatusMessage = "Analizando entorno...";
    activeDetection = null;
    speak("Alerta entendida. Reanudando asistencia.");
    vibrate(100);
    
    if (!isConnected) {
      _connectWebSocket();
    }
    notifyListeners();
  }

  void simulateCameraError() {
    isCameraError = !isCameraError;
    notifyListeners();
  }

  void simulateOffline() {
    isConnected = !isConnected;
    notifyListeners();
  }
}

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

class CameraSimulator extends StatefulWidget {
  final AppState state;
  final bool isUltraWide;

  const CameraSimulator({
    super.key,
    required this.state,
    this.isUltraWide = true,
  });

  @override
  State<CameraSimulator> createState() => _CameraSimulatorState();
}

class _CameraSimulatorState extends State<CameraSimulator>
    with WidgetsBindingObserver {
  /// Capturas fallidas seguidas antes de reiniciar la cámara.
  static const int _maxConsecutiveCaptureFailures = 5;

  /// Ritmo máximo de envío (el servidor procesa solo el último frame).
  static const Duration _minFrameInterval = Duration(milliseconds: 150);
  static const Duration _idlePoll = Duration(milliseconds: 150);

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _ultraWideCamera;
  CameraDescription? _mainCamera;
  CameraDescription? _activeCamera;
  bool _isCameraInitialized = false;
  bool _isLoopRunning = false;
  bool _disposed = false;
  bool _paused = false;
  bool _permissionDenied = false;
  bool _cameraFailed = false;
  bool _initializing = false;
  bool _pausedDuringInit = false;
  int _consecutiveCaptureFailures = 0;

  /// Cola que serializa todas las operaciones sobre la cámara (init,
  /// cambio de lente, liberar): nunca hay dos initialize() concurrentes.
  Future<void> _cameraOps = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enqueue(_initializeCameras);
  }

  @override
  void didUpdateWidget(CameraSimulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isUltraWide != widget.isUltraWide && _cameras != null) {
      final target = widget.isUltraWide ? _ultraWideCamera : _mainCamera;
      if (target != null && target != _activeCamera) {
        _enqueue(() => _applyCamera(target));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_paused) return;
        _paused = true;
        // Un diálogo de permisos pausa la app mientras inicializamos.
        _pausedDuringInit = _initializing;
        _enqueue(_releaseCamera);
        break;
      case AppLifecycleState.resumed:
        if (!_paused) return;
        _paused = false;
        _enqueue(() async {
          final skip = _pausedDuringInit && _permissionDenied;
          _pausedDuringInit = false;
          // Si el usuario acaba de denegar el permiso en el diálogo, no se
          // vuelve a pedir enseguida (sí al volver desde los ajustes).
          if (skip) return;
          final camera = _activeCamera;
          if (camera == null) {
            await _initializeCameras();
          } else {
            await _applyCamera(camera);
          }
        });
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Encola una operación de cámara; los errores se capturan aquí para que
  /// la cola nunca se rompa (también los de didUpdateWidget).
  void _enqueue(Future<void> Function() op) {
    _cameraOps = _cameraOps.then((_) async {
      if (_disposed) return;
      try {
        await op();
      } catch (e) {
        _handleCameraError(e);
      }
    });
  }

  Future<void> _initializeCameras() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('NoCamera', 'No se encontró ninguna cámara');
    }
    _cameras = cameras;
    final backCameras = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList();

    for (final cam in cameras) {
      debugPrint("[CAMERA] Dispositivo: id=${cam.name}, facing=${cam.lensDirection}");
    }

    CameraDescription? byIds(List<String> ids) =>
        backCameras.where((c) => ids.contains(c.name)).firstOrNull;
    final defaultBack =
        backCameras.isNotEmpty ? backCameras.first : cameras.first;

    // IDs conocidos del Samsung Galaxy A33 5G: ultra gran angular (2 o 58) y
    // principal (0 o 23). En otros equipos se usa la cámara trasera por
    // defecto.
    _ultraWideCamera = byIds(const ['2', '58']) ?? defaultBack;
    _mainCamera = byIds(const ['0', '23']) ?? defaultBack;

    debugPrint("[CAMERA] Configurado Ultra-Wide: ${_ultraWideCamera?.name}, Principal: ${_mainCamera?.name}");

    final target = widget.isUltraWide ? _ultraWideCamera : _mainCamera;
    await _applyCamera(target ?? defaultBack);
  }

  Future<void> _releaseCamera() async {
    final old = _cameraController;
    _cameraController = null;
    if (mounted && _isCameraInitialized) {
      setState(() => _isCameraInitialized = false);
    } else {
      _isCameraInitialized = false;
    }
    if (old != null) {
      try {
        await old.dispose();
      } catch (e) {
        debugPrint("[CAMERA] Error liberando cámara: $e");
      }
    }
  }

  Future<void> _applyCamera(CameraDescription camera) async {
    await _releaseCamera();
    _activeCamera = camera;
    if (_disposed || _paused) return;

    debugPrint("[CAMERA] Inicializando sensor cámara ID: ${camera.name}...");
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializing = true;
    try {
      await controller.initialize();
    } catch (e) {
      try {
        await controller.dispose();
      } catch (_) {}
      rethrow;
    } finally {
      _initializing = false;
    }

    // Configurar zoom mínimo nativo para asegurar la máxima amplitud angular
    try {
      final double minZoom = await controller.getMinZoomLevel();
      final double maxZoom = await controller.getMaxZoomLevel();
      debugPrint("[CAMERA ${camera.name}] Zoom soportado: min=$minZoom, max=$maxZoom");
      await controller.setZoomLevel(minZoom);
    } catch (ze) {
      debugPrint("[CAMERA ${camera.name}] Zoom note: $ze");
    }

    // Si mientras inicializaba se desmontó o la app pasó a segundo plano,
    // se libera este controller en lugar de perderlo.
    if (_disposed || _paused) {
      await controller.dispose();
      return;
    }

    _cameraController = controller;
    _consecutiveCaptureFailures = 0;
    _permissionDenied = false;
    _cameraFailed = false;
    widget.state.reportCameraReady();
    if (mounted) {
      setState(() => _isCameraInitialized = true);
    }
    _ensureTransmissionLoop();
  }

  static bool _isPermissionError(CameraException e) {
    final code = e.code.toLowerCase();
    return code.contains('accessdenied') ||
        code.contains('accessrestricted') ||
        (code.contains('permission') && !code.contains('ongoing'));
  }

  void _handleCameraError(Object e) {
    debugPrint("[CAMERA] Error: $e");
    if (_disposed) return;
    if (e is CameraException && _isPermissionError(e)) {
      _permissionDenied = true;
      widget.state.reportCameraPermissionDenied();
    } else {
      _cameraFailed = true;
      widget.state.reportCameraError('$e');
    }
    if (mounted) setState(() {});
  }

  /// Arranca el bucle de captura si no hay uno corriendo. Se llama desde el
  /// ciclo de vida de la cámara (nunca desde build), así solo existe uno.
  void _ensureTransmissionLoop() {
    if (_isLoopRunning || _disposed || _paused) return;
    _isLoopRunning = true;
    _transmissionLoop();
  }

  Future<void> _transmissionLoop() async {
    try {
      while (mounted && !_disposed && !_paused) {
        final controller = _cameraController;
        if (!widget.state.canStreamFrames ||
            controller == null ||
            !controller.value.isInitialized ||
            controller.value.isTakingPicture) {
          await Future.delayed(_idlePoll);
          continue;
        }

        final started = DateTime.now();
        try {
          final XFile file = await controller.takePicture();
          final Uint8List bytes = await file.readAsBytes();
          File(file.path).delete().ignore();
          _consecutiveCaptureFailures = 0;
          // Espera a que el frame se entregue antes de capturar otro.
          await widget.state.sendFrameBytes(bytes);
        } catch (e) {
          // El controller cambió (lente/pausa) mientras capturábamos.
          if (!identical(controller, _cameraController)) continue;
          _consecutiveCaptureFailures++;
          debugPrint("[CAMERA] Fallo de captura ($_consecutiveCaptureFailures): $e");
          if (_consecutiveCaptureFailures >= _maxConsecutiveCaptureFailures) {
            _consecutiveCaptureFailures = 0;
            widget.state.reportCameraError('takePicture: $e');
            final camera = _activeCamera;
            if (camera != null) _enqueue(() => _applyCamera(camera));
            await Future.delayed(const Duration(seconds: 1));
          } else {
            await Future.delayed(const Duration(milliseconds: 100));
          }
          continue;
        }

        final elapsed = DateTime.now().difference(started);
        if (elapsed < _minFrameInterval) {
          await Future.delayed(_minFrameInterval - elapsed);
        }
      }
    } finally {
      _isLoopRunning = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _cameraController;
    _cameraController = null;
    // Espera a cualquier operación en curso antes de liberar.
    _cameraOps.whenComplete(() => controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.state.assistanceState;
    final isScanning = status != AssistanceState.inactive;
    final controller = _cameraController;
    final previewSize = controller?.value.previewSize;

    Widget cameraContent;
    if (_isCameraInitialized &&
        controller != null &&
        controller.value.isInitialized &&
        previewSize != null) {
      cameraContent = ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      );
    } else if (_permissionDenied || !widget.state.hasCameraPermission) {
      cameraContent = _buildCameraMessage(
        icon: Icons.no_photography_rounded,
        text: "Sin permiso de cámara.\nActívalo en los ajustes del teléfono.",
      );
    } else if (_cameraFailed || widget.state.isCameraError) {
      cameraContent = _buildCameraMessage(
        icon: Icons.videocam_off_rounded,
        text: "La cámara no está disponible.\nReintentando…",
      );
    } else {
      cameraContent = _buildCameraMessage(
        showSpinner: true,
        text: "Iniciando cámara…",
      );
    }

    // Modo inmersivo permanente a pantalla completa
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          cameraContent,
          if (isScanning && widget.state.isConnected)
            _buildBoundingBoxes(),
        ],
      ),
    );
  }

  Widget _buildCameraMessage({
    IconData? icon,
    bool showSpinner = false,
    required String text,
  }) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const CircularProgressIndicator(color: RiqsiTheme.accentCyan)
              else if (icon != null)
                Icon(icon, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoundingBoxes() {
    final activeDetection = widget.state.activeDetection;
    if (activeDetection == null || activeDetection.objects.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: activeDetection.objects.map((obj) {
            double left = 0;
            double top = 0;
            double width = 0;
            double height = 0;

            if (obj.boxNorm.length == 4) {
              left = (obj.boxNorm[0] * w).clamp(0.0, w);
              top = (obj.boxNorm[1] * h).clamp(0.0, h);
              width = ((obj.boxNorm[2] - obj.boxNorm[0]) * w).clamp(24.0, w - left);
              height = ((obj.boxNorm[3] - obj.boxNorm[1]) * h).clamp(24.0, h - top);
            } else if (obj.box.length == 4) {
              left = obj.box[0].toDouble().clamp(0.0, w);
              top = obj.box[1].toDouble().clamp(0.0, h);
              width = (obj.box[2] - obj.box[0]).toDouble().clamp(24.0, w - left);
              height = (obj.box[3] - obj.box[1]).toDouble().clamp(24.0, h - top);
            } else {
              return const SizedBox.shrink();
            }

            final color = _getColorForObject(obj.label, obj.riskLevel);

            return Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Cuadro delimitador del objeto (Bounding Box)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: color, width: 2.5),
                      borderRadius: BorderRadius.circular(6),
                      color: color.withValues(alpha: 0.12),
                    ),
                  ),
                  // 2. Etiqueta con el nombre y distancia en la parte superior izquierda
                  Positioned(
                    left: -1,
                    top: -1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(5),
                          bottomRight: Radius.circular(8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 4,
                            offset: const Offset(1, 1),
                          )
                        ],
                      ),
                      child: Text(
                        obj.distancia.isNotEmpty
                            ? "${obj.label.toUpperCase()} • ${obj.distancia}"
                            : obj.label.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _getColorForObject(String label, String risk) {
    final l = label.toLowerCase();
    if (risk == "Alto" || l.contains("hueco") || l.contains("desnivel") || l.contains("pared") || l.contains("peligro")) {
      return const Color(0xFFFF2A2A); // Rojo peligro
    }
    if (l.contains("persona") || l.contains("peatón")) {
      return const Color(0xFFE040FB); // Magenta
    }
    if (l.contains("auto") || l.contains("camión") || l.contains("bus") || l.contains("moto") || l.contains("bicicleta")) {
      return const Color(0xFF00E676); // Verde
    }
    if (l.contains("perro") || l.contains("gato") || l.contains("animal")) {
      return const Color(0xFF00E5FF); // Celeste / Cyan
    }
    if (l.contains("semáforo") || l.contains("señal") || l.contains("escalón")) {
      return const Color(0xFFFFD600); // Amarillo brillante
    }
    return const Color(0xFF2979FF); // Azul
  }
}
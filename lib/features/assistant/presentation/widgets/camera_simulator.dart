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

class _CameraSimulatorState extends State<CameraSimulator> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _ultraWideCamera;
  CameraDescription? _mainCamera;
  CameraDescription? _activeCamera;
  bool _isCameraInitialized = false;
  bool _isLoopRunning = false;

  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }

  @override
  void didUpdateWidget(CameraSimulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isUltraWide != widget.isUltraWide && _cameras != null) {
      final target = widget.isUltraWide ? _ultraWideCamera : _mainCamera;
      if (target != null && target != _activeCamera) {
        _applyCamera(target);
      }
    }
  }

  Future<void> _initializeCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final backCameras = _cameras!
            .where((camera) => camera.lensDirection == CameraLensDirection.back)
            .toList();

        for (final cam in _cameras!) {
          debugPrint("[CAMERA] Dispositivo: id=${cam.name}, facing=${cam.lensDirection}");
        }

        // 1. Identificar lente Ultra-Wide (0.5x, 123° FOV, focal ~1.42mm)
        // En Samsung Galaxy A33 5G, Camera ID 2 o 58 corresponde al sensor ultra-gran angular.
        try {
          _ultraWideCamera = backCameras.firstWhere(
            (c) => c.name == '2' || c.name == '58',
          );
        } catch (_) {
          if (backCameras.length > 1) {
            _ultraWideCamera = backCameras[1];
          }
        }
        _ultraWideCamera ??= (backCameras.isNotEmpty ? backCameras.first : _cameras!.first);

        // 2. Identificar lente Principal (1.0x Wide, focal ~4.65mm)
        try {
          _mainCamera = backCameras.firstWhere(
            (c) => c.name == '0' || c.name == '23',
          );
        } catch (_) {
          _mainCamera = backCameras.isNotEmpty ? backCameras.first : _cameras!.first;
        }

        debugPrint("[CAMERA] Configurado Ultra-Wide: ${_ultraWideCamera?.name}, Principal: ${_mainCamera?.name}");

        final target = widget.isUltraWide ? _ultraWideCamera : _mainCamera;
        await _applyCamera(target ?? _cameras!.first);
      }
    } catch (e) {
      debugPrint("[CAMERA] Error de inicialización: $e");
    }
  }

  Future<void> _applyCamera(CameraDescription camera) async {
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }

    final oldController = _cameraController;
    _cameraController = null;
    await oldController?.dispose();

    _activeCamera = camera;
    debugPrint("[CAMERA] Inicializando sensor cámara ID: ${camera.name}...");

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _cameraController = controller;
    await controller.initialize();

    // Configurar zoom mínimo nativo para asegurar la máxima amplitud angular
    try {
      final double minZoom = await controller.getMinZoomLevel();
      final double maxZoom = await controller.getMaxZoomLevel();
      debugPrint("[CAMERA ${camera.name}] Zoom soportado: min=$minZoom, max=$maxZoom");
      await controller.setZoomLevel(minZoom);
    } catch (ze) {
      debugPrint("[CAMERA ${camera.name}] Zoom note: $ze");
    }

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  void _startFastTransmission() async {
    if (_isLoopRunning) return;
    _isLoopRunning = true;

    while (mounted && _isLoopRunning) {
      final status = widget.state.assistanceState;
      final isScanning = status != AssistanceState.inactive;

      if (!isScanning ||
          !widget.state.isConnected ||
          _cameraController == null ||
          !_cameraController!.value.isInitialized ||
          _cameraController!.value.isTakingPicture) {
        await Future.delayed(const Duration(milliseconds: 35));
        continue;
      }

      try {
        final XFile file = await _cameraController!.takePicture();
        final Uint8List bytes = await file.readAsBytes();
        File(file.path).delete().ignore();

        widget.state.sendFrameBytes(bytes);

        // Control de ritmo para evitar saturación del buffer en Android
        await Future.delayed(const Duration(milliseconds: 20));
      } catch (e) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    _isLoopRunning = false;
  }

  @override
  void dispose() {
    _isLoopRunning = false;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.state.assistanceState;
    final isScanning = status != AssistanceState.inactive;

    if (isScanning && widget.state.isConnected) {
      if (!_isLoopRunning && _isCameraInitialized) {
        _startFastTransmission();
      }
    } else {
      _isLoopRunning = false;
    }

    Widget cameraContent;
    if (_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      cameraContent = ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize!.height,
            height: _cameraController!.value.previewSize!.width,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    } else {
      cameraContent = Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: RiqsiTheme.accentCyan),
              SizedBox(height: 16),
              Text(
                "Iniciando cámara 0.5x...",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
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
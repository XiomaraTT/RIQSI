import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

class CameraSimulator extends StatefulWidget {
  final AppState state;
  const CameraSimulator({super.key, required this.state});

  @override
  State<CameraSimulator> createState() => _CameraSimulatorState();
}

class _CameraSimulatorState extends State<CameraSimulator> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isLoopRunning = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final backCameras = _cameras!
            .where((camera) => camera.lensDirection == CameraLensDirection.back)
            .toList();

        final selectedCamera = backCameras.isNotEmpty
            ? (backCameras.length > 1 ? backCameras[1] : backCameras.first)
            : _cameras!.first;

        // Resolución low para transferir paquetes ultra ligeros en red local
        _cameraController = CameraController(
          selectedCamera,
          ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        await _cameraController!.initialize();

        try {
          final double minZoom = await _cameraController!.getMinZoomLevel();
          await _cameraController!.setZoomLevel(minZoom);
        } catch (_) {}

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint("[CAMERA] Error de inicialización: $e");
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
    if (isScanning &&
        _isCameraInitialized &&
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
        color: const Color(0xFF121212),
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white24, size: 48),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: status == AssistanceState.riskDetected
                    ? RiqsiTheme.alertHigh
                    : (status == AssistanceState.objectDetected
                        ? RiqsiTheme.accentCyan
                        : RiqsiTheme.textSecondary.withOpacity(0.2)),
                width: 3,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                cameraContent,
                if (!isScanning)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Text(
                        "Asistencia Inactiva\nToca el botón abajo para iniciar",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
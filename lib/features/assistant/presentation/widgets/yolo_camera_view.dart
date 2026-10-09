import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../../../core/accessibility/a11y_tap.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import '../../domain/scene/scene_logic.dart';

/// Modelo de detección (YOLO11n, 80 clases COCO).
///
/// - Android: empaquetado como asset (funciona sin internet).
/// - iOS: paquete Core ML oficial, se descarga y cachea en el primer uso.
String get riqsiModelPath => defaultTargetPlatform == TargetPlatform.iOS
    ? 'https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo11n.mlpackage.zip'
    : 'assets/models/yolo11n.tflite';

/// Cámara a pantalla completa con detección YOLO en el propio celular.
///
/// Solo monta el [YOLOView] (cámara + inferencia) mientras la asistencia
/// está activa: al detenerla se desmonta y la inferencia se para.
class YoloCameraView extends StatefulWidget {
  final AppState state;
  final bool isUltraWide;

  const YoloCameraView({
    super.key,
    required this.state,
    this.isUltraWide = true,
  });

  @override
  State<YoloCameraView> createState() => _YoloCameraViewState();
}

enum _PermissionStatus { unknown, checking, granted, denied, permanentlyDenied }

class _YoloCameraViewState extends State<YoloCameraView>
    with WidgetsBindingObserver {
  final YOLOViewController _controller = YOLOViewController();
  _PermissionStatus _permission = _PermissionStatus.unknown;
  bool _modelFailed = false;

  bool get _active =>
      widget.state.assistanceState != AssistanceState.inactive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_active) _checkPermission();
  }

  @override
  void didUpdateWidget(YoloCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_active && _permission == _PermissionStatus.unknown) {
      _checkPermission();
    }
    if (!_active) _modelFailed = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Al volver de los ajustes del teléfono se revisa otra vez el permiso.
    if (lifecycle == AppLifecycleState.resumed &&
        (_permission == _PermissionStatus.denied ||
            _permission == _PermissionStatus.permanentlyDenied)) {
      _checkPermission(request: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkPermission({bool request = true}) async {
    // En iOS el propio plugin pide el permiso (Info.plist); permission_handler
    // necesitaría macros en el Podfile.
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _permission = _PermissionStatus.granted);
      return;
    }
    setState(() => _permission = _PermissionStatus.checking);
    PermissionStatus status;
    try {
      status = request
          ? await Permission.camera.request()
          : await Permission.camera.status;
    } catch (e) {
      debugPrint('[CAMERA] Error pidiendo permiso: $e');
      status = PermissionStatus.denied;
    }
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      setState(() => _permission = _PermissionStatus.granted);
      widget.state.reportCameraReady();
    } else {
      setState(() => _permission = status.isPermanentlyDenied
          ? _PermissionStatus.permanentlyDenied
          : _PermissionStatus.denied);
      widget.state.reportCameraPermissionDenied();
    }
  }

  void _onResult(List<YOLOResult> results) {
    if (!mounted || !_active) return;
    widget.state.onRawDetections([
      for (final r in results)
        RawDetection(
          className: r.className,
          confidence: r.confidence,
          left: r.normalizedBox.left,
          top: r.normalizedBox.top,
          right: r.normalizedBox.right,
          bottom: r.normalizedBox.bottom,
        ),
    ]);
  }

  /// Umbral del modelo según la sensibilidad elegida en el perfil.
  double get _confidenceThreshold {
    switch (widget.state.sensitivity) {
      case '90%':
        return 0.25;
      case '50%':
        return 0.5;
      default:
        return 0.35;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (!_active) {
      content = _message(
        icon: Icons.visibility_outlined,
        text: 'Pulsa Iniciar para que Riqsi\nobserve tu camino.',
      );
    } else if (_permission == _PermissionStatus.denied ||
        _permission == _PermissionStatus.permanentlyDenied) {
      content = _message(
        icon: Icons.no_photography_rounded,
        text: 'Riqsi necesita permiso de cámara\npara detectar obstáculos.',
        action: _permission == _PermissionStatus.permanentlyDenied
            ? _actionButton('Abrir ajustes del teléfono', openAppSettings)
            : _actionButton('Dar permiso de cámara', _checkPermission),
      );
    } else if (_permission != _PermissionStatus.granted) {
      content = _message(showSpinner: true, text: 'Preparando la cámara…');
    } else if (_modelFailed) {
      content = _message(
        icon: Icons.error_outline_rounded,
        text: 'No se pudo cargar el modelo de detección.',
        action: _actionButton('Reintentar', () {
          setState(() => _modelFailed = false);
        }),
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          YOLOView(
            // Cambiar de lente recrea la vista con la nueva cámara.
            key: ValueKey(widget.isUltraWide),
            modelPath: riqsiModelPath,
            task: YOLOTask.detect,
            controller: _controller,
            lensFacing:
                widget.isUltraWide ? LensFacing.backWide : LensFacing.back,
            confidenceThreshold: _confidenceThreshold,
            streamingConfig: const YOLOStreamingConfig.custom(
              includeClassifications: false,
              includeProcessingTimeMs: false,
              includeFps: false,
              maxFPS: 10,
            ),
            onResult: _onResult,
            onModelLoad: (_, _) => widget.state.reportCameraReady(),
            onModelError: (error, _, _) {
              debugPrint('[YOLO] Error de modelo: $error');
              widget.state.reportCameraError('modelo: $error');
              if (mounted) setState(() => _modelFailed = true);
            },
          ),
          _buildBoundingBoxes(),
        ],
      );
    }

    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: content,
    );
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: A11yTap(
        label: label,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: RiqsiTheme.accentCyan, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: RiqsiTheme.accentCyan,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _message({
    IconData? icon,
    bool showSpinner = false,
    required String text,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const CircularProgressIndicator(color: RiqsiTheme.accentCyan)
            else if (icon != null)
              ExcludeSemantics(
                child: Icon(icon, color: RiqsiTheme.accentCyan, size: 56),
              ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _buildBoundingBoxes() {
    final detection = widget.state.activeDetection;
    if (detection == null || detection.objects.isEmpty) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            children: [
              for (final obj in detection.objects)
                if (obj.boxNorm.length == 4) _box(obj, w, h),
            ],
          );
        },
      ),
    );
  }

  Widget _box(DetectedObject obj, double w, double h) {
    final left = (obj.boxNorm[0] * w).clamp(0.0, w);
    final top = (obj.boxNorm[1] * h).clamp(0.0, h);
    final width =
        ((obj.boxNorm[2] - obj.boxNorm[0]) * w).clamp(24.0, w - left);
    final height =
        ((obj.boxNorm[3] - obj.boxNorm[1]) * h).clamp(24.0, h - top);
    final color = RiqsiTheme.riskColor(obj.riskLevel);
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            left: -1,
            top: -1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Text(
                obj.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

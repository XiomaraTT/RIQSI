import 'package:flutter/material.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';

class ArHudReticle extends StatefulWidget {
  final AppState state;
  final bool isScanning;

  const ArHudReticle({
    super.key,
    required this.state,
    required this.isScanning,
  });

  @override
  State<ArHudReticle> createState() => _ArHudReticleState();
}

class _ArHudReticleState extends State<ArHudReticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    if (widget.isScanning) {
      _sweepController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ArHudReticle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_sweepController.isAnimating) {
      _sweepController.repeat(reverse: true);
    } else if (!widget.isScanning && _sweepController.isAnimating) {
      _sweepController.stop();
    }
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.state.assistanceState;
    final detection = widget.state.activeDetection;

    Color themeColor = RiqsiTheme.accentCyan;
    if (status == AssistanceState.riskDetected) {
      themeColor = RiqsiTheme.alertHigh;
    } else if (status == AssistanceState.objectDetected) {
      themeColor = const Color(0xFF00E5FF);
    } else if (!widget.isScanning) {
      themeColor = Colors.white38;
    }

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Center Assistive AR Target Frame
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _buildCorner(themeColor, isTop: true, isLeft: true),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _buildCorner(themeColor, isTop: true, isLeft: false),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: _buildCorner(themeColor, isTop: false, isLeft: true),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: _buildCorner(themeColor, isTop: false, isLeft: false),
                  ),
                  Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: themeColor, width: 2),
                        color: themeColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  if (detection != null)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: themeColor, width: 1.5),
                          ),
                          child: Text(
                            detection.relativePosition.toUpperCase(),
                            style: TextStyle(
                              color: themeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 2. Animated Laser Scanner Sweep Line (properly placed inside Positioned.fill)
          if (widget.isScanning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sweepController,
                builder: (context, child) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final topPos = _sweepController.value * (constraints.maxHeight - 20);
                      return Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: Offset(0, topPos),
                          child: Container(
                            height: 2.5,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  themeColor.withValues(alpha: 0.7),
                                  themeColor,
                                  themeColor.withValues(alpha: 0.7),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: themeColor.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCorner(Color color, {required bool isTop, required bool isLeft}) {
    const double length = 26.0;
    const double thickness = 3.5;

    return Container(
      width: length,
      height: length,
      decoration: BoxDecoration(
        border: Border(
          top: isTop
              ? BorderSide(color: color, width: thickness)
              : BorderSide.none,
          bottom: !isTop
              ? BorderSide(color: color, width: thickness)
              : BorderSide.none,
          left: isLeft
              ? BorderSide(color: color, width: thickness)
              : BorderSide.none,
          right: !isLeft
              ? BorderSide(color: color, width: thickness)
              : BorderSide.none,
        ),
      ),
    );
  }
}

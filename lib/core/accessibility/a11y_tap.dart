import 'package:flutter/material.dart';

/// Tamaño mínimo recomendado de área táctil (Material / Android: 48dp).
const double kMinTapTarget = 48.0;

/// Contenedor táctil accesible: área mínima de 48x48dp (el dibujo puede ser
/// más pequeño), etiqueta semántica en español, tooltip y el contenido visual
/// excluido del árbol semántico para que TalkBack no lea iconos decorativos.
class A11yTap extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final String? hint;
  final bool? selected;
  final bool? toggled;
  final bool showTooltip;
  final BorderRadius? borderRadius;

  const A11yTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.hint,
    this.selected,
    this.toggled,
    this.showTooltip = true,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      toggled: toggled,
      label: label,
      hint: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              borderRadius ?? BorderRadius.circular(kMinTapTarget / 2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
            ),
            child: Center(widthFactor: 1, heightFactor: 1, child: child),
          ),
        ),
      ),
    );
    if (showTooltip) {
      content = Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: content,
      );
    }
    return content;
  }
}

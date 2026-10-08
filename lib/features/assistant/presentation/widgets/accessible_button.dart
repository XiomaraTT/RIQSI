import 'package:flutter/material.dart';
import '../../../../core/theme/riqsi_theme.dart';

class AccessibleButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color textColor;
  final bool isPrimary;
  final String? semanticHint;

  const AccessibleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = RiqsiTheme.accentCyan,
    this.textColor = Colors.black,
    this.isPrimary = true,
    this.semanticHint,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: semanticHint,
      enabled: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 65), // Large touch target
        child: ElevatedButton(
          onPressed: () {
            onPressed();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isPrimary ? RiqsiTheme.accentCyan : RiqsiTheme.darkSurface,
            foregroundColor: isPrimary ? Colors.black : Colors.white,
            side: isPrimary ? null : const BorderSide(color: RiqsiTheme.accentCyan, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isPrimary ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? activeColor;

  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = activeColor ?? RiqsiTheme.accentCyan;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: () {
            onPressed();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 72,
            height: 72, // Large accessibility tap target
            decoration: BoxDecoration(
              color: isActive ? effectiveColor.withValues(alpha: 0.2) : RiqsiTheme.darkSurface,
              border: Border.all(
                color: isActive ? effectiveColor : RiqsiTheme.textSecondary.withValues(alpha: 0.3),
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 32,
              color: isActive ? effectiveColor : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

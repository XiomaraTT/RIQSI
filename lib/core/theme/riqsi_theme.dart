import 'package:flutter/material.dart';

class RiqsiTheme {
  // Premium Cyan and Slate palette from reference image
  static const Color darkBg = Color(0xFF070E17);
  static const Color darkSurface = Color(0xFF0F1824);
  static const Color accentCyan = Color(0xFF00E5FF); // Vibrant Cyan
  static const Color textPrimary = Color(0xFFFFFFFF);
  // Contraste (WCAG): #8CA0B6 sobre #070E17 = 7.2:1; sobre #0F1824 = 6.6:1 (>= 4.5:1).
  static const Color textSecondary = Color(0xFF8CA0B6); // Slate Grey claro

  // Alert colors
  static const Color alertHigh = Color(0xFFFF3D00); // Tech Red-Orange
  static const Color alertMedium = Color(0xFFFFB300);
  static const Color alertLow = Color(0xFF00E676);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        secondary: accentCyan,
        surface: darkSurface,
        onSurface: textPrimary,
      ),

      // Accessibility typography rules (WCAG compliant sizing & weights)
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 0.5,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600, // Medium bold for legibility
          color: textPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textSecondary,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),

      // High contrast outline buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: accentCyan, width: 2.0),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),

      // Slider/Switch accessibility
      sliderTheme: const SliderThemeData(
        activeTrackColor: accentCyan,
        thumbColor: accentCyan,
        inactiveTrackColor: Color(0xFF1B2C3F),
        valueIndicatorColor: accentCyan,
        trackHeight: 6.0,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentCyan;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accentCyan.withValues(alpha: 0.3);
          }
          return const Color(0xFF1B2C3F);
        }),
      ),
    );
  }
}

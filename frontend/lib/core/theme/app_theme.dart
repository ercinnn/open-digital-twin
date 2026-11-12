import 'package:flutter/material.dart';

/// Dark "engineering console" theme shared by every feature.
class AppTheme {
  const AppTheme._();

  static const Color background = Color(0xFF0B1220);
  static const Color surface = Color(0xFF111A2E);
  static const Color surfaceHigh = Color(0xFF17223A);
  static const Color outline = Color(0xFF253350);
  static const Color accent = Color(0xFF22D3EE);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color marine = Color(0xFF38BDF8);
  static const Color construction = Color(0xFFFBBF24);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
      primary: accent,
      surface: surface,
      surfaceContainerHighest: surfaceHigh,
      outline: outline,
      outlineVariant: outline,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: outline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1, space: 1),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    );
  }
}

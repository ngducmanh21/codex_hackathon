import 'package:flutter/material.dart';

/// Colours borrowed from SCOAI Voice's light theme.
abstract final class C {
  static const paper = Color(0xFFF9FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const sunken = Color(0xFFF0F2F6);
  static const hairline = Color(0xFFE2E6EC);
  static const lineStrong = Color(0xFF7A8590);
  static const ink = Color(0xFF142433);
  static const inkMuted = Color(0xFF626F76);
  static const brand = Color(0xFF183449);
  static const brandSoft = Color(0xFFE7ECF1);
  static const accent = Color(0xFFEC4513);
  static const accentEnd = Color(0xFFEE6A24);
  static const success = Color(0xFF127035);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFBE3E3);
  static const warningSoft = Color(0xFFFBEEDC);
  static const warning = Color(0xFF9C4A07);
}

const accentGradient = LinearGradient(colors: [C.accent, C.accentEnd]);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.brand,
    primary: C.brand,
    onPrimary: Colors.white,
    secondary: C.accent,
    surface: C.paper,
    onSurface: C.ink,
    error: C.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: C.paper,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.ink),
    ),
    dividerColor: C.hairline,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: C.ink),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.ink),
      bodyLarge: TextStyle(fontSize: 16, height: 24 / 16, color: C.ink),
      bodyMedium: TextStyle(fontSize: 15, height: 22 / 15, color: C.ink),
      bodySmall: TextStyle(fontSize: 13, height: 18 / 13, color: C.inkMuted),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: C.brand, width: 1.5),
      ),
      hintStyle: const TextStyle(color: C.inkMuted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.brand : null),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.ink,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

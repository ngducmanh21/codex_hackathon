import 'package:flutter/material.dart';

/// The palette, built from the SCOAI mark: its navy #0B476A is the brand
/// colour, a deeper sky than TwinMind's fades into cool paper behind the
/// home header, and SCOAI's orange marks the one action that records.
abstract final class C {
  /// Cool off-white behind the content.
  static const paper = Color(0xFFF6F8FB);
  static const surface = Color(0xFFFFFFFF);
  static const sunken = Color(0xFFEDF1F6);
  static const hairline = Color(0xFFE1E8EF);
  static const lineStrong = Color(0xFF7A8B99);

  /// Headings: the mark's navy, a shade deeper.
  static const ink = Color(0xFF0C3550);
  static const inkMuted = Color(0xFF607785);

  /// The hexagon's own fill.
  static const brand = Color(0xFF0B476A);
  static const brandSoft = Color(0xFFE2EDF4);
  static const accent = Color(0xFFEC4513);
  static const accentEnd = Color(0xFFF07B2B);
  static const success = Color(0xFF127035);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFBE3E3);
  static const warningSoft = Color(0xFFFBEEDC);
  static const warning = Color(0xFF9C4A07);

  /// The sky behind the home header: the mark's navy, lightened.
  static const skyTop = Color(0xFF0B476A);
  static const skyBottom = Color(0xFF9FC4D9);
}

/// Home's sky: a band at the top that fades into the paper by about a
/// quarter of the screen, as TwinMind's does.
const skyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [C.skyTop, C.skyBottom, C.paper],
  stops: [0, 0.16, 0.26],
);

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
    snackBarTheme: const SnackBarThemeData(backgroundColor: C.ink, behavior: SnackBarBehavior.floating),
  );
}

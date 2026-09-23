import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const violet = Color(0xFF6C4DFF);
  static const cyan = Color(0xFF00A3C4);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF5B3DF0),
      secondary: cyan,
      surface: Colors.white,
      surfaceContainerHighest: const Color(0xFFECE9F7),
    ),
    scaffold: const Color(0xFFF7F6FD),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF9C8CFF),
      secondary: const Color(0xFF4DD0E8),
      surface: const Color(0xFF1A1826),
      surfaceContainerHighest: const Color(0xFF2A2740),
    ),
    scaffold: const Color(0xFF0E0D16),
  );

  static ThemeData _build(ColorScheme scheme, {required Color scaffold}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        titleMedium: TextStyle(fontWeight: FontWeight.w700, height: 1.25),
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          height: 1.2,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

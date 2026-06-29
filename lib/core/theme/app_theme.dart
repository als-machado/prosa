import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color _primaryLight = Color(0xFF2D6A4F);
  static const Color _primaryDark = Color(0xFF52B788);
  static const Color _surfaceLight = Color(0xFFFAF8F5);
  static const Color _surfaceDark = Color(0xFF1A1A2E);
  static const Color _backgroundLight = Color(0xFFF2EFE9);
  static const Color _backgroundDark = Color(0xFF0F0F1A);
  static const Color _sidebarLight = Color(0xFFE8E4DC);
  static const Color _sidebarDark = Color(0xFF16213E);

  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: _primaryLight,
      surface: _surfaceLight,
      surfaceContainerLowest: _sidebarLight,
    ),
    scaffoldBackgroundColor: _backgroundLight,
    textTheme: GoogleFonts.interTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: _surfaceLight,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFD5CFC4)),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: _primaryDark,
      surface: _surfaceDark,
      surfaceContainerLowest: _sidebarDark,
    ),
    scaffoldBackgroundColor: _backgroundDark,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: _surfaceDark,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF2A2A4A)),
  );
}

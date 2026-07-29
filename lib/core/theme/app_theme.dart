import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Paleta inspirada no app Claude (tons quentes, terracota/cobre)
  static const Color _primaryLight    = Color(0xFFCC6B3D); // terracota quente
  static const Color _onPrimaryLight  = Color(0xFFFFFFFF);
  static const Color _bgLight         = Color(0xFFF7F3EC); // creme quente
  static const Color _surfaceLight    = Color(0xFFFFFDF9); // branco levemente aquecido
  static const Color _sidebarLight    = Color(0xFFEEE7DC); // creme mais escuro para sidebar
  static const Color _onSurfaceLight  = Color(0xFF1C1712); // marrom-escuro para texto
  static const Color _dividerLight    = Color(0xFFE0D8CC);

  /// Cor do sublinhado ondulado da verificação ortográfica.
  ///
  /// Não usa `colorScheme.error` de propósito. No tema escuro o error do
  /// Material 3 é `#FFB4AB`, um rosa lavado: mesmo tendo o maior contraste de
  /// luminância contra o fundo (10,9x, medido), ele não salta, porque o que
  /// falta é saturação — passa por mais uma linha clara no meio de texto
  /// claro. `#FF5252` tem 5,8x de contraste, bem acima do necessário para
  /// decoração, e lê na hora como marca de erro.
  static Color spellcheckUnderline(Brightness brightness) =>
      brightness == Brightness.dark ? _spellcheckDark : _spellcheckLight;

  static const Color _spellcheckLight = Color(0xFFBA1A1A);
  static const Color _spellcheckDark  = Color(0xFFFF5252);

  static const Color _primaryDark     = Color(0xFFE8906A); // cobre claro para dark mode
  static const Color _onPrimaryDark   = Color(0xFF1A0A02);
  static const Color _bgDark          = Color(0xFF141414); // cinza escuro neutro
  static const Color _surfaceDark     = Color(0xFF1E1E1E); // superfície cinza escura
  static const Color _sidebarDark     = Color(0xFF191919); // sidebar levemente mais escura
  static const Color _onSurfaceDark   = Color(0xFFEDEDED); // texto claro neutro
  static const Color _dividerDark     = Color(0xFF2C2C2C);

  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: _primaryLight,
      onPrimary: _onPrimaryLight,
      secondary: Color(0xFFB8896A),
      onSecondary: _onPrimaryLight,
      surface: _surfaceLight,
      onSurface: _onSurfaceLight,
      onSurfaceVariant: Color(0xFF5C4F42),
      surfaceContainerLowest: _sidebarLight,
      surfaceContainerLow: Color(0xFFF2EBE1),
      surfaceContainer: Color(0xFFEBE3D8),
      outline: Color(0xFFB8A898),
      outlineVariant: _dividerLight,
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
    ),
    scaffoldBackgroundColor: _bgLight,
    textTheme: GoogleFonts.interTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: _surfaceLight,
      foregroundColor: _onSurfaceLight,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: _surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: _dividerLight),
      ),
    ),
    dividerTheme: const DividerThemeData(color: _dividerLight, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: _dividerLight),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _primaryLight,
        foregroundColor: _onPrimaryLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: _primaryDark,
      onPrimary: _onPrimaryDark,
      secondary: Color(0xFFCCA07A),
      onSecondary: _onPrimaryDark,
      surface: _surfaceDark,
      onSurface: _onSurfaceDark,
      onSurfaceVariant: Color(0xFFAAAAAA),
      surfaceContainerLowest: _sidebarDark,
      surfaceContainerLow: Color(0xFF212121),
      surfaceContainer: Color(0xFF252525),
      outline: Color(0xFF606060),
      outlineVariant: _dividerDark,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
    ),
    scaffoldBackgroundColor: _bgDark,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: _surfaceDark,
      foregroundColor: _onSurfaceDark,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: _dividerDark),
      ),
    ),
    dividerTheme: const DividerThemeData(color: _dividerDark, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: _dividerDark),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _primaryDark,
        foregroundColor: _onPrimaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
    ),
  );
}

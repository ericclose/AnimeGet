import 'package:material_ui/material_ui.dart';

/// Material 3 Slate + Ocean-Blue color tokens inspired by openwrt-checker.
class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF00658F),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFC7E7FF),
      onPrimaryContainer: Color(0xFF001E2E),
      secondary: Color(0xFF4E616D),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD2E5F4),
      onSecondaryContainer: Color(0xFF0B1D28),
      tertiary: Color(0xFF615A7D),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFE6DEFF),
      onTertiaryContainer: Color(0xFF1D1736),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFF8FAFC),
      onSurface: Color(0xFF0F172A),
      onSurfaceVariant: Color(0xFF475569),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF1F5F9),
      surfaceContainer: Color(0xFFE2E8F0),
      surfaceContainerHigh: Color(0xFFCBD5E1),
      surfaceContainerHighest: Color(0xFF94A3B8),
      outline: Color(0xFF94A3B8),
      outlineVariant: Color(0xFFCBD5E1),
      inverseSurface: Color(0xFF1E293B),
      onInverseSurface: Color(0xFFF8FAFC),
      inversePrimary: Color(0xFF85CFFF),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF85CFFF),
      onPrimary: Color(0xFF00344C),
      primaryContainer: Color(0xFF004C6D),
      onPrimaryContainer: Color(0xFFC7E7FF),
      secondary: Color(0xFFB6C9D7),
      onSecondary: Color(0xFF20333E),
      secondaryContainer: Color(0xFF334155),
      onSecondaryContainer: Color(0xFFE2E8F0),
      tertiary: Color(0xFFCBC1EA),
      onTertiary: Color(0xFF322C4C),
      tertiaryContainer: Color(0xFF494363),
      onTertiaryContainer: Color(0xFFE6DEFF),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF090D10),
      onSurface: Color(0xFFE2E8F0),
      onSurfaceVariant: Color(0xFF94A3B8),
      surfaceContainerLowest: Color(0xFF0F172A),
      surfaceContainerLow: Color(0xFF131D2E),
      surfaceContainer: Color(0xFF172338),
      surfaceContainerHigh: Color(0xFF1E2F49),
      surfaceContainerHighest: Color(0xFF283E5F),
      outline: Color(0xFF475569),
      outlineVariant: Color(0xFF1E293B),
      inverseSurface: Color(0xFFE2E8F0),
      onInverseSurface: Color(0xFF0F172A),
      inversePrimary: Color(0xFF00658F),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
    );
  }

  static Color colorByTitle(String text) {
    if (text.isEmpty) return const Color(0xFF00658F);
    const palette = <Color>[
      Color(0xFF00658F),
      Color(0xFF1D4ED8),
      Color(0xFF0F766E),
      Color(0xFF615A7D),
      Color(0xFF0369A1),
      Color(0xFF4338CA),
      Color(0xFF047857),
      Color(0xFF334155),
    ];
    return palette[text.runes.fold<int>(0, (a, b) => a + b) % palette.length];
  }
}

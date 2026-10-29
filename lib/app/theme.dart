import 'package:flutter/material.dart';

/// Obsidian 设计 token（对齐 SPEC §4.5）。
class ObsidianPalette {
  const ObsidianPalette({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgHover,
    required this.border,
    required this.textNormal,
    required this.textMuted,
  });

  static const dark = ObsidianPalette(
    bgPrimary: Color(0xFF1E1E1E),
    bgSecondary: Color(0xFF262626),
    bgHover: Color(0xFF2F2F2F),
    border: Color(0xFF363636),
    textNormal: Color(0xFFDCDDDE),
    textMuted: Color(0xFF999999),
  );

  static const light = ObsidianPalette(
    bgPrimary: Color(0xFFFFFFFF),
    bgSecondary: Color(0xFFF2F3F5),
    bgHover: Color(0xFFE9E9E9),
    border: Color(0xFFE1E4E8),
    textNormal: Color(0xFF222222),
    textMuted: Color(0xFF8A8A8A),
  );

  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgHover;
  final Color border;
  final Color textNormal;
  final Color textMuted;
}

/// Obsidian 默认强调色（可在设置中自定义）。
const Color kDefaultAccent = Color(0xFF7F6DF2);

ThemeData buildJinahTheme({
  required ObsidianPalette p,
  required Color accent,
  required Brightness brightness,
}) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: Colors.white,
    secondary: accent,
    onSecondary: Colors.white,
    error: brightness == Brightness.dark
        ? const Color(0xFFCF6679)
        : const Color(0xFFB3261E),
    onError: Colors.white,
    surface: p.bgPrimary,
    onSurface: p.textNormal,
    surfaceContainerHighest: p.bgSecondary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bgPrimary,
    dividerColor: p.border,
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: p.textNormal),
      bodyMedium: TextStyle(color: p.textNormal),
      bodySmall: TextStyle(color: p.textMuted),
      titleLarge: TextStyle(color: p.textNormal, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: p.textNormal, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(color: p.textNormal),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bgPrimary,
      foregroundColor: p.textNormal,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.bgSecondary,
      contentTextStyle: TextStyle(color: p.textNormal),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: p.border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.bgSecondary,
      hintStyle: TextStyle(color: p.textMuted),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.bgSecondary,
      indicatorColor: accent.withValues(alpha: 0.15),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.bgSecondary,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.border),
      ),
      textStyle: TextStyle(color: p.textNormal, fontSize: 12),
    ),
  );
}

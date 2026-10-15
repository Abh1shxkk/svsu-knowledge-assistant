/// Colours from the web app's globals.css, so the app looks the same in light and dark mode.
library;

import 'package:flutter/material.dart';

@immutable
class Pal extends ThemeExtension<Pal> {
  const Pal({
    required this.bg, required this.surface, required this.surface2, required this.surface3,
    required this.line, required this.line2, required this.fg, required this.fg2, required this.fg3,
    required this.accent, required this.accent2, required this.accentSoft, required this.accentInk,
    required this.chart, required this.heroBg, required this.heroFg,
    required this.green, required this.greenSoft, required this.amber, required this.amberSoft,
    required this.red, required this.redSoft, required this.paper, required this.paperFg, required this.paperLine,
    required this.paperDim, required this.hl, required this.hlRing,
  });

  final Color bg, surface, surface2, surface3, line, line2, fg, fg2, fg3;
  final Color accent, accent2, accentSoft, accentInk, chart, heroBg, heroFg;
  final Color green, greenSoft, amber, amberSoft, red, redSoft;
  final Color paper, paperFg, paperLine, paperDim, hl, hlRing;

  static const light = Pal(
    bg: Color(0xFFF5F4F1), surface: Color(0xFFFFFFFF), surface2: Color(0xFFF8F7F4), surface3: Color(0xFFEFEDE8),
    line: Color(0xFFE7E4DE), line2: Color(0xFFD8D4CC), fg: Color(0xFF1B1A18), fg2: Color(0xFF57534D), fg3: Color(0xFF78736B),
    accent: Color(0xFF1F5F73), accent2: Color(0xFF174B5C), accentSoft: Color(0xFFE6EFF1), accentInk: Color(0xFFFFFFFF),
    chart: Color(0xFF0A7AA0), heroBg: Color(0xFF1D3C47), heroFg: Color(0xFFF7F5F0),
    green: Color(0xFF2F7A4A), greenSoft: Color(0xFFECF5EE), amber: Color(0xFF9A6A12), amberSoft: Color(0xFFFBF3E3),
    red: Color(0xFFB4452C), redSoft: Color(0xFFFBEEEA),
    paper: Color(0xFFFFFFFF), paperFg: Color(0xFF1D1C1A), paperLine: Color(0xFFE7E4DE), paperDim: Color(0xFF78736B),
    hl: Color(0xFFFBE3A1), hlRing: Color(0xFFC08A12),
  );

  static const dark = Pal(
    bg: Color(0xFF141312), surface: Color(0xFF1C1B19), surface2: Color(0xFF22211F), surface3: Color(0xFF2B2A27),
    line: Color(0xFF2E2C29), line2: Color(0xFF3C3A36), fg: Color(0xFFF1EFEA), fg2: Color(0xFFC3BEB5), fg3: Color(0xFF958F85),
    accent: Color(0xFF4F97AD), accent2: Color(0xFF63A7BC), accentSoft: Color(0xFF1D2F35), accentInk: Color(0xFF0E181B),
    chart: Color(0xFF2A9FC7), heroBg: Color(0xFF1B2F37), heroFg: Color(0xFFF1EFEA),
    green: Color(0xFF6FBF8A), greenSoft: Color(0xFF16261C), amber: Color(0xFFE3B25A), amberSoft: Color(0xFF2A2112),
    red: Color(0xFFE58A73), redSoft: Color(0xFF2D1A15),
    paper: Color(0xFF1C1B19), paperFg: Color(0xFFEBE8E2), paperLine: Color(0xFF33312D), paperDim: Color(0xFF958F85),
    hl: Color(0x42EAB308), hlRing: Color(0xFFE3B25A),
  );

  @override
  Pal copyWith() => this;

  @override
  Pal lerp(Pal? other, double t) => t < .5 ? this : (other ?? this);
}

extension PalX on BuildContext {
  Pal get pal => Theme.of(this).extension<Pal>()!;
}

const docFont = 'serif';
const monoFont = 'monospace';

ThemeData buildTheme(Pal p, Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: b).copyWith(
    primary: p.accent, onPrimary: p.accentInk, surface: p.surface, onSurface: p.fg, error: p.red,
    outline: p.line2, outlineVariant: p.line, surfaceContainerHighest: p.surface3, secondary: p.accent2,
  );
  final r = BorderRadius.circular(10);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg, foregroundColor: p.fg, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(color: p.fg, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: p.surface, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: p.surface, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: p.line2)),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: p.line2)),
      focusedBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: p.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: p.red)),
      hintStyle: TextStyle(color: p.fg3),
      labelStyle: TextStyle(color: p.fg2),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: p.accent, foregroundColor: p.accentInk, shape: RoundedRectangleBorder(borderRadius: r),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), textStyle: const TextStyle(fontWeight: FontWeight.w600),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: p.fg, side: BorderSide(color: p.line2), shape: RoundedRectangleBorder(borderRadius: r),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.accent)),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface, selectedColor: p.accentSoft, side: BorderSide(color: p.line2),
      labelStyle: TextStyle(color: p.fg, fontSize: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: p.fg, contentTextStyle: TextStyle(color: p.bg)),
    drawerTheme: DrawerThemeData(backgroundColor: p.surface),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, showDragHandle: true),
    dialogTheme: DialogThemeData(backgroundColor: p.surface),
    tabBarTheme: TabBarThemeData(labelColor: p.accent, unselectedLabelColor: p.fg2, indicatorColor: p.accent, dividerColor: p.line),
    listTileTheme: ListTileThemeData(iconColor: p.fg2, textColor: p.fg),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : null)),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.fg3)),
    switchTheme: SwitchThemeData(trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : null)),
  );
}

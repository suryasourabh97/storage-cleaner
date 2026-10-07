import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Design tokens. One accent (amber) marks space that can be reclaimed;
/// brick red is reserved for permanent deletion.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.paper,
    required this.surface,
    required this.sidebar,
    required this.ink,
    required this.muted,
    required this.line,
    required this.amber,
    required this.onAmber,
    required this.brick,
    required this.track,
  });

  final Color paper;
  final Color surface;
  final Color sidebar;
  final Color ink;
  final Color muted;
  final Color line;
  final Color amber;
  final Color onAmber;
  final Color brick;
  final Color track;

  static const light = Tokens(
    paper: Color(0xFFF2F4F7),
    surface: Color(0xFFFFFFFF),
    sidebar: Color(0xFFE6EAF0),
    ink: Color(0xFF1C2633),
    muted: Color(0xFF667180),
    line: Color(0xFFDCE1E8),
    amber: Color(0xFFE3A21A),
    onAmber: Color(0xFF1C2633),
    brick: Color(0xFFB83A25),
    track: Color(0xFFDCE1E8),
  );

  static const dark = Tokens(
    paper: Color(0xFF151A21),
    surface: Color(0xFF1D242D),
    sidebar: Color(0xFF11161C),
    ink: Color(0xFFE6EAF0),
    muted: Color(0xFF97A1AE),
    line: Color(0xFF2C3540),
    amber: Color(0xFFF0B43A),
    onAmber: Color(0xFF151A21),
    brick: Color(0xFFE0654F),
    track: Color(0xFF2C3540),
  );

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(Tokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TokensX on BuildContext {
  Tokens get tokens => Theme.of(this).extension<Tokens>()!;
}

const _textFamily = 'Segoe UI Variable Text';
const _displayFamily = 'Segoe UI Variable Display';
const _fallback = ['Segoe UI', 'Arial'];
const tabular = [FontFeature.tabularFigures()];

/// Big light numerals for sizes (the app's typographic signature).
TextStyle figure(BuildContext context, {double size = 40}) => TextStyle(
      fontFamily: _displayFamily,
      fontFamilyFallback: _fallback,
      fontSize: size,
      fontWeight: FontWeight.w300,
      height: 1.1,
      color: context.tokens.ink,
      fontFeatures: tabular,
    );

/// Right-aligned size column in lists.
TextStyle sizeText(BuildContext context) => TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: context.tokens.ink,
      fontFeatures: tabular,
    );

ThemeData buildTheme(Brightness brightness) {
  final t = brightness == Brightness.light ? Tokens.light : Tokens.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: t.ink,
    brightness: brightness,
  ).copyWith(
    primary: t.ink,
    onPrimary: t.paper,
    secondary: t.amber,
    onSecondary: t.onAmber,
    error: t.brick,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.ink,
    onSurfaceVariant: t.muted,
    outline: t.line,
    outlineVariant: t.line,
    surfaceContainerHighest: t.paper,
  );

  TextStyle s(double size, FontWeight w, {String family = _textFamily}) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: _fallback,
        fontSize: size,
        fontWeight: w,
        color: t.ink,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.paper,
    fontFamily: _textFamily,
    fontFamilyFallback: _fallback,
    extensions: [t],
    textTheme: TextTheme(
      displaySmall: s(30, FontWeight.w400, family: _displayFamily),
      headlineSmall: s(20, FontWeight.w600, family: _displayFamily),
      titleMedium: s(15, FontWeight.w600),
      titleSmall: s(13, FontWeight.w600),
      bodyLarge: s(15, FontWeight.w400),
      bodyMedium: s(13, FontWeight.w400),
      bodySmall: s(12, FontWeight.w400).copyWith(color: t.muted),
      labelLarge: s(13, FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? t.ink : null,
      ),
      checkColor: WidgetStatePropertyAll(t.paper),
      side: BorderSide(color: t.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? t.amber : t.muted,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.ink,
        foregroundColor: t.paper,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: s(13, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        side: BorderSide(color: t.line),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: s(13, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.ink,
        textStyle: s(13, FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: s(20, FontWeight.w600, family: _displayFamily),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.ink,
      contentTextStyle: s(13, FontWeight.w400).copyWith(color: t.paper),
      width: 560,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: s(13, FontWeight.w400),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.amber,
      linearTrackColor: t.track,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.ink,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: s(12, FontWeight.w400).copyWith(color: t.paper),
    ),
  );
}

import 'package:flutter/material.dart';

class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
    );
  }
}

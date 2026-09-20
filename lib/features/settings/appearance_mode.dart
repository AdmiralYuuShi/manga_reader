import 'package:flutter/material.dart';

enum AppearanceMode {
  system('system', 'System', ThemeMode.system),
  light('light', 'Light', ThemeMode.light),
  dark('dark', 'Dark', ThemeMode.dark);

  const AppearanceMode(this.id, this.label, this.themeMode);

  final String id;
  final String label;
  final ThemeMode themeMode;

  static AppearanceMode fromId(String? id) =>
      values.firstWhere((mode) => mode.id == id, orElse: () => system);
}

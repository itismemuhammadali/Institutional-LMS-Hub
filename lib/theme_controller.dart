import 'package:flutter/material.dart';

/// Simple app-wide theme controller using a ValueNotifier.
/// No external state management needed.
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  /// Current theme mode for the app.
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

  void setThemeMode(ThemeMode mode) {
    if (themeMode.value != mode) {
      themeMode.value = mode;
    }
  }

  void toggle() {
    setThemeMode(themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

enum ThemeSetting { auto, light, dark }

class ThemeNotifier extends StateNotifier<ThemeSetting> {
  ThemeNotifier() : super(ThemeSetting.auto);

  void setTheme(ThemeSetting setting) => state = setting;
  void toggleOverride() {
    if (state == ThemeSetting.auto) {
      final auto = AppTheme.autoThemeMode();
      state = auto == ThemeMode.light ? ThemeSetting.dark : ThemeSetting.light;
    } else {
      state = ThemeSetting.auto;
    }
  }

  ThemeMode get themeMode {
    switch (state) {
      case ThemeSetting.light:
        return ThemeMode.light;
      case ThemeSetting.dark:
        return ThemeMode.dark;
      case ThemeSetting.auto:
        return AppTheme.autoThemeMode();
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeSetting>(
  (ref) => ThemeNotifier(),
);

final themeModeProvider = Provider<ThemeMode>((ref) {
  ref.watch(themeProvider);
  return ref.read(themeProvider.notifier).themeMode;
});

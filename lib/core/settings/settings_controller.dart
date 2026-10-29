import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('在 main() 中 override 注入'),
);

class SettingsState {
  const SettingsState({required this.themeMode, required this.accent});

  final ThemeMode themeMode;
  final Color accent;

  SettingsState copyWith({ThemeMode? themeMode, Color? accent}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
      );
}

class SettingsController extends Notifier<SettingsState> {
  static const _themeKey = 'theme_mode';
  static const _accentKey = 'accent_color';

  @override
  SettingsState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final themeIndex = prefs.getInt(_themeKey) ?? ThemeMode.dark.index;
    final accentValue =
        prefs.getInt(_accentKey) ?? kDefaultAccent.toARGB32();
    return SettingsState(
      themeMode: ThemeMode.values[themeIndex.clamp(0, 2)],
      accent: Color(accentValue),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref.read(sharedPreferencesProvider).setInt(_themeKey, mode.index);
  }

  Future<void> setAccent(Color color) async {
    state = state.copyWith(accent: color);
    await ref
        .read(sharedPreferencesProvider)
        .setInt(_accentKey, color.toARGB32());
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

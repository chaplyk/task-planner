import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'theme_mode';

/// Light, dark, or follow the phone (system). Defaults to system.
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_prefKey);
  themeModeNotifier.value = ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefKey, mode.name);
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Automatic',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

import 'package:material_ui/material_ui.dart';

import '../core/constants/app_constants.dart';
import '../data/database/database_helper.dart';

/// Persists the user's light/dark preference in SQLite.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._db);

  final DatabaseHelper _db;

  ThemeMode _mode = ThemeMode.system;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final String? stored = await _db.getSetting(AppConstants.settingThemeMode);
    _mode = _parseMode(stored);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    try {
      await _db.setSetting(AppConstants.settingThemeMode, mode.name);
    } catch (_) {
      // A preference write failure should never block the UI.
    }
  }

  /// Cycles system → light → dark. Used by the compact AppBar toggle.
  Future<void> cycle() async {
    switch (_mode) {
      case ThemeMode.system:
        await setMode(ThemeMode.light);
        break;
      case ThemeMode.light:
        await setMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        await setMode(ThemeMode.system);
        break;
    }
  }

  static ThemeMode _parseMode(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}

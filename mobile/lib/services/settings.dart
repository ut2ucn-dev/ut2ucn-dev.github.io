import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device preferences: theme and lesson reminders.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);
  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  ThemeMode get themeMode {
    switch (_prefs.getString('theme')) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  set themeMode(ThemeMode m) {
    _prefs.setString('theme', m.name);
    notifyListeners();
  }

  bool get remindersEnabled => _prefs.getBool('reminders') ?? true;
  set remindersEnabled(bool v) {
    _prefs.setBool('reminders', v);
    notifyListeners();
  }

  /// Minutes before a lesson starts.
  int get reminderLead => _prefs.getInt('reminderLead') ?? 15;
  set reminderLead(int v) {
    _prefs.setInt('reminderLead', v);
    notifyListeners();
  }

  /// Admins only: remind about every lesson in the studio, not just own.
  bool get remindAllStudio => _prefs.getBool('remindAllStudio') ?? false;
  set remindAllStudio(bool v) {
    _prefs.setBool('remindAllStudio', v);
    notifyListeners();
  }

  /// Morning summary of the day's lessons.
  bool get dailyDigest => _prefs.getBool('dailyDigest') ?? true;
  set dailyDigest(bool v) {
    _prefs.setBool('dailyDigest', v);
    notifyListeners();
  }

  /// The signed-in person's profile row, so the app can open offline.
  Map<String, dynamic>? cachedProfile(String userId) {
    final raw = _prefs.getString('profile');
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return m['id'] == userId ? m : null;
  }

  void saveProfile(Map<String, dynamic>? row) =>
      row == null ? _prefs.remove('profile') : _prefs.setString('profile', jsonEncode(row));

  String? get lastEmail => _prefs.getString('lastEmail');
  set lastEmail(String? v) => v == null ? _prefs.remove('lastEmail') : _prefs.setString('lastEmail', v);
}

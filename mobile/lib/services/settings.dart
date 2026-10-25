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

  /// Admins only: a notification when a colleague prints a model, adds a
  /// student, moves or cancels a lesson.
  bool get othersEvents => _prefs.getBool('othersEvents') ?? true;
  set othersEvents(bool v) {
    _prefs.setBool('othersEvents', v);
    notifyListeners();
  }

  /// Morning summary of the day's lessons.
  bool get dailyDigest => _prefs.getBool('dailyDigest') ?? true;
  set dailyDigest(bool v) {
    _prefs.setBool('dailyDigest', v);
    notifyListeners();
  }

  /// What was opened last from the ⌘K search (`student:<id>`,
  /// `lesson:<id>`, `teacher:<id>`), newest first.
  List<String> get recentSearch => _prefs.getStringList('recentSearch') ?? const [];
  void addRecentSearch(String key) =>
      _prefs.setStringList('recentSearch', [key, ...recentSearch.where((k) => k != key)].take(6).toList());

  /// Extra Mac windows opened and not yet known to be closed: the main
  /// window takes over what they couldn't send (desktop/windows.dart).
  List<String> get openWindows => _prefs.getStringList('openWindows') ?? const [];
  void rememberWindow(String key) => _prefs.setStringList('openWindows', {...openWindows, key}.toList());
  void forgetWindow(String key) => _prefs.setStringList('openWindows', openWindows.where((k) => k != key).toList());

  /// The printer and filament picked last when marking a model printed.
  String? get lastPrinterId => _prefs.getString('lastPrinterId');
  String? get lastFilamentId => _prefs.getString('lastFilamentId');
  void saveLastPrintChoice(String? printerId, String? filamentId) {
    printerId == null ? _prefs.remove('lastPrinterId') : _prefs.setString('lastPrinterId', printerId);
    filamentId == null ? _prefs.remove('lastFilamentId') : _prefs.setString('lastFilamentId', filamentId);
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

  /// Which side of the login screen was used last: staff or parents.
  bool get parentLoginMode => _prefs.getBool('parentLoginMode') ?? false;
  set parentLoginMode(bool v) => _prefs.setBool('parentLoginMode', v);

  String? get lastParentPhone => _prefs.getString('lastParentPhone');
  set lastParentPhone(String? v) =>
      v == null ? _prefs.remove('lastParentPhone') : _prefs.setString('lastParentPhone', v);

  /// A signed-in parent's session token (sql/0018). Parents never have a
  /// Supabase Auth session, so this alone says the app is in parent mode.
  String? get parentToken => _prefs.getString('parentToken');

  /// The last parent_portal() document, so the portal opens offline.
  Map<String, dynamic>? get cachedParentPortal {
    final raw = _prefs.getString('parentPortal');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  void saveParentPortal(Map<String, dynamic>? doc) =>
      doc == null ? _prefs.remove('parentPortal') : _prefs.setString('parentPortal', jsonEncode(doc));

  /// Child last looked at in the portal.
  String? get parentChildId => _prefs.getString('parentChild');
  set parentChildId(String? v) => v == null ? _prefs.remove('parentChild') : _prefs.setString('parentChild', v);

  void setParentToken(String? token) {
    if (token == null) {
      _prefs.remove('parentToken');
      _prefs.remove('parentPortal');
      _prefs.remove('parentChild');
    } else {
      _prefs.setString('parentToken', token);
    }
    notifyListeners();
  }
}

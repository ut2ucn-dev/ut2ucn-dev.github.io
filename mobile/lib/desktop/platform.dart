import 'package:flutter/foundation.dart';

/// `--dart-define=STEMIK_DESKTOP=true` shows the desktop admin app on any
/// platform (Chrome, Linux) — for development, previews and tests.
const _forceDesktop = bool.fromEnvironment('STEMIK_DESKTOP');

bool get _mac => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// The macOS and Windows builds are a separate product: the studio's admin
/// console. Only admins and superadmins may sign in, there is no parents'
/// portal, and the signed-in app is the desktop shell (sidebar, split
/// panes, menus) instead of the phone's bottom tabs. Everything else —
/// data, offline outbox, business rules, screens, the launch intro — is
/// shared with the phone app.
bool get isAdminDesktop => _forceDesktop || _mac || _windows;

/// The real macOS app, where the native menu bar exists.
bool get hasNativeMenuBar => _mac;

/// The real Windows app: its menus are drawn by the app, under the title bar.
bool get isWindowsApp => _windows;

/// Where the native side can open extra windows (a student's card on its
/// own): the Mac (macos/Runner) and Windows (windows/runner).
bool get hasAppWindows => _mac || _windows;

/// A shortcut as the platform writes it: "⇧⌘N" on the Mac, "Ctrl+Shift+N"
/// elsewhere. [key] is the key's label ("N", ",", "1").
String shortcutLabel(String key, {bool shift = false}) =>
    _mac ? '${shift ? '⇧' : ''}⌘$key' : 'Ctrl+${shift ? 'Shift+' : ''}$key';

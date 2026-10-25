import 'package:flutter/foundation.dart';

/// `--dart-define=STEMIK_DESKTOP=true` shows the macOS admin app on any
/// platform (Chrome, Linux) — for development, previews and tests.
const _forceDesktop = bool.fromEnvironment('STEMIK_DESKTOP');

/// The macOS build is a separate product: the studio's admin console. Only
/// admins and superadmins may sign in, there is no parents' portal, and the
/// signed-in app is the desktop shell (sidebar, split panes, menu bar)
/// instead of the phone's bottom tabs. Everything else — data, offline
/// outbox, business rules, screens, the launch intro — is shared with the
/// phone app.
bool get isAdminDesktop => _forceDesktop || (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

/// The real macOS app, where the native menu bar exists.
bool get hasNativeMenuBar => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

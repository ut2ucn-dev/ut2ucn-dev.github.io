import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/parent_portal.dart';
import '../data/store.dart';
import '../services/reminders.dart';
import '../services/settings.dart';
import 'intro.dart';
import 'login_screen.dart';
import 'parent/parent_home.dart';
import 'scope.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

class StemikApp extends StatelessWidget {
  const StemikApp({
    super.key,
    required this.store,
    required this.parentApi,
    required this.settings,
    required this.reminders,
  });
  final AppStore store;
  final ParentApi parentApi;
  final Settings settings;
  final Reminders reminders;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: StoreScope(
        store: store,
        child: RemindersScope(
          reminders: reminders,
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => MaterialApp(
              title: 'Stemik',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: settings.themeMode,
              locale: const Locale('uk'),
              supportedLocales: const [Locale('uk')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              // The robot's hello on launch, over the app as it loads.
              builder: (context, child) => LaunchIntro(child: child!),
              home: AuthGate(api: store.api, parentApi: parentApi),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Gate { loading, signedOut, ready }

/// Decides between the login screen and the app. Opens straight into the
/// app from the cached profile when offline; confirms it with the server
/// in the background (and signs out a deactivated account, as the web does).
/// A parent's session token (sql/0018) takes over the whole app with the
/// parents' portal; parents never have a Supabase Auth session.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.api, required this.parentApi});
  final StemikApi api;
  final ParentApi parentApi;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Gate _gate = _Gate.loading;
  StreamSubscription<AuthEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.api.authEvents.listen((e) {
      if (e == AuthEvent.signedOut) {
        _signedOut();
      } else if (e == AuthEvent.signedIn && _gate != _Gate.ready) {
        _open();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    final uid = widget.api.currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _gate = _Gate.signedOut);
      return;
    }
    final store = context.storeRead;
    final settings = SettingsScope.read(context);
    final cached = settings.cachedProfile(uid);
    if (cached != null) {
      await store.open(Profile(cached));
      if (mounted) setState(() => _gate = _Gate.ready);
    }
    final row = await store.fetch(() => widget.api.fetchProfile(uid), quiet: cached != null);
    if (!mounted) return;
    if (row == null) {
      if (cached == null) {
        // First sign-in on this device and the profile can't be loaded.
        setState(() => _gate = _Gate.signedOut);
        await widget.api.signOut();
      }
      return;
    }
    final p = Profile(row);
    if (!p.active) {
      store.say('Обліковий запис деактивовано. Зверніться до адміністратора.');
      await _signOut();
      return;
    }
    settings.saveProfile(row);
    await store.open(p);
    if (mounted) setState(() => _gate = _Gate.ready);
  }

  Future<void> _signedOut() async {
    final store = context.storeRead;
    SettingsScope.read(context).saveProfile(null);
    await store.close();
    if (mounted) setState(() => _gate = _Gate.signedOut);
  }

  Future<void> _signOut() async {
    await widget.api.signOut();
    await _signedOut();
  }

  @override
  Widget build(BuildContext context) {
    if (SettingsScope.of(context).parentToken != null) return ParentHome(api: widget.parentApi);
    switch (_gate) {
      case _Gate.loading:
        return const Scaffold(body: LoadingView());
      case _Gate.signedOut:
        return LoginScreen(api: widget.api, parentApi: widget.parentApi);
      case _Gate.ready:
        return HomeShell(onSignOut: _signOut);
    }
  }
}

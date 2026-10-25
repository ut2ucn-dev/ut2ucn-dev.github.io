import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../data/local_files.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../data/supabase_api.dart';
import '../services/settings.dart';
import '../ui/scope.dart';
import '../ui/students/student_card_screen.dart';
import '../ui/theme.dart';

// Extra windows on the Mac — a student's card next to the main window.
//
// Stable Flutter draws one window per engine, so each extra window runs
// the app's Dart code again in an engine of its own (macos/Runner/
// MainFlutterWindow.swift, StemikWindows), started with the entrypoint
// arguments ["window", <spec>]. The two sides talk through the native
// code:
//
//  * the window never refreshes the login session (two engines refreshing
//    one session sign each other out): the main window hands it the
//    access token, and every refreshed one;
//  * each side tells the other when it changed something on the server,
//    and the other reloads;
//  * the window keeps its cache and queue of offline changes in files of
//    its own; when it closes — or at the next start, if the app quit with
//    it open — the main window takes over whatever it couldn't send.

/// The extra windows, seen from the main window. Null where there are none
/// (phones, the web, tests, the demo).
class AppWindows {
  AppWindows._(this.store, this.files, this.settings);
  final AppStore store;
  final LocalFiles files;
  final Settings settings;

  static AppWindows? main;
  static const _channel = MethodChannel('studio.stemik/windows');

  /// In the main window of the real Mac app.
  static void start(AppStore store, LocalFiles files, Settings settings) {
    main = AppWindows._(store, files, settings).._listen();
  }

  ThemeMode? _theme;

  void _listen() {
    _channel.setMethodCallHandler(_handle);
    store.serverWrites.listen((_) => _broadcast({'type': 'changed'}));
    store.api.accessTokens.listen((t) {
      if (t != null) _broadcast({'type': 'token', 'token': t});
    });
    _theme = settings.themeMode;
    settings.addListener(() {
      if (settings.themeMode == _theme) return;
      _theme = settings.themeMode;
      _broadcast({'type': 'theme', 'mode': settings.themeMode.name});
    });
  }

  /// The student's card in a window of its own (or that window, brought
  /// to the front, if it is open already).
  Future<void> openStudent(Student s) async {
    final token = store.api.accessToken;
    if (!store.signedIn || token == null) {
      store.say("Немає активного входу — оновіть дані (⌘R) і спробуйте ще раз.");
      return;
    }
    final key = 'student-${s.id}';
    settings.rememberWindow(key);
    final spec = WindowSpec(
      key: key,
      studentId: s.id,
      userId: store.me.id,
      profile: store.me.raw,
      accessToken: token,
      themeMode: settings.themeMode.name,
    );
    try {
      await _channel.invokeMethod('open', {
        'key': key,
        'spec': jsonEncode(spec.toJson()),
        'title': '${s.name} — Stemik',
        'width': 760.0,
        'height': 840.0,
      });
    } on PlatformException catch (e) {
      store.say('Не вдалося відкрити вікно: ${e.message}');
    }
  }

  Future<void> closeAll() async {
    try {
      await _channel.invokeMethod('closeAll');
    } on MissingPluginException {
      // No native side (tests).
    }
  }

  /// Signing out: windows go, and what they kept goes with them.
  Future<void> discardAll() async {
    await closeAll();
    if (!store.signedIn) return;
    for (final key in settings.openWindows) {
      await _deleteFiles(key, store.me.id);
      settings.forgetWindow(key);
    }
  }

  /// Windows left open when the app last quit: send what they queued.
  Future<void> adoptLeftovers() async {
    for (final key in settings.openWindows) {
      await _adopt(key);
    }
  }

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'message':
        final m = Map<String, dynamic>.from((call.arguments as Map)['message'] as Map);
        if (m['type'] == 'changed') unawaited(store.sync());
      case 'closed':
        await _adopt(call.arguments as String);
    }
    return null;
  }

  Future<void> _adopt(String key) async {
    if (!store.signedIn) return;
    final uid = store.me.id;
    await store.adoptOutbox(await files.readJson(windowFiles(key, 'outbox_$uid.json')));
    await _deleteFiles(key, uid);
    settings.forgetWindow(key);
  }

  Future<void> _deleteFiles(String key, String uid) async {
    await files.delete(windowFiles(key, 'outbox_$uid.json'));
    await files.delete(windowFiles(key, 'snapshot_$uid.json'));
  }

  Future<void> _broadcast(Map<String, Object?> message) async {
    try {
      await _channel.invokeMethod('broadcast', {'message': message});
    } on MissingPluginException {
      // No native side (tests).
    }
  }
}

/// Where a window keeps [name].
String windowFiles(String key, String name) => 'w_${key}_$name';

/// What a window is opened with (as JSON in its entrypoint arguments).
class WindowSpec {
  const WindowSpec({
    required this.key,
    required this.studentId,
    required this.userId,
    required this.profile,
    required this.accessToken,
    required this.themeMode,
  });
  final String key;
  final String studentId;
  final String userId;
  final Map<String, dynamic> profile;
  final String accessToken;
  final String themeMode;

  factory WindowSpec.fromJson(Map<String, dynamic> j) => WindowSpec(
    key: j['key'] as String,
    studentId: j['studentId'] as String,
    userId: j['userId'] as String,
    profile: Map<String, dynamic>.from(j['profile'] as Map),
    accessToken: j['accessToken'] as String,
    themeMode: j['themeMode'] as String? ?? 'system',
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'studentId': studentId,
    'userId': userId,
    'profile': profile,
    'accessToken': accessToken,
    'themeMode': themeMode,
  };
}

/// A window's files: its own cache and outbox under its own names; until
/// it has saved a cache, the main window's one gives it a head start.
class WindowFiles implements LocalFiles {
  WindowFiles(this.base, this.key);
  final LocalFiles base;
  final String key;

  @override
  Future<Object?> readJson(String name) async {
    final own = await base.readJson(windowFiles(key, name));
    if (own != null || name.startsWith('outbox_')) return own;
    return base.readJson(name);
  }

  @override
  Future<void> writeJson(String name, Object? data) => base.writeJson(windowFiles(key, name), data);

  @override
  Future<void> delete(String name) => base.delete(windowFiles(key, name));

  // Photos are shared: the main window may have to upload one a window took.
  @override
  Future<String> savePhoto(Uint8List bytes) => base.savePhoto(bytes);
  @override
  Future<Uint8List?> readPhoto(String handle) => base.readPhoto(handle);
  @override
  Future<void> deletePhoto(String handle) => base.deletePhoto(handle);
  @override
  ImageProvider photoImage(String handle) => base.photoImage(handle);
}

/// True in an extra window's engine.
bool isExtraWindow = false;

/// The entry point of an extra window's engine.
Future<void> runWindow(String specJson) async {
  WidgetsFlutterBinding.ensureInitialized();
  isExtraWindow = true;
  final spec = WindowSpec.fromJson(Map<String, dynamic>.from(jsonDecode(specJson) as Map));
  await initializeDateFormatting('uk');
  final settings = await Settings.load();
  var token = spec.accessToken;
  await SupabaseApi.initializeForWindow(() async => token);
  final store = AppStore(SupabaseApi(windowUserId: spec.userId), WindowFiles(LocalFiles.create(), spec.key));
  await store.open(Profile(spec.profile));

  const channel = MethodChannel('studio.stemik/window');
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'message':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        switch (m['type']) {
          case 'token':
            token = m['token'] as String;
          case 'changed':
            unawaited(store.sync());
          case 'theme':
            settings.themeMode = ThemeMode.values.asNameMap()[m['mode']] ?? ThemeMode.system;
        }
      case 'willClose':
        await store.shutDown();
        return true;
    }
    return null;
  });
  store.serverWrites.listen((_) => channel.invokeMethod('toMain', {'type': 'changed'}));

  runApp(
    WindowApp(
      store: store,
      settings: settings,
      child: StudentWindow(studentId: spec.studentId, onTitle: (title) => channel.invokeMethod('setTitle', title)),
    ),
  );
}

/// The app around an extra window's content: theme, locale, store.
class WindowApp extends StatelessWidget {
  const WindowApp({super.key, required this.store, required this.settings, required this.child});
  final AppStore store;
  final Settings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) => SettingsScope(
    settings: settings,
    child: StoreScope(
      store: store,
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
          home: child,
        ),
      ),
    ),
  );
}

/// A student's card as a window: the same card as in the app, which keeps
/// the window's title on the student's name, shows the store's messages
/// and reloads when the connection comes back.
class StudentWindow extends StatefulWidget {
  const StudentWindow({super.key, required this.studentId, this.onTitle});
  final String studentId;
  final void Function(String title)? onTitle;

  @override
  State<StudentWindow> createState() => _StudentWindowState();
}

class _StudentWindowState extends State<StudentWindow> {
  StreamSubscription<String>? _messages;
  StreamSubscription<List<ConnectivityResult>>? _net;
  String? _title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.storeRead;
      _messages = store.messages.listen((m) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(m), width: 420));
      });
      try {
        _net = Connectivity().onConnectivityChanged.listen((r) {
          if (r.any((x) => x != ConnectivityResult.none)) store.sync();
        });
      } on MissingPluginException {
        // Tests.
      }
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    _net?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final student = context.store.data.studentById[widget.studentId];
    final title = student == null ? 'Stemik' : '${student.name} — Stemik';
    if (title != _title) {
      _title = title;
      widget.onTitle?.call(title);
    }
    // A Scaffold of its own so snackbars show once, over the whole window.
    return Scaffold(body: StudentCardScreen(studentId: widget.studentId));
  }
}

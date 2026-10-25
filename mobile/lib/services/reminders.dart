import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../data/studio_events.dart';
import '../util/dates.dart';
import 'settings.dart';

/// Local notifications before each lesson, plus a morning summary of the
/// day. Everything is computed on the device from the cached schedule, so
/// it works offline and needs no push server. Re-planned whenever the
/// schedule or the settings change.
///
/// For admins also what colleagues do ([AppStore.othersEvents]), shown as
/// it arrives with the live updates.
class Reminders {
  Reminders(this.store, this.settings);

  final AppStore store;
  final Settings settings;
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  final _studentTaps = StreamController<String>.broadcast();
  var _eventId = 0;
  late final tz.Location _kyiv;

  bool _ready = false;
  String? _plannedSignature;
  Timer? _debounce;

  /// Windows: a desktop app that isn't installed from the Store can't take
  /// back a notification the system has scheduled, so the reminders are
  /// timers in the running app instead.
  final _timers = <Timer>[];
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  /// Lesson ids from tapped notifications.
  Stream<String> get taps => _taps.stream;

  /// Student ids from tapped notifications ("Новий учень").
  Stream<String> get studentTaps => _studentTaps.stream;

  /// A lesson id if the app was opened by tapping a reminder.
  String? launchLessonId;

  static const _studentPayload = 'student:';

  static const _android = AndroidNotificationDetails(
    'lessons',
    'Нагадування про заняття',
    channelDescription: 'Перед кожним заняттям і зранку — план на день',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF5B4FE0),
    category: AndroidNotificationCategory.reminder,
  );
  static const _details = NotificationDetails(
    android: _android,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );
  static const _eventDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'events',
      'Дії колег',
      channelDescription: 'Модель надруковано, новий учень, заняття перенесено чи скасовано',
      importance: Importance.defaultImportance,
      color: Color(0xFF5B4FE0),
      category: AndroidNotificationCategory.status,
    ),
    iOS: DarwinNotificationDetails(threadIdentifier: 'events'),
    macOS: DarwinNotificationDetails(threadIdentifier: 'events'),
  );

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<void> init() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    _kyiv = tz.getLocation(studioTimeZone);
    store.addListener(_schedulePlan);
    settings.addListener(_schedulePlan);
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        // Ask for permission after sign-in, not on the login screen.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Stemik Admin',
          appUserModelId: 'StemikStudio.StemikAdmin',
          // Identifies the app's notification activator (taps); never change.
          guid: 'b79c4640-8466-4e9f-a6d0-376f21952e45',
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id == null || id.isEmpty) return;
        if (id.startsWith(_studentPayload)) {
          _studentTaps.add(id.substring(_studentPayload.length));
        } else {
          _taps.add(id);
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null && !payload.startsWith(_studentPayload)) {
      launchLessonId = payload;
    }
    store.othersEvents.listen(_showEvents);
    _ready = true;
  }

  /// Colleagues' doings. A burst (catching up after the connection was
  /// down) comes as one notification rather than a stack of them.
  Future<void> _showEvents(List<StudioEvent> events) async {
    if (!_ready || !store.isAdmin || !settings.othersEvents) return;
    for (final n in notificationsFor(events)) {
      final e = n.tapTo;
      await _plugin.show(
        // Its own range, away from the planned reminders' ids.
        id: 5000 + _eventId++ % 500,
        title: n.title,
        body: n.body,
        notificationDetails: _eventDetails,
        payload: e?.lessonId ?? (e?.studentId == null ? null : '$_studentPayload${e!.studentId}'),
      );
    }
  }

  /// What [events] show as: each on its own, or more than three as one
  /// summary.
  static List<({String title, String body, StudioEvent? tapTo})> notificationsFor(List<StudioEvent> events) {
    if (events.length <= 3) return [for (final e in events) (title: e.title, body: e.body, tapTo: e)];
    final lines = [for (final e in events.take(4)) '${e.title}: ${e.body}'];
    if (events.length > 4) lines.add('і ще ${events.length - 4}');
    return [
      (title: 'Колеги: ${_plural(events.length, 'зміна', 'зміни', 'змін')}', body: lines.join('\n'), tapTo: null),
    ];
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    if (mac != null) return await mac.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  Future<void> showTest() async {
    if (!_ready) return;
    await requestPermission();
    await _plugin.show(
      id: 1,
      title: 'Нагадування працюють',
      body: 'Ви отримаєте сповіщення за ${settings.reminderLead} хв до заняття.',
      notificationDetails: _details,
    );
  }

  void _schedulePlan() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _plan);
  }

  Future<void> _plan() async {
    if (!_ready) return;
    if (!store.signedIn) {
      _cancelTimers();
      if (_plannedSignature != null) await _plugin.cancelAll();
      _plannedSignature = null;
      return;
    }
    final now = tz.TZDateTime.now(_kyiv);
    final until = now.add(const Duration(days: 14));
    final source = store.isAdmin && settings.remindAllStudio ? store.data.lessons : store.myLessons;
    final lessons = source.where((l) {
      final start = _start(l);
      return start != null && start.isAfter(now) && start.isBefore(until);
    }).toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));

    final lead = settings.reminderLead;
    final signature = [
      settings.remindersEnabled,
      lead,
      settings.dailyDigest,
      for (final l in lessons) '${l.id}${l.date}${l.time}${l.course}${l.room}${l.studentIds.length}',
    ].join('|');
    if (signature == _plannedSignature) return;
    _plannedSignature = signature;

    // Only what's planned: colleagues' notifications already shown stay.
    if (_windows) {
      _cancelTimers();
    } else {
      await _plugin.cancelAllPendingNotifications();
    }
    if (!settings.remindersEnabled) return;

    final mode = _windows ? AndroidScheduleMode.exact : await _scheduleMode();
    var id = 1000;
    // iOS keeps at most 64 pending notifications; stay well under it.
    for (final l in lessons.take(48)) {
      final at = _start(l)!.subtract(Duration(minutes: lead));
      if (!at.isAfter(now)) continue;
      final where = [l.course, l.room].whereType<String>().join(' · ');
      final kids = l.studentIds.length;
      await _schedule(
        id: id++,
        at: at,
        mode: mode,
        title: 'Через $lead хв: ${l.time} ${where.isEmpty ? l.theme : where}',
        body: [l.theme, if (kids > 0) _kids(kids)].join(' · '),
        payload: l.id,
      );
    }

    if (settings.dailyDigest) {
      final byDay = <String, List<Lesson>>{};
      for (final l in lessons) {
        byDay.putIfAbsent(l.date, () => []).add(l);
      }
      var digestId = 100;
      for (final entry in byDay.entries.take(10)) {
        final first = _start(entry.value.first)!;
        final d = parseDate(entry.key);
        var at = tz.TZDateTime(_kyiv, d.year, d.month, d.day, 8);
        // An early first lesson: send the summary an hour before it instead.
        final latest = first.subtract(Duration(minutes: lead + 60));
        if (at.isAfter(latest)) at = latest;
        if (!at.isAfter(now)) continue;
        final n = entry.value.length;
        await _schedule(
          id: digestId++,
          at: at,
          mode: mode,
          title: 'Сьогодні ${_lessons(n)}',
          body: entry.value.map((l) => '${l.time} ${l.course ?? l.theme}').join(', '),
          payload: entry.value.first.id,
        );
      }
    }
  }

  Future<void> _schedule({
    required int id,
    required tz.TZDateTime at,
    required AndroidScheduleMode mode,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (_windows) {
      final wait = at.difference(tz.TZDateTime.now(_kyiv));
      _timers.add(
        Timer(
          wait,
          () => _plugin.show(id: id, title: title, body: body, notificationDetails: _details, payload: payload),
        ),
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: mode,
      title: title,
      body: body,
      payload: payload,
    );
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    return exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  tz.TZDateTime? _start(Lesson l) {
    final m = timeToMinutes(l.time);
    if (m == null) return null;
    final d = parseDate(l.date);
    return tz.TZDateTime(_kyiv, d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  static String _plural(int n, String one, String few, String many) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return '$n $one';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n $few';
    return '$n $many';
  }

  static String _kids(int n) => _plural(n, 'учень', 'учні', 'учнів');
  static String _lessons(int n) => _plural(n, 'заняття', 'заняття', 'занять');
}

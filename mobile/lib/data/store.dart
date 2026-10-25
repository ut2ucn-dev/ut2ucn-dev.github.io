import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:uuid/uuid.dart';

import '../util/dates.dart';
import 'api.dart';
import 'local_files.dart';
import 'models.dart';
import 'outbox.dart';
import 'snapshot.dart';
import 'studio_data.dart';

enum Connection { unknown, online, offline }

/// Holds everything the signed-in person sees and every change they make.
///
/// Reads come from a snapshot of the server's data cached on the device, so
/// the app opens instantly and works without a connection. Day-to-day
/// changes (attendance, print status, work photos, comments) go into an
/// outbox first: they show up on screen at once and are sent to Supabase in
/// order whenever a connection is available. Rarer admin edits (lessons,
/// students, rates, accounts) need a connection and go straight through.
class AppStore extends ChangeNotifier {
  /// [watchLive]: reload whenever anyone changes studio data (admins; see
  /// [live]). Off in the Mac's extra windows, which hear it from the main
  /// window.
  AppStore(this.api, this.files, {this.watchLive = true});

  final StemikApi api;
  final LocalFiles files;
  final bool watchLive;

  Profile? _me;
  Profile get me => _me!;
  bool get signedIn => _me != null;
  bool get isAdmin => _me?.isAdmin ?? false;
  bool get isSuperAdmin => _me?.isSuperAdmin ?? false;

  Snapshot _server = Snapshot.empty;
  final List<PendingOp> _ops = [];

  /// Ops already accepted by the server but not yet reflected in [_server]
  /// (no refresh since). Still applied on top so nothing flickers back.
  final List<PendingOp> _synced = [];

  StudioData _data = StudioData.empty;
  StudioData get data => _data;

  bool _hasData = false;
  bool get hasData => _hasData;
  bool _refreshing = false;
  bool get refreshing => _refreshing;
  Connection _connection = Connection.unknown;
  Connection get connection => _connection;
  DateTime? _lastRefresh;
  DateTime? get lastRefresh => _lastRefresh;
  String? get cachedAt => _server.savedAt;

  int get pendingCount => _ops.length;
  List<PendingOp> get pendingOps => List.unmodifiable(_ops);
  final List<String> rejected = [];

  final _messages = StreamController<String>.broadcast();
  final _serverWrites = StreamController<void>.broadcast();
  final _remoteChanges = StreamController<void>.broadcast();

  /// Fires after the data was reloaded because someone else changed it.
  Stream<void> get remoteChanges => _remoteChanges.stream;

  // --- live updates ---------------------------------------------------------

  LiveWatch? _watch;
  Timer? _liveDebounce;
  bool _live = false;
  bool _wasLive = false;

  /// Changes made by others (the web, phones, other admins) arrive by
  /// themselves: the server says something changed, the store reloads.
  bool get live => _live;

  void _startLive() {
    _stopLive();
    if (!watchLive || !isAdmin) return;
    _watch = api.watchStudio(
      onChange: _changedElsewhere,
      onLive: (live) {
        if (live == _live) return;
        _live = live;
        notifyListeners();
        // Back after a drop: catch up on what happened meanwhile.
        if (live && _wasLive) _changedElsewhere();
        _wasLive |= live;
      },
    );
  }

  void _stopLive() {
    _liveDebounce?.cancel();
    final w = _watch;
    _watch = null;
    if (w != null) unawaited(w.cancel());
    _live = false;
    _wasLive = false;
  }

  /// One reload for a burst of changes (a lesson marked for a whole group
  /// is a dozen events), and always a fresh one: a reload already running
  /// may have read the data before the change.
  void _changedElsewhere() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 1200), () async {
      final running = _syncing;
      if (running != null) await running;
      if (_me == null) return;
      await sync();
      _remoteChanges.add(null);
    });
  }

  /// Fires when this store changed something on the server (sent queued
  /// changes, or an online-only change went through), so other windows
  /// showing the same data can reload.
  Stream<void> get serverWrites => _serverWrites.stream;

  /// Short messages for the user (errors, "saved"); the shell shows them.
  Stream<String> get messages => _messages.stream;
  void say(String message) => _messages.add(message);

  Timer? _retryTimer;
  Timer? _refreshDebounce;
  Future<void>? _syncing;
  bool _flushing = false;

  // --- admin: whose workspace is shown ------------------------------------

  String? _teacherFilter;

  /// For an admin: show only this teacher's lessons (null = whole studio).
  String? get teacherFilter => _teacherFilter;
  set teacherFilter(String? id) {
    _teacherFilter = id;
    notifyListeners();
  }

  /// Lessons the schedule shows: a teacher's own and the ones they cover;
  /// for an admin, the whole studio or the picked teacher's.
  Iterable<Lesson> get scheduleLessons {
    if (!isAdmin) return _data.lessons;
    final f = _teacherFilter;
    return f == null ? _data.lessons : _data.lessons.where((l) => l.ownerId == f);
  }

  /// Lessons whose works and pay belong to the current scope (a substitute
  /// covering a class doesn't take over its prints or pay).
  Iterable<Lesson> get ownedLessons {
    if (isAdmin) return scheduleLessons;
    return _data.lessons.where((l) => l.ownerId == _me?.id);
  }

  /// The signed-in person's own upcoming lessons, for reminders.
  Iterable<Lesson> get myLessons => _data.lessons.where((l) => l.ownerId == _me?.id || l.substituteOwnerId == _me?.id);

  int get pendingPrintCount => _data.queue(ownedLessons, includePrinted: false).length;

  // --- lifecycle ----------------------------------------------------------

  String get _snapshotFile => 'snapshot_${_me!.id}.json';
  String get _outboxFile => 'outbox_${_me!.id}.json';

  /// Called once the profile of the signed-in person is known.
  Future<void> open(Profile me) async {
    if (_me?.id == me.id) {
      _me = me;
      notifyListeners();
      return;
    }
    _me = me;
    _teacherFilter = null;
    _server = Snapshot.fromJson(await files.readJson(_snapshotFile));
    _ops.clear();
    _synced.clear();
    final saved = await files.readJson(_outboxFile);
    if (saved is Map) {
      _ops.addAll(((saved['ops'] as List?) ?? const []).map(PendingOp.fromJson).whereType<PendingOp>());
      _synced.addAll(((saved['synced'] as List?) ?? const []).map(PendingOp.fromJson).whereType<PendingOp>());
    }
    _hasData = !_server.isEmpty;
    _rebuild();
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_ops.isNotEmpty) sync();
    });
    unawaited(sync());
    _startLive();
  }

  /// Forget everything about the signed-in person (sign-out).
  Future<void> close({bool discardPending = true}) async {
    _retryTimer?.cancel();
    _refreshDebounce?.cancel();
    _stopLive();
    if (_me != null && discardPending) {
      for (final op in [..._ops, ..._synced]) {
        if (op.type == OpType.uploadWorkPhoto) await files.deletePhoto(op.data['photoHandle'] as String);
      }
      await files.delete(_snapshotFile);
      await files.delete(_outboxFile);
    }
    _me = null;
    _server = Snapshot.empty;
    _ops.clear();
    _synced.clear();
    _data = StudioData.empty;
    _hasData = false;
    _connection = Connection.unknown;
    rejected.clear();
    notifyListeners();
  }

  /// Takes over changes another window queued and couldn't send (its saved
  /// outbox, as [_saveOutbox] writes it), and sends them from here.
  Future<void> adoptOutbox(Object? saved) async {
    if (_me == null || saved is! Map) return;
    final ops = ((saved['ops'] as List?) ?? const []).map(PendingOp.fromJson).whereType<PendingOp>().toList();
    if (ops.isEmpty) return;
    _ops.addAll(ops);
    await _saveOutbox();
    _rebuild();
    unawaited(sync());
  }

  /// Before a window goes: lets a send in progress finish, stops retrying
  /// and leaves what's still queued saved, for the main window to adopt.
  Future<void> shutDown() async {
    _retryTimer?.cancel();
    _refreshDebounce?.cancel();
    _stopLive();
    try {
      await _syncing;
    } catch (_) {}
    if (_me != null) await _saveOutbox();
  }

  void updateMe(Profile p) {
    _me = p;
    notifyListeners();
  }

  void _rebuild() {
    final view = _server.mutableCopy();
    for (final op in _synced) {
      applyOp(view, op, pending: false);
    }
    for (final op in _ops) {
      applyOp(view, op);
    }
    _data = StudioData.from(view);
    notifyListeners();
  }

  Future<void> _saveOutbox() => files.writeJson(_outboxFile, {
    'ops': _ops.map((o) => o.toJson()).toList(),
    'synced': _synced.map((o) => o.toJson()).toList(),
  });

  // --- syncing ------------------------------------------------------------

  /// Sends pending changes, then reloads everything. Safe to call often:
  /// concurrent calls share one run.
  Future<void> sync() => _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    final reached = await _flush();
    if (reached) await _refresh();
  }

  /// Returns false if the server couldn't be reached.
  Future<bool> _flush() async {
    if (_flushing) return true;
    _flushing = true;
    var reached = true;
    var sent = false;
    try {
      while (_ops.isNotEmpty && _me != null) {
        final op = _ops.first;
        try {
          await executeOp(api, files, op);
          _synced.add(op);
        } on ServerRejected catch (e) {
          // A retried comment insert that already landed the first time.
          final duplicate = op.type == OpType.addComment && e.message.contains('duplicate');
          if (!duplicate) {
            final msg = '${op.describe()}: ${e.message}';
            rejected.insert(0, msg);
            say('Не збережено — $msg');
            if (op.type == OpType.uploadWorkPhoto) await files.deletePhoto(op.data['photoHandle'] as String);
          } else {
            _synced.add(op);
          }
        } catch (_) {
          reached = false;
          break;
        }
        _ops.removeAt(0);
        sent = true;
        await _saveOutbox();
      }
    } finally {
      _flushing = false;
    }
    _setConnection(reached ? Connection.online : Connection.offline);
    if (sent) {
      _rebuild();
      _serverWrites.add(null);
    }
    return reached;
  }

  void _setConnection(Connection c) {
    if (_connection == c) return;
    _connection = c;
    notifyListeners();
  }

  Future<void> _refresh() async {
    final me = _me;
    if (me == null) return;
    _refreshing = true;
    notifyListeners();
    try {
      final admin = me.isAdmin;
      final ownerId = admin ? null : me.id;
      final results = await Future.wait([
        api.fetchProfiles(),
        api.fetchStudents(),
        api.fetchLessons(ownerId: ownerId),
        api.fetchWorks(ownerId: ownerId),
        admin ? api.fetchSubscriptions() : Future.value(<DbRow>[]),
        api.fetchRateCards(),
      ]);
      final lessons = results[2];
      final covered = admin
          ? const <String>[]
          : lessons.where((l) => l['owner_id'] != me.id).map((l) => l['id'] as String).toList();
      final attendance = await api.fetchAttendance(ownerId: ownerId, lessonIds: covered);
      if (_me?.id != me.id) return; // signed out meanwhile

      final mine = results[0].where((p) => p['id'] == me.id).firstOrNull;
      if (mine != null) _me = Profile(mine);

      _server = Snapshot(
        profiles: results[0],
        students: results[1],
        lessons: lessons,
        works: results[3],
        attendance: attendance,
        subscriptions: results[4],
        rateCards: results[5],
        savedAt: DateTime.now().toIso8601String(),
      );
      for (final op in _synced) {
        if (op.type == OpType.uploadWorkPhoto) await files.deletePhoto(op.data['photoHandle'] as String);
      }
      _synced.clear();
      await _saveOutbox();
      await files.writeJson(_snapshotFile, _server.toJson());
      _hasData = true;
      _lastRefresh = DateTime.now();
      _setConnection(Connection.online);
    } on ServerRejected catch (e) {
      say(e.message);
    } catch (_) {
      _setConnection(Connection.offline);
    } finally {
      _refreshing = false;
      _rebuild();
    }
  }

  /// Pull-to-refresh, app resume, connection regained.
  Future<void> refresh() => sync();

  /// Reload a bit after the last local change, so a burst of taps on a
  /// lesson card costs one reload rather than one per tap.
  void _refreshSoon() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(seconds: 3), () => sync());
  }

  Future<void> _enqueue(PendingOp op) async {
    _ops.add(op);
    await _saveOutbox();
    _rebuild();
    final reached = await _flush();
    if (reached) _refreshSoon();
  }

  // --- offline-capable changes --------------------------------------------

  Future<void> markAttendance(
    Lesson lesson,
    Student student,
    String status, {
    String? paymentMethod,
    double discountPercent = 0,
    String? purchaseDate,
    String? purchaseMethod,
  }) => _enqueue(
    PendingOp(OpType.markAttendance, {
      'lessonId': lesson.id,
      'studentId': student.id,
      'status': status,
      'paymentMethod': paymentMethod,
      'discountPercent': discountPercent,
      'purchaseDate': purchaseDate,
      'purchaseMethod': purchaseMethod,
    }),
  );

  Future<void> unmarkAttendance(Lesson lesson, Student student) =>
      _enqueue(PendingOp(OpType.unmarkAttendance, {'lessonId': lesson.id, 'studentId': student.id}));

  Future<void> setAttendancePrint(Lesson lesson, Student student, bool enabled, double? price) => _enqueue(
    PendingOp(OpType.setAttendancePrint, {
      'lessonId': lesson.id,
      'studentId': student.id,
      'enabled': enabled,
      'price': price,
    }),
  );

  /// [printData] — weight_g, print_minutes, printer_id, filament_id
  /// (sql/0019) — goes with marking printed; un-marking keeps whatever was
  /// entered, as on the web.
  Future<void> setPrinted(Lesson lesson, Student student, bool printed, {Map<String, Object?>? printData}) => _enqueue(
    PendingOp(OpType.setWork, {
      'lessonId': lesson.id,
      'studentId': student.id,
      'ownerId': lesson.ownerId,
      'patch': {
        'printed': printed,
        'printed_by_name': printed ? me.fullName : null,
        'printed_at': printed ? DateTime.now().toUtc().toIso8601String() : null,
        ...?printData,
      },
    }),
  );

  /// Corrects the weight, time, printer or filament of a printed model.
  Future<void> setPrintData(Lesson lesson, Student student, Map<String, Object?> printData) => _enqueue(
    PendingOp(OpType.setWork, {
      'lessonId': lesson.id,
      'studentId': student.id,
      'ownerId': lesson.ownerId,
      'patch': printData,
    }),
  );

  // --- printers and filaments to pick from (sql/0019) ---------------------

  List<Printer> _printers = const [];
  List<Filament> _filaments = const [];
  List<Printer> get printers => _printers;
  List<Filament> get filaments => _filaments;
  static const _printDirectoryFile = 'print_directory.json';

  /// Refreshes the lists (kept on the device, so marking a model printed
  /// works offline too).
  Future<void> loadPrintDirectory() async {
    try {
      final (p, f) = (await api.fetchPrinters(), await api.fetchFilaments());
      _printers = p.map(Printer.new).toList();
      _filaments = f.map(Filament.new).toList();
      await files.writeJson(_printDirectoryFile, {'printers': p, 'filaments': f});
    } catch (_) {
      if (_printers.isEmpty && _filaments.isEmpty) {
        final saved = await files.readJson(_printDirectoryFile);
        if (saved is Map) {
          _printers = [
            for (final r in (saved['printers'] as List? ?? const [])) Printer(Map<String, dynamic>.from(r as Map)),
          ];
          _filaments = [
            for (final r in (saved['filaments'] as List? ?? const [])) Filament(Map<String, dynamic>.from(r as Map)),
          ];
        }
      }
    }
    notifyListeners();
  }

  Future<void> setTrial(Lesson lesson, Student student, bool trial) => _enqueue(
    PendingOp(OpType.setWork, {
      'lessonId': lesson.id,
      'studentId': student.id,
      'ownerId': lesson.ownerId,
      'patch': {'trial': trial},
    }),
  );

  /// [jpeg] is already resized/compressed by the picker.
  Future<void> attachWorkPhoto(Lesson lesson, Student student, Uint8List jpeg) async {
    final handle = await files.savePhoto(jpeg);
    await _enqueue(
      PendingOp(OpType.uploadWorkPhoto, {
        'lessonId': lesson.id,
        'studentId': student.id,
        'ownerId': lesson.ownerId,
        'photoHandle': handle,
      }),
    );
  }

  Future<void> setLessonCompleted(Lesson lesson, bool completed) =>
      _enqueue(PendingOp(OpType.setLessonCompleted, {'lessonId': lesson.id, 'completed': completed}));

  Future<void> addComment(String studentId, String body) => _enqueue(
    PendingOp(OpType.addComment, {
      'id': const Uuid().v4(),
      'studentId': studentId,
      'authorId': me.id,
      'body': body,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  List<StudentComment> pendingComments(String studentId) => [
    for (final op in [..._synced, ..._ops].reversed)
      if (op.type == OpType.addComment && op.studentId == studentId)
        StudentComment({
          'id': op.data['id'],
          'student_id': studentId,
          'author_id': op.data['authorId'],
          'body': op.data['body'],
          'created_at': op.data['createdAt'],
          '_pending': _ops.contains(op),
        }),
  ];

  ImageProvider? localPhoto(Work? w) => w?.localPhoto == null ? null : files.photoImage(w!.localPhoto!);

  // --- online-only changes ------------------------------------------------

  /// Runs an online-only change. Returns true on success; on failure tells
  /// the user why and returns false.
  Future<bool> online(Future<void> Function() change, {String? done, bool reload = true}) async {
    try {
      await change();
    } on ServerRejected catch (e) {
      say(e.message);
      return false;
    } catch (_) {
      _setConnection(Connection.offline);
      say("Немає з'єднання з сервером. Ця дія потребує інтернету.");
      return false;
    }
    _setConnection(Connection.online);
    _serverWrites.add(null);
    if (done != null) say(done);
    if (reload) unawaited(sync());
    return true;
  }

  /// Like [online], for reads; returns null on failure.
  Future<T?> fetch<T>(Future<T> Function() read, {bool quiet = false}) async {
    try {
      final v = await read();
      _setConnection(Connection.online);
      return v;
    } on ServerRejected catch (e) {
      if (!quiet) say(e.message);
    } catch (_) {
      _setConnection(Connection.offline);
      if (!quiet) say("Немає з'єднання з сервером.");
    }
    return null;
  }

  /// The student's full history across the studio (not just this
  /// teacher's lessons). Offline, falls back to what's cached.
  Future<StudentPortfolio> portfolio(Student s) async {
    final remote = await fetch(
      () => Future.wait([api.fetchStudentLessons(s.id), api.fetchStudentWorks(s.id), api.fetchStudentAttendance(s.id)]),
      quiet: true,
    );
    if (remote == null) {
      final lessons = _data.lessons.where((l) => l.studentIds.contains(s.id)).toList();
      return StudentPortfolio(
        lessons,
        {for (final l in lessons) l.id: ?_data.work(l.id, s.id)},
        {for (final l in lessons) l.id: ?_data.attendance(l.id, s.id)},
        offline: true,
      );
    }
    final lessons = remote[0].map(Lesson.new).toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return StudentPortfolio(
      lessons,
      {for (final w in remote[1].map(Work.new)) w.lessonId: w},
      {for (final a in remote[2].map(Attendance.new)) a.lessonId: a},
    );
  }

  /// Today's date, for screens that need "now" consistently.
  String get today => todayStr();

  @override
  void dispose() {
    _retryTimer?.cancel();
    _refreshDebounce?.cancel();
    _messages.close();
    _stopLive();
    _serverWrites.close();
    _remoteChanges.close();
    super.dispose();
  }
}

class StudentPortfolio {
  final List<Lesson> lessons;
  final Map<String, Work> workByLesson;
  final Map<String, Attendance> attendanceByLesson;
  final bool offline;
  StudentPortfolio(this.lessons, this.workByLesson, this.attendanceByLesson, {this.offline = false});
}

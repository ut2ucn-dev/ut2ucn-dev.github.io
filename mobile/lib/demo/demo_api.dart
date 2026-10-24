import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../data/api.dart';
import '../util/dates.dart';

/// In-memory stand-in for Supabase with a made-up studio, for previews,
/// screenshots and tests. `--dart-define=STEMIK_DEMO_ROLE=teacher` signs
/// in as a teacher instead of the superadmin.
class DemoApi implements StemikApi {
  DemoApi({String? role, this.offline = false}) {
    _seed(role ?? const String.fromEnvironment('STEMIK_DEMO_ROLE', defaultValue: 'superadmin'));
  }

  /// Simulates having no connection: every call throws.
  bool offline;

  final _uuid = const Uuid();
  final _auth = StreamController<AuthEvent>.broadcast();
  String? _uid;
  late String _meId;

  final profiles = <DbRow>[];
  final students = <DbRow>[];
  final lessons = <DbRow>[];
  final works = <DbRow>[];
  final attendance = <DbRow>[];
  final subscriptions = <DbRow>[];
  final comments = <DbRow>[];
  final rateCards = <DbRow>[];
  String? calcStart;

  Future<T> _io<T>(T Function() f) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (offline) throw Exception('offline');
    return f();
  }

  List<DbRow> _copy(Iterable<DbRow> rows) =>
      rows.map((r) => Map<String, dynamic>.from(jsonDecode(jsonEncode(r)) as Map)).toList();

  void _seed(String role) {
    final rnd = Random(7);
    DbRow profile(String last, String first, String role, {bool active = true}) {
      final r = {
        'id': _uuid.v4(),
        'email': '${first.toLowerCase().hashCode.abs() % 1000}@stemik.studio',
        'last_name': last,
        'first_name': first,
        'role': role,
        'active': active,
        'photo': null,
      };
      profiles.add(r);
      return r;
    }

    final boss = profile('Коваленко', 'Ірина', 'superadmin');
    final admin = profile('Мельник', 'Олег', 'admin');
    final t1 = profile('Шевчук', 'Анна', 'teacher');
    final t2 = profile('Бондар', 'Максим', 'teacher');
    profile('Ткаченко', 'Дарина', 'teacher', active: false);
    _meId = switch (role) {
      'teacher' => t1['id'],
      'admin' => admin['id'],
      _ => boss['id'],
    } as String;
    _uid = _meId;

    const names = [
      'Марійка Петренко',
      'Тимофій Бондаренко',
      'Соломія Іванчук',
      'Назар Петрук',
      'Злата Кравець',
      'Богдан Лисенко',
      'Олеся Гнатюк',
      'Матвій Савчук',
      'Вероніка Мороз',
      'Ярослав Ковальчук',
      'Єва Олійник',
      'Остап Руденко',
      'Аліна Сидоренко',
      'Ілля Поліщук',
      'Христина Марченко',
    ];
    for (final n in names) {
      final parts = n.split(' ');
      students.add({
        'id': _uuid.v4(),
        'owner_id': t1['id'],
        'name': n,
        'phone':
            '+380 ${50 + rnd.nextInt(49)} ${100 + rnd.nextInt(899)} ${10 + rnd.nextInt(89)} ${10 + rnd.nextInt(89)}',
        'birthday': '20${14 + rnd.nextInt(6)}-0${1 + rnd.nextInt(9)}-1${rnd.nextInt(9)}',
        'parent_last_name': parts.last,
        'parent_first_name': ['Олена', 'Андрій', 'Наталія', 'Сергій'][rnd.nextInt(4)],
        'notes': null,
        'photo': null,
      });
    }

    for (final course in const [
      '3D Tinkercad FIRST (9-12)',
      '3D Tinkercad PRO (9-12)',
      '3D Makers FIRST (6-8)',
      '3D Makers PRO (6-8)',
      'VR ІГРОВИЙ',
      'VR РОЗРОБКА (Delightex)',
      'Robo AI (Ukit 6-8)',
      'Robo AI (UGot 9-12)',
      '3D слайсинг',
    ]) {
      rateCards.add({
        'course': course,
        'zp_group_1': 250,
        'zp_group_2_6': 400,
        'zp_individual': 350,
        'zp_individual_online': 300,
        'zp_group_online': 350,
        'zp_extra_service': 100,
        'price_group_1': 450,
        'price_group_2_6': 400,
        'price_individual': 700,
        'price_individual_online': 550,
        'price_group_online': 350,
        'price_extra_service': 150,
        'price_print_online': null,
        'price_sub_group': 1400,
        'price_sub_individual': 2600,
        'price_sub_individual_online': 2000,
        'price_sub_group_online': 1200,
      });
    }

    const plan = [
      ('10:00', 90, '3D Makers PRO (6-8)', 'Друк брелока з ініціалами', 'Клас 3D', 'group'),
      ('12:00', 60, 'VR ІГРОВИЙ', 'Перша гра в шоломі', 'Клас VR', 'group'),
      ('14:00', 60, 'Robo AI (Ukit 6-8)', 'Робот-сортувальник', 'Клас AI', 'group'),
      ('16:30', 60, '3D Tinkercad PRO (9-12)', 'Модель кімнати мрії', "Комп'ютерний клас", 'individual'),
      ('18:00', 60, '3D Tinkercad FIRST (9-12)', 'Підставка для телефона', null, 'individual_online'),
    ];
    final today = DateTime.now();
    for (var day = -10; day <= 10; day++) {
      final d = DateTime(today.year, today.month, today.day + day);
      if (d.weekday == DateTime.sunday) continue;
      for (var i = 0; i < plan.length; i++) {
        if ((day + i) % 3 == 0) continue;
        final (time, dur, course, theme, room, format) = plan[i];
        final owner = i.isEven ? t1 : t2;
        final count = format.startsWith('individual') ? 1 : 2 + rnd.nextInt(4);
        final ids = (students.map((s) => s['id'] as String).toList()..shuffle(rnd)).take(count).toList();
        final lesson = {
          'id': _uuid.v4(),
          'owner_id': owner['id'],
          'date': isoDate(d),
          'time': '$time:00',
          'theme': theme,
          'course': course,
          'format': format,
          'student_ids': ids,
          'extra_service': false,
          'series_id': null,
          'duration_minutes': dur,
          'room': room,
          'substitute_owner_id': (day == 1 && i == 2) ? t1['id'] : null,
          'completed': day < 0,
          'payroll_amount': 0,
          'price_amount': 0,
        };
        _price(lesson);
        lessons.add(lesson);
        if (day <= 0) {
          for (final sid in ids) {
            final status = rnd.nextInt(10) < 8 ? 'present' : (rnd.nextBool() ? 'absent' : 'excused');
            if (day == 0 && rnd.nextBool()) continue;
            final pm = status != 'present' ? null : ['card', 'cash', null, 'card'][rnd.nextInt(4)];
            attendance.add({
              'id': _uuid.v4(),
              'lesson_id': lesson['id'],
              'student_id': sid,
              'owner_id': owner['id'],
              'status': status,
              'payment_method': pm,
              'amount': pm == null ? 0 : lesson['price_amount'],
              'discount_percent': 0,
              'subscription_id': null,
              'print_enabled': false,
              'print_price': null,
            });
            if (status == 'present' && course.startsWith('3D') && day < -2) {
              works.add({
                'id': _uuid.v4(),
                'owner_id': owner['id'],
                'lesson_id': lesson['id'],
                'student_id': sid,
                'photo': null,
                'printed': rnd.nextInt(3) > 0,
                'printed_by_name': 'Анна Шевчук',
                'trial': false,
              });
            }
          }
        }
      }
    }
    subscriptions.add({
      'id': _uuid.v4(),
      'student_id': students.first['id'],
      'course': '3D Makers PRO (6-8)',
      'total_lessons': 4,
      'remaining_lessons': 2,
      'total_price': 1400,
      'purchased_at': '${addDays(todayStr(), -14)}T00:00:00Z',
      'payment_method': 'card',
      'status': 'active',
    });
    comments.add({
      'id': _uuid.v4(),
      'student_id': students.first['id'],
      'author_id': t1['id'],
      'body': 'Дуже захоплюється 3D-друком, хоче наступного разу надрукувати динозавра.',
      'created_at': DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String(),
    });
  }

  bool get _isAdmin => ['admin', 'superadmin'].contains(profiles.firstWhere((p) => p['id'] == _meId)['role']);

  void _price(DbRow l) {
    final rc = rateCards.firstWhere((r) => r['course'] == l['course'], orElse: () => {});
    final n = (l['student_ids'] as List).length;
    final f = l['format'] as String;
    final bucket = f == 'group' ? (n <= 1 ? 'group_1' : 'group_2_6') : f;
    final extra = l['extra_service'] == true;
    l['payroll_amount'] = ((rc['zp_$bucket'] as num?) ?? 0) + (extra ? (rc['zp_extra_service'] as num? ?? 0) : 0);
    l['price_amount'] = ((rc['price_$bucket'] as num?) ?? 0) + (extra ? (rc['price_extra_service'] as num? ?? 0) : 0);
  }

  DbRow _safeLesson(DbRow l) => _isAdmin ? l : ({...l}..['price_amount'] = null);

  // --- auth ---------------------------------------------------------------

  @override
  String? get currentUserId => _uid;

  @override
  Stream<AuthEvent> get authEvents => _auth.stream;

  @override
  Future<void> signIn(String email, String password) => _io(() {
    if (password.length < 3) throw ServerRejected('Invalid login credentials');
    _uid = _meId;
    _auth.add(AuthEvent.signedIn);
  });

  @override
  Future<void> sendPasswordReset(String email) => _io(() {});

  @override
  Future<void> updatePassword(String password) => _io(() {});

  @override
  Future<void> signOut() async {
    _uid = null;
    _auth.add(AuthEvent.signedOut);
  }

  // --- reads --------------------------------------------------------------

  @override
  Future<DbRow?> fetchProfile(String id) => _io(() => _copy(profiles.where((p) => p['id'] == id)).firstOrNull);

  @override
  Future<List<DbRow>> fetchProfiles() => _io(() => _copy(profiles));

  @override
  Future<List<DbRow>> fetchStudents() => _io(() => _copy(students));

  @override
  Future<List<DbRow>> fetchLessons({String? ownerId}) => _io(
    () => _copy(
      lessons
          .where((l) => ownerId == null || l['owner_id'] == ownerId || l['substitute_owner_id'] == ownerId)
          .map(_safeLesson),
    ),
  );

  @override
  Future<List<DbRow>> fetchWorks({String? ownerId}) =>
      _io(() => _copy(works.where((w) => ownerId == null || w['owner_id'] == ownerId)));

  @override
  Future<List<DbRow>> fetchAttendance({String? ownerId, List<String> lessonIds = const []}) => _io(
    () => _copy(
      attendance.where((a) => ownerId == null || a['owner_id'] == ownerId || lessonIds.contains(a['lesson_id'])),
    ),
  );

  @override
  Future<List<DbRow>> fetchSubscriptions({String? studentId}) =>
      _io(() => _copy(subscriptions.where((s) => studentId == null || s['student_id'] == studentId)));

  @override
  Future<List<DbRow>> fetchRateCards() => _io(
    () => _copy(
      rateCards.map(
        (r) => _isAdmin ? r : {for (final e in r.entries) e.key: e.key.startsWith('price_') ? null : e.value},
      ),
    ),
  );

  @override
  Future<List<DbRow>> fetchComments(String studentId) => _io(
    () =>
        _copy(comments.where((c) => c['student_id'] == studentId))
          ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String)),
  );

  @override
  Future<List<DbRow>> fetchStudentLessons(String studentId) =>
      _io(() => _copy(lessons.where((l) => (l['student_ids'] as List).contains(studentId)).map(_safeLesson)));

  @override
  Future<List<DbRow>> fetchStudentWorks(String studentId) =>
      _io(() => _copy(works.where((w) => w['student_id'] == studentId)));

  @override
  Future<List<DbRow>> fetchStudentAttendance(String studentId) =>
      _io(() => _copy(attendance.where((a) => a['student_id'] == studentId)));

  @override
  Future<String?> fetchCalcStartDate() => _io(() => calcStart);

  @override
  Future<DbRow?> fetchReportSummary(String from, String to) => _io(() {
    bool inRange(DbRow a) {
      final l = lessons.firstWhere((x) => x['id'] == a['lesson_id']);
      final d = l['date'] as String;
      return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
    }

    final paid = attendance.where((a) => a['status'] == 'present' && a['payment_method'] != null && inRange(a));
    final debt = attendance.where((a) => a['status'] == 'present' && a['payment_method'] == null && inRange(a));
    return {
      'paid_total': paid.fold<num>(0, (s, a) => s + (a['amount'] as num)),
      'paid_count': paid.length,
      'debt_total': debt.length * 400,
      'debt_count': debt.length,
      'unused_subscription_lessons': subscriptions.fold<num>(0, (s, x) => s + (x['remaining_lessons'] as num)),
      'unused_excused_count': 0,
    };
  });

  @override
  Future<List<DbRow>> fetchReportView(String view, {String? from, String? to, required String orderBy}) => _io(() {
    DbRow withLesson(DbRow a) {
      final l = lessons.firstWhere((x) => x['id'] == a['lesson_id']);
      final s = students.firstWhere((x) => x['id'] == a['student_id']);
      return {
        ...a,
        'lesson_date': l['date'],
        'course': l['course'],
        'price_amount': l['price_amount'],
        'student_name': s['name'],
      };
    }

    switch (view) {
      case 'report_paid':
        return attendance
            .where((a) => a['status'] == 'present' && a['payment_method'] != null)
            .map(withLesson)
            .toList();
      case 'report_debt':
        return attendance
            .where((a) => a['status'] == 'present' && a['payment_method'] == null)
            .map(withLesson)
            .toList();
      case 'report_unused_subscriptions':
        return [
          for (final s in subscriptions)
            {
              ...s,
              'subscription_id': s['id'],
              'student_name': students.firstWhere((x) => x['id'] == s['student_id'])['name'],
            },
        ];
      default:
        return <DbRow>[];
    }
  });

  // --- writes -------------------------------------------------------------

  @override
  Future<void> markAttendance({
    required String lessonId,
    required String studentId,
    required String status,
    String? paymentMethod,
    double discountPercent = 0,
    String? purchaseDate,
    String? purchaseMethod,
  }) => _io(() {
    final l = lessons.firstWhere((x) => x['id'] == lessonId);
    final existing = attendance.where((a) => a['lesson_id'] == lessonId && a['student_id'] == studentId).firstOrNull;
    final present = status == 'present';
    var amount = present ? (l['price_amount'] as num).toDouble() : 0.0;
    if (present && existing?['print_enabled'] == true) amount += (existing?['print_price'] as num?) ?? 100;
    if (present && paymentMethod == 'subscription') amount = 350;
    amount = amount * (1 - discountPercent / 100);
    final row = {
      ...?existing,
      'id': existing?['id'] ?? _uuid.v4(),
      'lesson_id': lessonId,
      'student_id': studentId,
      'owner_id': l['owner_id'],
      'status': status,
      'payment_method': present ? paymentMethod : null,
      'amount': amount,
      'discount_percent': present ? discountPercent : 0,
      'print_enabled': existing?['print_enabled'] ?? false,
      'print_price': existing?['print_price'],
    };
    attendance.removeWhere((a) => a['lesson_id'] == lessonId && a['student_id'] == studentId);
    attendance.add(row);
  });

  @override
  Future<void> unmarkAttendance(String lessonId, String studentId) =>
      _io(() => attendance.removeWhere((a) => a['lesson_id'] == lessonId && a['student_id'] == studentId));

  @override
  Future<void> setAttendancePrint(String lessonId, String studentId, bool enabled, double? price) => _io(() {
    final a = attendance.where((a) => a['lesson_id'] == lessonId && a['student_id'] == studentId).firstOrNull;
    if (a == null || a['status'] != 'present') throw ServerRejected('Спочатку позначте учня присутнім (П)');
    a['print_enabled'] = enabled;
    a['print_price'] = enabled ? price : null;
  });

  @override
  Future<void> upsertWork(String lessonId, String studentId, String ownerId, DbRow patch) => _io(() {
    final w = works.where((w) => w['lesson_id'] == lessonId && w['student_id'] == studentId).firstOrNull;
    if (w != null) {
      w.addAll(patch);
    } else {
      works.add({
        'id': _uuid.v4(),
        'owner_id': ownerId,
        'lesson_id': lessonId,
        'student_id': studentId,
        'printed': false,
        ...patch,
      });
    }
  });

  @override
  Future<String> uploadPhoto(String bucket, String path, Uint8List bytes) =>
      _io(() => 'data:image/jpeg;base64,${base64Encode(bytes)}');

  @override
  Future<void> updateLesson(String id, DbRow patch) => _io(() {
    final l = lessons.firstWhere((x) => x['id'] == id);
    l.addAll(patch);
    _price(l);
  });

  @override
  Future<void> insertComment(DbRow row) => _io(() => comments.add({...row}));

  @override
  Future<void> insertLessons(List<DbRow> rows) => _io(() {
    for (final r in rows) {
      final l = {'id': _uuid.v4(), 'completed': false, 'substitute_owner_id': null, ...r};
      _price(l);
      lessons.add(l);
    }
  });

  @override
  Future<void> deleteLesson(String id) => _io(() => lessons.removeWhere((l) => l['id'] == id));

  @override
  Future<void> deleteLessonSeries(String seriesId, String fromDate) => _io(
    () => lessons.removeWhere((l) => l['series_id'] == seriesId && (l['date'] as String).compareTo(fromDate) >= 0),
  );

  @override
  Future<void> reassignLessonOwner(String lessonId, String ownerId) => _io(() {
    for (final r in [...works, ...attendance]) {
      if (r['lesson_id'] == lessonId) r['owner_id'] = ownerId;
    }
  });

  @override
  Future<DbRow> saveStudent(DbRow payload, {String? id}) => _io(() {
    if (id != null) {
      final s = students.firstWhere((x) => x['id'] == id)..addAll(payload);
      return {...s};
    }
    final s = {'id': _uuid.v4(), ...payload};
    students.add(s);
    return {...s};
  });

  @override
  Future<void> insertStudents(List<DbRow> rows) =>
      _io(() => students.addAll(rows.map((r) => {'id': _uuid.v4(), ...r})));

  @override
  Future<void> deleteStudent(String id) => _io(() => students.removeWhere((s) => s['id'] == id));

  @override
  Future<void> updateSubscription(String id, DbRow patch) =>
      _io(() => subscriptions.firstWhere((s) => s['id'] == id).addAll(patch));

  @override
  Future<void> updateProfile(String id, DbRow patch) =>
      _io(() => profiles.firstWhere((p) => p['id'] == id).addAll(patch));

  @override
  Future<void> upsertRateCards(List<DbRow> rows) => _io(() {
    for (final r in rows) {
      rateCards.removeWhere((x) => x['course'] == r['course']);
      rateCards.add(r);
    }
  });

  @override
  Future<void> setCalcStartDate(String? date) => _io(() => calcStart = date);

  @override
  Future<DbRow> callFunction(String name, DbRow body) => _io(() {
    if (name == 'reset-password') return {'password': 'Stemik-${1000 + Random().nextInt(9000)}'};
    profiles.add({
      'id': _uuid.v4(),
      'email': body['email'],
      'last_name': body['last_name'],
      'first_name': body['first_name'],
      'role': 'teacher',
      'active': true,
    });
    return <String, dynamic>{};
  });
}

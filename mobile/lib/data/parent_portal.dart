// The parents' portal (sql/0018, client/index.html on the web). Parents are
// not Supabase Auth users: parent_login() hands out a session token and
// parent_portal(token) returns everything for that parent's children as
// one JSON document. These classes wrap that document; [PortalSummary] is
// the same arithmetic as summarize() in client/index.html.

import '../util/domain.dart';

double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _rows(Object? v) =>
    ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// What parent_login() returns on success.
class ParentSession {
  final String token;
  final String? name;
  final String phone;
  const ParentSession({required this.token, this.name, required this.phone});
}

class ParentPortal {
  final Map<String, dynamic> raw;
  ParentPortal(this.raw);

  Map<String, dynamic> get _parent => Map<String, dynamic>.from((raw['parent'] as Map?) ?? const {});
  String? get parentName => _str(_parent['name']);
  String get parentPhone => (_parent['phone'] as String?) ?? '';

  /// Studio-local date the server computed the document on.
  String get today => (raw['today'] as String?) ?? '';
  bool get paymentsEnabled => raw['payments_enabled'] == true;

  late final List<PortalStudent> students = _rows(raw['students']).map(PortalStudent.new).toList();
}

class PortalStudent {
  final Map<String, dynamic> raw;
  PortalStudent(this.raw);

  String get id => raw['id'] as String;
  String get name => (raw['name'] as String?) ?? '';
  String? get photo => _str(raw['photo']);
  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  late final List<PortalLesson> lessons = _rows(raw['lessons']).map(PortalLesson.new).toList();
  late final List<PortalWork> works = _rows(raw['works']).map(PortalWork.new).toList();
  late final List<PortalSubscription> subscriptions = _rows(raw['subscriptions']).map(PortalSubscription.new).toList();
}

enum LessonState { upcoming, unmarked, absent, excused, paid, unpaid }

class PortalLesson {
  final Map<String, dynamic> raw;
  PortalLesson(this.raw);

  String get id => raw['id'] as String;
  String get date => raw['date'] as String;
  String? get time {
    final t = raw['time'] as String?;
    if (t == null || t.isEmpty) return null;
    return t.length > 5 ? t.substring(0, 5) : t;
  }

  String? get course => _str(raw['course']);
  String get format => (raw['format'] as String?) ?? 'group';
  String? get theme => _str(raw['theme']);
  String? get room => _str(raw['room']);
  String? get teacher => _str(raw['teacher']);
  String? get status => raw['status'] as String?;
  String? get paymentMethod => raw['payment_method'] as String?;
  double? get amount => _num(raw['amount']);

  /// Owed for a lesson attended and not paid (price + this child's print).
  double? get due => _num(raw['due']);
  bool get printEnabled => raw['print_enabled'] == true;
  bool get trial => raw['trial'] == true;

  String get sortKey => '$date${time ?? ''}';

  LessonState state(String today) {
    switch (status) {
      case null:
        return date.compareTo(today) >= 0 ? LessonState.upcoming : LessonState.unmarked;
      case 'absent':
        return LessonState.absent;
      case 'excused':
        return LessonState.excused;
      default:
        return paymentMethod != null ? LessonState.paid : LessonState.unpaid;
    }
  }
}

class PortalWork {
  final Map<String, dynamic> raw;
  PortalWork(this.raw);

  String get lessonId => raw['lesson_id'] as String;
  String get date => raw['date'] as String;
  String? get course => _str(raw['course']);
  String get format => (raw['format'] as String?) ?? 'group';
  String? get theme => _str(raw['theme']);
  String? get photo => _str(raw['photo']);
  bool get printed => raw['printed'] == true;
  bool get trial => raw['trial'] == true;
  bool get printEnabled => raw['print_enabled'] == true;

  /// Same rule as lessonPrintsFor(): 3D courses, and online lessons only
  /// when printing was ticked for this child.
  bool get prints => courseHasPrinting(course) && (!isOnlineFormat(format) || printEnabled);
}

class PortalSubscription {
  final Map<String, dynamic> raw;
  PortalSubscription(this.raw);

  String get id => raw['id'] as String;
  String get course => (raw['course'] as String?) ?? '';
  int get totalLessons => (raw['total_lessons'] as num?)?.toInt() ?? 4;
  int get remainingLessons => (raw['remaining_lessons'] as num?)?.toInt() ?? 0;
  double get totalPrice => _num(raw['total_price']) ?? 0;
  String get status => (raw['status'] as String?) ?? 'active';
  String get purchaseDate {
    final s = (raw['purchased_at'] as String?) ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  bool get isActive => status == 'active' && remainingLessons > 0;
}

class CourseProgress {
  final String course;
  int total = 0;
  int attended = 0;
  String first;
  String last;
  final Set<String> formats = {};
  PortalLesson? next;
  CourseProgress(this.course, String date) : first = date, last = date;
}

/// Everything the portal's screens show, derived once per child.
class PortalSummary {
  PortalSummary(this.student, this.today) {
    lessons = [...student.lessons]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    attended = lessons.where((l) => l.status == 'present').toList();
    upcoming = lessons.where((l) => l.state(today) == LessonState.upcoming).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    unpaid = attended.where((l) => l.paymentMethod == null).toList();
    due = unpaid.fold(0.0, (s, l) => s + (l.due ?? 0));
    certificates = attended.where((l) => l.paymentMethod == 'certificate').toList();
    trials = lessons.where((l) => l.trial).toList();
    activeSubscriptions = student.subscriptions.where((s) => s.isActive).toList();
    models = student.works.where((w) => w.photo != null || courseHasPrinting(w.course)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final byCourse = <String, CourseProgress>{};
    for (final l in lessons) {
      final key = l.course ?? 'Інше';
      final c = byCourse.putIfAbsent(key, () => CourseProgress(key, l.date));
      c.total++;
      if (l.status == 'present') c.attended++;
      if (l.date.compareTo(c.first) < 0) c.first = l.date;
      if (l.date.compareTo(c.last) > 0) c.last = l.date;
      c.formats.add(l.format);
    }
    for (final l in upcoming) {
      final c = byCourse[l.course ?? 'Інше'];
      if (c != null) c.next ??= l;
    }
    courses = byCourse.values.toList()..sort((a, b) => b.last.compareTo(a.last));
  }

  final PortalStudent student;
  final String today;
  late final List<PortalLesson> lessons;
  late final List<PortalLesson> attended;
  late final List<PortalLesson> upcoming;
  late final List<PortalLesson> unpaid;
  late final double due;
  late final List<PortalLesson> certificates;
  late final List<PortalLesson> trials;
  late final List<PortalSubscription> activeSubscriptions;
  late final List<PortalWork> models;
  late final List<CourseProgress> courses;

  int get paidCount => attended.length - unpaid.length;
  int get printedModels => models.where((w) => w.printed).length;

  /// Level by lessons attended, as levelOf() in client/index.html.
  PortalLevel get level {
    var i = 0;
    while (i + 1 < portalLevels.length && attended.length >= portalLevels[i + 1].$1) {
      i++;
    }
    final next = i + 1 < portalLevels.length ? portalLevels[i + 1] : null;
    final from = portalLevels[i].$1;
    return PortalLevel(
      number: i + 1,
      name: portalLevels[i].$2,
      nextName: next?.$2,
      toNext: next == null ? 0 : next.$1 - attended.length,
      progress: next == null ? 1 : (attended.length - from) / (next.$1 - from),
    );
  }

  /// The same badges as achievementsOf() in client/index.html.
  List<Achievement> get achievements => [
    Achievement('🚀', 'Перший старт', 'Перше заняття в студії', attended.length, 1),
    Achievement('🧊', 'Перша модель', 'Створив(-ла) свою модель', models.length, 1),
    Achievement('🖨️', 'Друкар', 'Модель надруковано на 3D-принтері', printedModels, 1),
    Achievement('🔥', 'У ритмі', '5 відвіданих занять', attended.length, 5),
    Achievement('🏅', 'Десятка', '10 відвіданих занять', attended.length, 10),
    Achievement('🎨', 'Колекціонер', '5 власних моделей', models.length, 5),
    Achievement('🧭', 'Мультитул', 'Заняття у двох напрямах', courses.length, 2),
    Achievement('🏆', 'Чемпіон', '25 відвіданих занять', attended.length, 25),
  ];
  int get lessonsLeftInSubscriptions => activeSubscriptions.fold(0, (s, x) => s + x.remainingLessons);
}

/// (lessons attended to reach it, name) — the portal's game layer.
const portalLevels = [
  (0, 'Новачок'),
  (4, 'Дослідник'),
  (8, 'Конструктор'),
  (16, 'Інженер'),
  (32, 'Винахідник'),
  (64, 'Майстер Stemik'),
];

class PortalLevel {
  final int number;
  final String name;
  final String? nextName;
  final int toNext;
  final double progress;
  const PortalLevel({
    required this.number,
    required this.name,
    required this.nextName,
    required this.toNext,
    required this.progress,
  });
}

class Achievement {
  final String emoji, title, description;
  final int have, need;
  const Achievement(this.emoji, this.title, this.description, this.have, this.need);
  bool get unlocked => have >= need;
}

/// Thrown when the token is no longer valid (expired, signed out
/// elsewhere, password reset, account switched off).
class ParentSessionExpired implements Exception {
  @override
  String toString() => 'Сесія завершилась — увійдіть знову';
}

/// The parents' side of the backend. [SupabaseParentApi] is the real one;
/// the demo build uses an in-memory fake.
abstract class ParentApi {
  /// Throws [ParentLoginFailed] with a message to show for a wrong
  /// password / locked account; anything else means no connection.
  Future<ParentSession> login(String phone, String password);
  Future<ParentPortal> fetchPortal(String token);
  Future<void> logout(String token);
}

class ParentLoginFailed implements Exception {
  final String message;
  ParentLoginFailed(this.message);
  @override
  String toString() => message;
}

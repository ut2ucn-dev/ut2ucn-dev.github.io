import 'api.dart';

/// The data one signed-in person works with, as raw rows. The store keeps
/// two of these: what the server last returned (cached on disk), and the
/// same with the not-yet-synced local changes applied on top.
class Snapshot {
  final List<DbRow> profiles;
  final List<DbRow> students;
  final List<DbRow> lessons;
  final List<DbRow> works;
  final List<DbRow> attendance;
  final List<DbRow> subscriptions;
  final List<DbRow> rateCards;
  final String? savedAt;

  const Snapshot({
    this.profiles = const [],
    this.students = const [],
    this.lessons = const [],
    this.works = const [],
    this.attendance = const [],
    this.subscriptions = const [],
    this.rateCards = const [],
    this.savedAt,
  });

  static const empty = Snapshot();

  bool get isEmpty => lessons.isEmpty && students.isEmpty && profiles.isEmpty;

  /// A copy whose lists can be changed without touching this one. The rows
  /// themselves are shared — callers replace a row rather than mutate it.
  Snapshot mutableCopy() => Snapshot(
    profiles: [...profiles],
    students: [...students],
    lessons: [...lessons],
    works: [...works],
    attendance: [...attendance],
    subscriptions: [...subscriptions],
    rateCards: [...rateCards],
    savedAt: savedAt,
  );

  Map<String, dynamic> toJson() => {
    'profiles': profiles,
    'students': students,
    'lessons': lessons,
    'works': works,
    'attendance': attendance,
    'subscriptions': subscriptions,
    'rateCards': rateCards,
    'savedAt': savedAt,
  };

  static Snapshot fromJson(Object? json) {
    if (json is! Map) return empty;
    List<DbRow> rows(String k) =>
        ((json[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Snapshot(
      profiles: rows('profiles'),
      students: rows('students'),
      lessons: rows('lessons'),
      works: rows('works'),
      attendance: rows('attendance'),
      subscriptions: rows('subscriptions'),
      rateCards: rows('rateCards'),
      savedAt: json['savedAt'] as String?,
    );
  }
}

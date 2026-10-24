import '../util/dates.dart';
import '../util/domain.dart';
import '../util/text.dart';
import 'models.dart';
import 'snapshot.dart';

String _key(String lessonId, String studentId) => '$lessonId|$studentId';

/// Typed, indexed view of a [Snapshot] for the screens to read from.
class StudioData {
  final List<Profile> profiles;
  final Map<String, Profile> profileById;
  final List<Student> students;
  final Map<String, Student> studentById;
  final List<Lesson> lessons;
  final Map<String, Lesson> lessonById;
  final Map<String, Attendance> _attendance;
  final Map<String, Work> _works;
  final List<Subscription> subscriptions;
  final Map<String, RateCard> rateCardByCourse;

  StudioData._(
    this.profiles,
    this.profileById,
    this.students,
    this.studentById,
    this.lessons,
    this.lessonById,
    this._attendance,
    this._works,
    this.subscriptions,
    this.rateCardByCourse,
  );

  factory StudioData.from(Snapshot s) {
    final profiles = s.profiles.map(Profile.new).toList()..sort((a, b) => ukCompare(a.fullName, b.fullName));
    final students = s.students.map(Student.new).toList()..sort((a, b) => ukCompare(a.name, b.name));
    final lessons = s.lessons.map(Lesson.new).toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return StudioData._(
      profiles,
      {for (final p in profiles) p.id: p},
      students,
      {for (final st in students) st.id: st},
      lessons,
      {for (final l in lessons) l.id: l},
      {for (final r in s.attendance.map(Attendance.new)) _key(r.lessonId, r.studentId): r},
      {for (final r in s.works.map(Work.new)) _key(r.lessonId, r.studentId): r},
      s.subscriptions.map(Subscription.new).toList(),
      {for (final r in s.rateCards.map(RateCard.new)) r.course: r},
    );
  }

  static final empty = StudioData.from(Snapshot.empty);

  Attendance? attendance(String lessonId, String studentId) => _attendance[_key(lessonId, studentId)];
  Work? work(String lessonId, String studentId) => _works[_key(lessonId, studentId)];

  Subscription? activeSubscription(String studentId, String? course) {
    for (final s in subscriptions) {
      if (s.studentId == studentId && s.course == course && s.status == 'active' && s.remainingLessons > 0) {
        return s;
      }
    }
    return null;
  }

  /// Students on the lesson's roster that still exist.
  List<Student> roster(Lesson l) => l.studentIds.map((id) => studentById[id]).whereType<Student>().toList();

  /// Children marked "П" whose work goes to the printer.
  List<Student> printable(Lesson l) => roster(l).where((s) {
    final att = attendance(l.id, s.id);
    return att != null && att.isPresent && lessonPrintsFor(l, att);
  }).toList();

  int printedCount(Lesson l) => printable(l).where((s) => work(l.id, s.id)?.printed ?? false).length;

  /// Lessons the given student has had in [course] (for "Пробне").
  int lessonsInCourse(String studentId, String? course) =>
      lessons.where((l) => l.course == course && l.studentIds.contains(studentId)).length;

  /// One row per child whose model is waiting to be (or has been) printed,
  /// newest lesson first — the same rules as QueueTab in index.html.
  List<QueueRow> queue(Iterable<Lesson> scope, {required bool includePrinted}) {
    final today = todayStr();
    final rows = <QueueRow>[];
    for (final l in scope) {
      if (!courseHasPrinting(l.course) || l.date.compareTo(today) > 0) continue;
      for (final sid in l.studentIds) {
        final st = studentById[sid];
        if (st == null) continue;
        final att = attendance(l.id, sid);
        if (att == null || !att.isPresent || !lessonPrintsFor(l, att)) continue;
        final w = work(l.id, sid);
        if (!includePrinted && (w?.printed ?? false)) continue;
        rows.add(QueueRow(l, st, w, att));
      }
    }
    rows.sort((a, b) => b.lesson.sortKey.compareTo(a.lesson.sortKey));
    return rows;
  }
}

class QueueRow {
  final Lesson lesson;
  final Student student;
  final Work? work;
  final Attendance attendance;
  QueueRow(this.lesson, this.student, this.work, this.attendance);
}

import '../util/dates.dart';
import 'models.dart';
import 'studio_data.dart';

/// Something a colleague did that the admin may want to hear about.
class StudioEvent {
  const StudioEvent(this.title, this.body, {this.lessonId, this.studentId});

  final String title;
  final String body;

  /// What a tap on the notification opens.
  final String? lessonId;
  final String? studentId;

  @override
  String toString() => '$title: $body';
}

/// What others changed between two loads of the studio's data: a model
/// printed, a student added, a lesson from today on moved or cancelled.
/// Only for changes that came from elsewhere — the store's own writes are
/// already in [before]. Models marked printed under [me]'s name (from the
/// web or another window) aren't anybody else's.
List<StudioEvent> findOthersEvents(StudioData before, StudioData after, {required Profile me, required DateTime now}) {
  if (identical(before, after)) return const [];
  final today = isoDate(now);
  final events = <StudioEvent>[];

  String what(Lesson l) => l.course ?? (l.theme.isEmpty ? 'Заняття' : l.theme);
  String when(Lesson l) {
    final d = parseDate(l.date);
    return [l.date == today ? 'сьогодні' : '${d.day} ${months[d.month - 1]}', ?l.time].join(' ');
  }

  String teacher(StudioData data, Lesson l) => data.profileById[l.ownerId]?.fullName ?? '';
  String join(List<String?> parts) => parts.whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  for (final w in after.works) {
    if (!w.printed || (before.work(w.lessonId, w.studentId)?.printed ?? false)) continue;
    if (w.printedByName != null && w.printedByName == me.fullName) continue;
    final l = after.lessonById[w.lessonId];
    final s = after.studentById[w.studentId];
    if (l == null || s == null) continue;
    events.add(StudioEvent('Модель надруковано', join([s.name, what(l), w.printedByName]), lessonId: l.id));
  }

  for (final s in after.students) {
    if (before.studentById.containsKey(s.id)) continue;
    events.add(StudioEvent('Новий учень', join([s.name, s.parentsName]), studentId: s.id));
  }

  for (final old in before.lessons) {
    final l = after.lessonById[old.id];
    if (l == null) {
      if (old.date.compareTo(today) < 0) continue;
      events.add(StudioEvent('Заняття скасовано', join([what(old), when(old), teacher(before, old)])));
    } else if (l.date != old.date || l.time != old.time) {
      if (old.date.compareTo(today) < 0 && l.date.compareTo(today) < 0) continue;
      events.add(
        StudioEvent(
          'Заняття перенесено',
          join(['${what(l)}: ${when(old)} → ${when(l)}', teacher(after, l)]),
          lessonId: l.id,
        ),
      );
    }
  }
  return events;
}

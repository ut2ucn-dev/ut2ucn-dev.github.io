// Studio-wide search for the ⌘K palette: students, lessons and teachers
// matched on everything a person might type about them.

import '../data/models.dart';
import '../data/studio_data.dart';
import 'dates.dart';
import 'domain.dart';
import 'text.dart';

/// Lower case, apostrophes dropped: "П'ятниця" finds "пятниця" and back.
String foldForSearch(String s) => s.toLowerCase().replaceAll(RegExp("['’ʼ`]"), '');

/// The words of [query]; a phone-looking word ("+380", "(67)") keeps only
/// its digits.
List<String> searchTokens(String query) => [
  for (final w in foldForSearch(query).split(RegExp(r'\s+')))
    if (w.isNotEmpty)
      RegExp(r'^[+\d()\-]+$').hasMatch(w) && RegExp(r'\d').hasMatch(w) ? w.replaceAll(RegExp(r'\D'), '') : w,
];

/// 0 unless every token is in [haystack] (already folded); otherwise
/// higher for matches at the very start and at word starts.
int matchScore(String haystack, List<String> tokens) {
  if (tokens.isEmpty) return 0;
  var score = 0;
  for (final t in tokens) {
    final i = haystack.indexOf(t);
    if (i < 0) return 0;
    score += i == 0 ? 4 : (_wordStart(haystack, i) ? 3 : 1);
  }
  return score;
}

bool _wordStart(String s, int i) => RegExp(r'[\s\-·(,./]').hasMatch(s[i - 1]);

enum SearchKind { student, lesson, teacher }

class SearchHit {
  const SearchHit(this.kind, this.id, this.score);
  final SearchKind kind;
  final String id;
  final int score;
}

class SearchResults {
  const SearchResults(this.students, this.lessons, this.teachers);
  final List<SearchHit> students;
  final List<SearchHit> lessons;
  final List<SearchHit> teachers;

  static const empty = SearchResults([], [], []);
  bool get isEmpty => students.isEmpty && lessons.isEmpty && teachers.isEmpty;
  int get best => [...students, ...lessons, ...teachers].fold(0, (m, h) => h.score > m ? h.score : m);
}

/// Everything in [data] that matches [query], best first, at most [limit]
/// of a kind. Lessons equally good are ordered by how close they are to
/// [now], upcoming before past.
SearchResults searchStudio(StudioData data, String query, {required DateTime now, int limit = 6}) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return SearchResults.empty;
  final today = dateOnly(now);

  final students = <SearchHit>[];
  for (final s in data.students) {
    final hay = foldForSearch('${s.name} ${s.parentsName} ${(s.phone ?? '').replaceAll(RegExp(r'\D'), '')}');
    final score = matchScore(hay, tokens);
    if (score > 0) students.add(SearchHit(SearchKind.student, s.id, score));
  }
  students.sort((a, b) {
    final d = b.score - a.score;
    return d != 0 ? d : ukCompare(data.studentById[a.id]!.name, data.studentById[b.id]!.name);
  });

  final lessons = <(SearchHit, int)>[];
  for (final l in data.lessons) {
    final score = matchScore(lessonHaystack(l, data, today), tokens);
    if (score > 0) {
      lessons.add((SearchHit(SearchKind.lesson, l.id, score), parseDate(l.date).difference(today).inDays));
    }
  }
  lessons.sort((a, b) {
    final d = b.$1.score - a.$1.score;
    if (d != 0) return d;
    final (da, db) = (a.$2, b.$2);
    if ((da < 0) != (db < 0)) return da < 0 ? 1 : -1;
    return da.abs() - db.abs();
  });

  final teachers = <SearchHit>[];
  for (final p in data.profiles) {
    final score = matchScore(foldForSearch('${p.fullName} ${p.email ?? ''} ${roleLabels[p.role] ?? ''}'), tokens);
    if (score > 0) teachers.add(SearchHit(SearchKind.teacher, p.id, score + (p.active ? 0 : -1)));
  }
  teachers.sort((a, b) => b.score - a.score);

  return SearchResults(students.take(limit).toList(), [
    for (final (h, _) in lessons.take(limit)) h,
  ], teachers.where((h) => h.score > 0).take(limit).toList());
}

/// What a lesson can be found by: theme, course, teacher, room, format,
/// the date in several spellings, the weekday, the time, and "сьогодні",
/// "завтра", "вчора".
String lessonHaystack(Lesson l, StudioData data, DateTime today) {
  final d = parseDate(l.date);
  final days = d.difference(today).inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  return foldForSearch(
    [
      l.theme,
      ?l.course,
      data.profileById[l.ownerId]?.fullName,
      if (l.substituteOwnerId != null) data.profileById[l.substituteOwnerId]?.fullName,
      ?l.room,
      formatLabel(l.format),
      '${two(d.day)}.${two(d.month)}.${d.year}',
      '${d.day}.${two(d.month)}',
      '${d.day} ${months[d.month - 1]}',
      weekdayName(d),
      ?l.time,
      if (days == 0) 'сьогодні',
      if (days == 1) 'завтра',
      if (days == -1) 'вчора',
    ].whereType<String>().join(' · '),
  );
}

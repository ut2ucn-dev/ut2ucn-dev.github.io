import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/studio_data.dart';
import '../util/dates.dart';
import '../util/domain.dart';
import '../util/search.dart';
import 'schedule/lesson_screen.dart';
import 'scope.dart';
import 'students/student_card_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Search on the phone — the same search as ⌘K on the Mac: students by
/// name, parents or any part of the phone; lessons by theme, course,
/// teacher, room, date, weekday or "завтра"; for admins, teachers. Several
/// words narrow it down. With nothing typed it lists what was opened from
/// it recently (shared with the Mac's palette).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onOpenTeacherSchedule});

  /// Shows the schedule filtered to the teacher just picked (already set
  /// on the store). Teachers are only offered when this is given.
  final VoidCallback? onOpenTeacherSchedule;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(String recentKey, VoidCallback go) {
    SettingsScope.read(context).addRecentSearch(recentKey);
    go();
  }

  void _openStudent(Student s) => _open(
    'student:${s.id}',
    () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentCardScreen(studentId: s.id))),
  );

  void _openLesson(Lesson l) => _open(
    'lesson:${l.id}',
    () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(lessonId: l.id))),
  );

  void _openTeacher(Profile p) => _open('teacher:${p.id}', () {
    context.storeRead.teacherFilter = p.id;
    Navigator.of(context).pop();
    widget.onOpenTeacherSchedule!();
  });

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final data = store.data;
    final tokens = searchTokens(_query.text);
    final teachers = store.isAdmin && widget.onOpenTeacherSchedule != null;

    final groups = <(String, List<Widget>)>[];
    if (tokens.isEmpty) {
      final recent = <Widget>[
        for (final key in SettingsScope.read(context).recentSearch) ?_recent(key, data, teachers, tokens),
      ];
      if (recent.isNotEmpty) groups.add(('Нещодавні', recent));
    } else {
      final found = searchStudio(data, _query.text, now: DateTime.now(), limit: 20);
      if (found.students.isNotEmpty) {
        groups.add(('Учні', [for (final h in found.students) _studentTile(data.studentById[h.id]!, tokens)]));
      }
      // The short lists first; lessons can be many.
      if (teachers && found.teachers.isNotEmpty) {
        groups.add(('Викладачі', [for (final h in found.teachers) _teacherTile(data.profileById[h.id]!, tokens)]));
      }
      if (found.lessons.isNotEmpty) {
        groups.add(('Заняття', [for (final h in found.lessons) _lessonTile(data.lessonById[h.id]!, tokens)]));
      }
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: teachers ? 'Учні, заняття, викладачі…' : 'Учні, заняття…',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистити',
                    onPressed: () => setState(_query.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
      body: groups.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                tokens.isEmpty
                    ? "Учня — за ім'ям, батьками чи телефоном; заняття — за темою, напрямком, викладачем, датою "
                          '(«25.10»), днем тижня чи словом «завтра». Кілька слів звужують пошук.'
                    : 'Нічого не знайдено за «${_query.text.trim()}»',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft),
              ),
            )
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
              children: [
                for (final (title, tiles) in groups) ...[SectionTitle(title), ...tiles],
              ],
            ),
    );
  }

  Widget? _recent(String key, StudioData data, bool teachers, List<String> tokens) {
    final i = key.indexOf(':');
    if (i < 0) return null;
    final id = key.substring(i + 1);
    return switch (key.substring(0, i)) {
      'student' => data.studentById[id] == null ? null : _studentTile(data.studentById[id]!, tokens),
      'lesson' => data.lessonById[id] == null ? null : _lessonTile(data.lessonById[id]!, tokens),
      'teacher' when teachers => data.profileById[id] == null ? null : _teacherTile(data.profileById[id]!, tokens),
      _ => null,
    };
  }

  Widget _tile({
    required Widget leading,
    required String title,
    required String subtitle,
    required List<String> tokens,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return ListTile(
      leading: leading,
      title: Text.rich(
        highlight(
          title,
          tokens,
          TextStyle(fontWeight: FontWeight.w700, color: c.ink),
          TextStyle(fontWeight: FontWeight.w800, color: c.brandText),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text.rich(
        highlight(
          subtitle,
          tokens,
          TextStyle(color: c.inkSoft),
          TextStyle(color: c.brandText, fontWeight: FontWeight.w700),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }

  Widget _studentTile(Student s, List<String> tokens) => _tile(
    leading: Avatar(initial: s.initial, url: context.storeRead.isAdmin ? s.photo : null, size: 40),
    title: s.name,
    subtitle: [if (s.parentsName.isNotEmpty) s.parentsName, ?s.phone].join(' · '),
    tokens: tokens,
    onTap: () => _openStudent(s),
  );

  Widget _lessonTile(Lesson l, List<String> tokens) {
    final c = context.c;
    final accent = c.course(l.course);
    final d = parseDate(l.date);
    return _tile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: accent.soft, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.event_rounded, color: accent.color),
      ),
      title: l.theme.isEmpty ? (l.course ?? 'Заняття') : l.theme,
      subtitle: [
        '${d.day} ${months[d.month - 1]}, ${weekdayName(d)}',
        ?l.time,
        if (context.storeRead.isAdmin) ?context.storeRead.data.profileById[l.ownerId]?.fullName,
        ?l.course,
      ].join(' · '),
      tokens: tokens,
      onTap: () => _openLesson(l),
    );
  }

  Widget _teacherTile(Profile p, List<String> tokens) => _tile(
    leading: Avatar(initial: p.initials, url: p.photo, size: 40),
    title: p.fullName,
    subtitle: [roleLabels[p.role] ?? 'Викладач', 'розклад викладача'].join(' · '),
    tokens: tokens,
    onTap: () => _openTeacher(p),
  );
}

/// The search icon for the phone's app bars (the Mac has ⌘K instead).
class SearchAction extends StatelessWidget {
  const SearchAction({super.key, this.onOpenTeacherSchedule});
  final VoidCallback? onOpenTeacherSchedule;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Пошук',
    onPressed: () =>
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SearchScreen(onOpenTeacherSchedule: onOpenTeacherSchedule))),
    icon: const Icon(Icons.search_rounded),
  );
}

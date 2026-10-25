import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../schedule/lesson_edit_screen.dart';
import '../schedule/lesson_screen.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// The whole studio, a week at a time (StudioCalendarTab on the web). In a
/// wide window it is a timetable — hours down, days across, a block per
/// lesson; on a phone, a list of days. A lesson's card opens on tap; a
/// right-click (long press) offers editing, the teacher's schedule and
/// deleting.
class StudioCalendarScreen extends StatefulWidget {
  const StudioCalendarScreen({super.key, this.onOpenTeacherSchedule});

  /// Shows the schedule filtered to one teacher (already set on the store).
  final VoidCallback? onOpenTeacherSchedule;

  @override
  State<StudioCalendarScreen> createState() => StudioCalendarScreenState();
}

class StudioCalendarScreenState extends State<StudioCalendarScreen> {
  DateTime _week = startOfWeek(DateTime.now());

  void shiftWeek(int weeks) => setState(() => _week = _week.add(Duration(days: 7 * weeks)));
  void thisWeek() => setState(() => _week = startOfWeek(DateTime.now()));

  List<DateTime> get _days => [for (var i = 0; i < 7; i++) DateTime(_week.year, _week.month, _week.day + i)];

  Future<void> _open(Lesson l) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(lessonId: l.id)));

  Future<void> _newLesson(DateTime day) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonEditScreen(presetDate: isoDate(day))));

  Future<void> _menu(Lesson l, Offset at) async {
    final store = context.storeRead;
    final teacher = store.data.profileById[l.ownerId];
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(
          value: 'open',
          child: ListTile(leading: Icon(Icons.open_in_new_rounded), title: Text('Відкрити')),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Редагувати')),
        ),
        if (teacher != null && widget.onOpenTeacherSchedule != null)
          PopupMenuItem(
            value: 'teacher',
            child: ListTile(leading: const Icon(Icons.person_rounded), title: Text('Розклад: ${teacher.fullName}')),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Видалити')),
        ),
      ],
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'open':
        await _open(l);
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonEditScreen(lesson: l)));
      case 'teacher':
        store.teacherFilter = l.ownerId;
        widget.onOpenTeacherSchedule!();
      case 'delete':
        await deleteLessonFlow(context, l);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final from = isoDate(_week);
    final to = isoDate(_days.last);
    final week = store.data.lessons.where((l) => l.date.compareTo(from) >= 0 && l.date.compareTo(to) <= 0).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    final byDate = <String, List<Lesson>>{};
    for (final l in week) {
      byDate.putIfAbsent(l.date, () => []).add(l);
    }
    final children = week.fold<int>(0, (n, l) => n + l.studentIds.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календар студії'),
        actions: [
          IconButton(
            tooltip: 'Попередній тиждень',
            onPressed: () => shiftWeek(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          TextButton(onPressed: thisWeek, child: const Text('Цей тиждень')),
          IconButton(
            tooltip: 'Наступний тиждень',
            onPressed: () => shiftWeek(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SyncButton(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Text(
                  '${weekRangeLabel(_week)} ${_days.last.year}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 12),
                Text(
                  '${pluralUk(week.length, 'заняття', 'заняття', 'занять')} · ${pluralUk(children, 'учень', 'учні', 'учнів')}',
                  style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 760
                  ? _WeekGrid(days: _days, byDate: byDate, onOpen: _open, onMenu: _menu, onNew: _newLesson)
                  : _WeekList(days: _days, byDate: byDate, onOpen: _open, onMenu: _menu, onNew: _newLesson),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _LessonAction = Future<void> Function(Lesson lesson);
typedef _MenuAction = Future<void> Function(Lesson lesson, Offset at);
typedef _DayAction = Future<void> Function(DateTime day);

/// Hours down, days across; lessons that overlap share the column side by
/// side (as layoutDayLessons() on the web's week grid).
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.days,
    required this.byDate,
    required this.onOpen,
    required this.onMenu,
    required this.onNew,
  });
  final List<DateTime> days;
  final Map<String, List<Lesson>> byDate;
  final _LessonAction onOpen;
  final _MenuAction onMenu;
  final _DayAction onNew;

  static const _hour = 64.0;
  static const _gutter = 52.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = todayStr();
    final timed = byDate.values.expand((l) => l).where((l) => timeToMinutes(l.time) != null);
    var first = 9, last = 20;
    for (final l in timed) {
      final start = timeToMinutes(l.time)!;
      first = math.min(first, start ~/ 60);
      last = math.max(last, ((start + l.durationMinutes) / 60).ceil());
    }
    last = math.min(last, 24);
    final untimed = {
      for (final d in days) isoDate(d): (byDate[isoDate(d)] ?? []).where((l) => l.time == null).toList(),
    };
    final anyUntimed = untimed.values.any((l) => l.isNotEmpty);

    return Column(
      children: [
        // Day headers.
        Padding(
          padding: const EdgeInsets.only(left: _gutter, right: 8),
          child: Row(
            children: [
              for (final d in days)
                Expanded(
                  child: _DayHeader(
                    day: d,
                    today: isoDate(d) == today,
                    count: byDate[isoDate(d)]?.length ?? 0,
                    onNew: () => onNew(d),
                  ),
                ),
            ],
          ),
        ),
        if (anyUntimed)
          Padding(
            padding: const EdgeInsets.only(left: _gutter, right: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in days)
                  Expanded(
                    child: Column(
                      children: [
                        for (final l in untimed[isoDate(d)]!)
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: SizedBox(
                              height: 44,
                              child: _Block(lesson: l, onOpen: onOpen, onMenu: onMenu),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Divider(height: 1, color: c.line),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 8, bottom: 24),
            child: SizedBox(
              height: (last - first) * _hour + 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(
                      children: [
                        for (var h = first; h < last; h++)
                          Positioned(
                            top: (h - first) * _hour - 7 + 8,
                            right: 8,
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: TextStyle(color: c.inkSoft, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Expanded(
                      child: _DayColumn(
                        lessons: (byDate[isoDate(d)] ?? []).where((l) => l.time != null).toList(),
                        first: first,
                        last: last,
                        today: isoDate(d) == today,
                        onOpen: onOpen,
                        onMenu: onMenu,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today, required this.count, required this.onNew});
  final DateTime day;
  final bool today;
  final int count;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Material(
        color: today ? c.brand : c.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekdayShort(day).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: today ? Colors.white70 : c.inkSoft,
                      ),
                    ),
                    Text(
                      '${day.day} ${months[day.month - 1]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: today ? Colors.white : c.ink),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Нове заняття на цей день',
                visualDensity: VisualDensity.compact,
                onPressed: onNew,
                icon: Icon(Icons.add_rounded, size: 18, color: today ? Colors.white : c.brandText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.lessons,
    required this.first,
    required this.last,
    required this.today,
    required this.onOpen,
    required this.onMenu,
  });
  final List<Lesson> lessons;
  final int first;
  final int last;
  final bool today;
  final _LessonAction onOpen;
  final _MenuAction onMenu;

  /// Lane per lesson and lanes per overlapping cluster.
  static (Map<String, int>, Map<String, int>) _lanes(List<Lesson> lessons) {
    final lane = <String, int>{};
    final width = <String, int>{};
    var cluster = <Lesson>[];
    var clusterEnd = -1;
    void close() {
      final n = cluster.fold<int>(0, (m, l) => math.max(m, lane[l.id]! + 1));
      for (final l in cluster) {
        width[l.id] = n;
      }
      cluster = [];
    }

    final ends = <int>[];
    for (final l in lessons) {
      final start = timeToMinutes(l.time)!;
      final end = start + l.durationMinutes;
      if (start >= clusterEnd && cluster.isNotEmpty) {
        close();
        ends.clear();
      }
      var i = ends.indexWhere((e) => e <= start);
      if (i < 0) {
        ends.add(end);
        i = ends.length - 1;
      } else {
        ends[i] = end;
      }
      lane[l.id] = i;
      cluster.add(l);
      clusterEnd = math.max(clusterEnd, end);
    }
    if (cluster.isNotEmpty) close();
    return (lane, width);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const hour = _WeekGrid._hour;
    final (lane, lanes) = _lanes(lessons);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: today ? c.brandSoft.withValues(alpha: 0.35) : null,
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            for (var h = first; h <= last; h++)
              Positioned(
                top: (h - first) * hour + 8,
                left: 0,
                right: 0,
                child: Container(height: 1, color: c.line),
              ),
            for (final l in lessons)
              Positioned(
                top: (timeToMinutes(l.time)! - first * 60) / 60 * hour + 8,
                height: math.max(28, l.durationMinutes / 60 * hour - 2),
                left: 2 + box.maxWidth / lanes[l.id]! * lane[l.id]!,
                width: box.maxWidth / lanes[l.id]! - 4,
                child: _Block(lesson: l, onOpen: onOpen, onMenu: onMenu),
              ),
          ],
        ),
      ),
    );
  }
}

/// A lesson in the timetable: course colour, time, theme, teacher, room.
class _Block extends StatelessWidget {
  const _Block({required this.lesson, required this.onOpen, required this.onMenu});
  final Lesson lesson;
  final _LessonAction onOpen;
  final _MenuAction onMenu;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final accent = c.course(lesson.course);
    final teacher = store.data.profileById[lesson.ownerId];
    final end = lessonEndTime(lesson.time, lesson.durationMinutes);
    final tip = [
      '${lesson.time ?? 'Без часу'}${end != null ? '–$end' : ''} · ${lesson.theme}',
      ?lesson.course,
      if (teacher != null) teacher.fullName,
      ?lesson.room,
      '${lesson.studentIds.length} уч.',
    ].join('\n');
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onMenu(lesson, d.globalPosition),
        onLongPressStart: (d) => onMenu(lesson, d.globalPosition),
        child: Material(
          color: accent.soft,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpen(lesson),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: accent.color, width: 3)),
              ),
              padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
              // Short lessons show what fits; the tooltip has the rest.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lesson.time ?? 'Без часу',
                              maxLines: 1,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent.color),
                            ),
                          ),
                          if (lesson.completed) Icon(Icons.check_circle_rounded, size: 12, color: c.successText),
                        ],
                      ),
                      Text(
                        lesson.theme,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink, height: 1.15),
                      ),
                      if (teacher != null)
                        Text(
                          [teacher.fullName, ?lesson.room].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: c.inkSoft),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On a phone: one card per day, as the web's calendar.
class _WeekList extends StatelessWidget {
  const _WeekList({
    required this.days,
    required this.byDate,
    required this.onOpen,
    required this.onMenu,
    required this.onNew,
  });
  final List<DateTime> days;
  final Map<String, List<Lesson>> byDate;
  final _LessonAction onOpen;
  final _MenuAction onMenu;
  final _DayAction onNew;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final today = todayStr();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        for (final d in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              shape: isoDate(d) == today
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: c.brand, width: 1.5),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(dayHeader(d), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        IconButton(
                          tooltip: 'Нове заняття на цей день',
                          onPressed: () => onNew(d),
                          icon: Icon(Icons.add_rounded, color: c.brandText),
                        ),
                      ],
                    ),
                    if ((byDate[isoDate(d)] ?? []).isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Немає занять', style: TextStyle(color: c.inkSoft)),
                      ),
                    for (final l in byDate[isoDate(d)] ?? const <Lesson>[])
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onOpen(l),
                        onLongPress: () {
                          final box = context.findRenderObject() as RenderBox;
                          onMenu(l, box.localToGlobal(box.size.center(Offset.zero)));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: c.course(l.course).color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 46,
                                child: Text(l.time ?? '—', style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.theme,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      [
                                        ?l.course,
                                        store.data.profileById[l.ownerId]?.fullName ?? '?',
                                        if (l.seriesId != null) 'щотижня',
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

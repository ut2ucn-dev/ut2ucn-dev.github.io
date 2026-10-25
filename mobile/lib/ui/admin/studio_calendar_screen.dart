import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../desktop/platform.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../schedule/lesson_edit_screen.dart';
import '../schedule/lesson_screen.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// The whole studio, a week at a time (StudioCalendarTab on the web). In a
/// wide window it is a timetable — hours down, days across, a block per
/// lesson — and a lesson can be dragged to another day or time; on a phone,
/// a list of days. A lesson's card opens on tap; a right-click (long press)
/// offers editing, the teacher's schedule and deleting.
class StudioCalendarScreen extends StatefulWidget {
  const StudioCalendarScreen({super.key, this.onOpenTeacherSchedule});

  /// Shows the schedule filtered to one teacher (already set on the store).
  final VoidCallback? onOpenTeacherSchedule;

  @override
  State<StudioCalendarScreen> createState() => StudioCalendarScreenState();
}

class StudioCalendarScreenState extends State<StudioCalendarScreen> {
  DateTime _week = startOfWeek(DateTime.now());

  /// Lessons dragged to a new place and not yet back from the server: shown
  /// there meanwhile, so nothing jumps back while it saves.
  final Map<String, ({String date, String? time})> _moved = {};

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

  /// Other lessons that day which overlap [start]–[start]+duration and share
  /// the teacher or the room.
  List<Lesson> _clashes(Lesson lesson, String date, int start) {
    final end = start + lesson.durationMinutes;
    return [
      for (final x in context.storeRead.data.lessons)
        if (x.id != lesson.id && x.date == date && timeToMinutes(x.time) != null)
          if (timeToMinutes(x.time)! < end && start < timeToMinutes(x.time)! + x.durationMinutes)
            if (x.ownerId == lesson.ownerId || (x.room != null && x.room == lesson.room)) x,
    ];
  }

  /// A lesson dropped on [day] at [minutes] after midnight. Moves at once
  /// (with "Скасувати" in the snackbar); asks first when it clashes with
  /// the teacher's or the room's other lessons, already has attendance, or
  /// is weekly — then "this and the following" moves the rest of the series
  /// by the same number of days, to the same time.
  Future<void> moveLesson(Lesson lesson, DateTime day, int minutes) async {
    final store = context.storeRead;
    final data = store.data;
    final date = isoDate(day);
    final time = minutesToTime(minutes);
    if (lesson.date == date && lesson.time == time) return;
    final shift = parseDate(date).difference(parseDate(lesson.date)).inDays;
    final following = lesson.seriesId == null
        ? const <Lesson>[]
        : data.lessons.where((x) => x.seriesId == lesson.seriesId && x.date.compareTo(lesson.date) > 0).toList();
    final clashes = _clashes(lesson, date, minutes);
    final marked = lesson.studentIds.any((s) => data.attendance(lesson.id, s) != null);

    var withSeries = false;
    if (following.isNotEmpty || clashes.isNotEmpty || marked) {
      final choice = await _askMove(lesson, day, time, following.length, clashes, marked);
      if (choice == null || !mounted) return;
      withSeries = choice == 'series';
    }
    await _apply([
      (lesson, date, time),
      if (withSeries)
        for (final x in following) (x, addDays(x.date, shift), time),
    ], undoable: true);
  }

  Future<String?> _askMove(Lesson lesson, DateTime day, String time, int following, List<Lesson> clashes, bool marked) {
    final data = context.storeRead.data;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.c;
        Widget warn(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: c.alertText),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );
        return AlertDialog(
          title: const Text('Перенести заняття?', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('«${lesson.theme}» → ${dayHeader(day)}, $time'),
                for (final x in clashes)
                  warn(
                    Icons.warning_amber_rounded,
                    'Накладається: ${x.time} «${x.theme}» — '
                    '${x.ownerId == lesson.ownerId ? 'той самий викладач' : 'той самий кабінет (${x.room})'}'
                    '${x.ownerId == lesson.ownerId ? '' : ', ${data.profileById[x.ownerId]?.fullName ?? ''}'}',
                  ),
                if (marked)
                  warn(Icons.how_to_reg_rounded, 'У заняття вже є відмітки присутності — вони перейдуть разом із ним.'),
                if (following > 0)
                  warn(
                    Icons.repeat_rounded,
                    'Заняття щотижневе. «Це і наступні» перенесе й наступні $following на той самий день тижня й час.',
                  ),
              ],
            ),
          ),
          actionsOverflowDirection: VerticalDirection.up,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
            if (following > 0)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'series'),
                child: Text('Це і наступні (${following + 1})'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'one'),
              child: Text(following > 0 ? 'Лише це' : 'Перенести'),
            ),
          ],
        );
      },
    );
  }

  /// Saves the new (date, time) of each lesson; needs a connection, like
  /// any other change to a lesson.
  Future<void> _apply(List<(Lesson, String, String?)> moves, {bool undoable = false}) async {
    final store = context.storeRead;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      for (final (l, date, time) in moves) {
        _moved[l.id] = (date: date, time: time);
      }
    });
    final ok = await store.online(() async {
      for (final (l, date, time) in moves) {
        await store.api.updateLesson(l.id, {'date': date, 'time': time});
      }
    }, reload: false);
    if (ok) await store.sync();
    if (!mounted) return;
    setState(() {
      for (final (l, _, _) in moves) {
        _moved.remove(l.id);
      }
    });
    if (!ok || !undoable) return;
    final (first, date, time) = moves.first;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          width: isAdminDesktop ? 480 : null,
          content: Text(
            '«${first.theme}» → ${dayHeader(parseDate(date))}, $time'
            '${moves.length > 1 ? ' (і ще ${moves.length - 1})' : ''}',
          ),
          action: SnackBarAction(
            label: 'Скасувати',
            onPressed: () => _apply([for (final (l, _, _) in moves) (l, l.date, l.time)]),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final from = isoDate(_week);
    final to = isoDate(_days.last);
    final week =
        store.data.lessons
            .map((l) {
              final m = _moved[l.id];
              return m == null ? l : l.copyWith({'date': m.date, 'time': m.time});
            })
            .where((l) => l.date.compareTo(from) >= 0 && l.date.compareTo(to) <= 0)
            .toList()
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
                  ? _WeekGrid(
                      days: _days,
                      byDate: byDate,
                      onOpen: _open,
                      onMenu: _menu,
                      onNew: _newLesson,
                      onDrop: moveLesson,
                    )
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
typedef _DropAction = Future<void> Function(Lesson lesson, DateTime day, int minutes);

/// Where the lesson being dragged would land ("Нд 16:00"), for the block
/// under the pointer; null when it is over no day. One drag at a time.
final _dropLabel = ValueNotifier<String?>(null);

/// Hours down, days across; lessons that overlap share the column side by
/// side (as layoutDayLessons() on the web's week grid).
class _WeekGrid extends StatefulWidget {
  const _WeekGrid({
    required this.days,
    required this.byDate,
    required this.onOpen,
    required this.onMenu,
    required this.onNew,
    required this.onDrop,
  });
  final List<DateTime> days;
  final Map<String, List<Lesson>> byDate;
  final _LessonAction onOpen;
  final _MenuAction onMenu;
  final _DayAction onNew;
  final _DropAction onDrop;

  static const _hour = 64.0;
  static const _gutter = 52.0;

  @override
  State<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<_WeekGrid> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// While a lesson is dragged near the top or bottom edge, scroll on.
  void _autoScroll(Offset topLeft, double height) {
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final top = box.localToGlobal(Offset.zero).dy;
    const edge = 28.0, step = 14.0;
    final p = _scroll.position;
    double? to;
    if (topLeft.dy < top + edge) to = p.pixels - step;
    if (topLeft.dy + height > top + box.size.height - edge) to = p.pixels + step;
    if (to != null) _scroll.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    const hour = _WeekGrid._hour;
    const gutter = _WeekGrid._gutter;
    final days = widget.days;
    final byDate = widget.byDate;
    final onOpen = widget.onOpen;
    final onMenu = widget.onMenu;
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
          padding: const EdgeInsets.only(left: gutter, right: 8),
          child: Row(
            children: [
              for (final d in days)
                Expanded(
                  child: _DayHeader(
                    day: d,
                    today: isoDate(d) == today,
                    count: byDate[isoDate(d)]?.length ?? 0,
                    onNew: () => widget.onNew(d),
                  ),
                ),
            ],
          ),
        ),
        if (anyUntimed)
          Padding(
            padding: const EdgeInsets.only(left: gutter, right: 8, bottom: 4),
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
                              child: _Block(lesson: l, onOpen: onOpen, onMenu: onMenu, draggable: true),
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
            key: _viewport,
            controller: _scroll,
            padding: const EdgeInsets.only(right: 8, bottom: 24),
            child: SizedBox(
              height: (last - first) * hour + 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: gutter,
                    child: Stack(
                      children: [
                        for (var h = first; h < last; h++)
                          Positioned(
                            top: (h - first) * hour - 7 + 8,
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
                        day: d,
                        lessons: (byDate[isoDate(d)] ?? []).where((l) => l.time != null).toList(),
                        first: first,
                        last: last,
                        today: isoDate(d) == today,
                        onOpen: onOpen,
                        onMenu: onMenu,
                        onDrop: widget.onDrop,
                        onDragMove: _autoScroll,
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

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.day,
    required this.lessons,
    required this.first,
    required this.last,
    required this.today,
    required this.onOpen,
    required this.onMenu,
    required this.onDrop,
    required this.onDragMove,
  });
  final DateTime day;
  final List<Lesson> lessons;
  final int first;
  final int last;
  final bool today;
  final _LessonAction onOpen;
  final _MenuAction onMenu;
  final _DropAction onDrop;
  final void Function(Offset topLeft, double height) onDragMove;

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
  State<_DayColumn> createState() => _DayColumnState();
}

/// A drop target: while a lesson is dragged over the day, the slot it
/// would land in (to a quarter of an hour) is outlined with its new time.
class _DayColumnState extends State<_DayColumn> {
  ({Lesson lesson, int start})? _hover;

  /// Where the top of the dragged block lands, snapped to 15 minutes and
  /// kept inside the visible hours.
  int _startAt(Offset topLeft, Lesson lesson) {
    final box = context.findRenderObject() as RenderBox;
    final y = box.globalToLocal(topLeft).dy - 8;
    final raw = widget.first * 60 + y / _WeekGrid._hour * 60;
    final latest = math.max(widget.first * 60, widget.last * 60 - lesson.durationMinutes);
    return ((raw / 15).round() * 15).clamp(widget.first * 60, latest);
  }

  double _top(int minutes) => (minutes - widget.first * 60) / 60 * _WeekGrid._hour + 8;
  double _height(Lesson l) => math.max(28, l.durationMinutes / 60 * _WeekGrid._hour - 2);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final first = widget.first;
    final (lane, lanes) = _DayColumn._lanes(widget.lessons);
    final hover = _hover;
    return DragTarget<Lesson>(
      onMove: (d) {
        final start = _startAt(d.offset, d.data);
        if (hover?.start != start || hover?.lesson.id != d.data.id) {
          setState(() => _hover = (lesson: d.data, start: start));
          _dropLabel.value = '${weekdayShort(widget.day)} ${minutesToTime(start)}';
        }
        widget.onDragMove(d.offset, _height(d.data));
      },
      onLeave: (_) {
        setState(() => _hover = null);
        _dropLabel.value = null;
      },
      onAcceptWithDetails: (d) {
        final start = _startAt(d.offset, d.data);
        setState(() => _hover = null);
        _dropLabel.value = null;
        widget.onDrop(d.data, widget.day, start);
      },
      builder: (context, _, _) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: hover != null
              ? c.brandSoft.withValues(alpha: 0.6)
              : (widget.today ? c.brandSoft.withValues(alpha: 0.35) : null),
          border: Border(left: BorderSide(color: c.line)),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              for (var h = first; h <= widget.last; h++)
                Positioned(
                  top: (h - first) * _WeekGrid._hour + 8,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: c.line),
                ),
              for (final l in widget.lessons)
                Positioned(
                  top: _top(timeToMinutes(l.time)!),
                  height: _height(l),
                  left: 2 + box.maxWidth / lanes[l.id]! * lane[l.id]!,
                  width: box.maxWidth / lanes[l.id]! - 4,
                  child: _Block(lesson: l, onOpen: widget.onOpen, onMenu: widget.onMenu, draggable: true),
                ),
              if (hover != null)
                Positioned(
                  top: _top(hover.start),
                  height: _height(hover.lesson),
                  left: 2,
                  right: 2,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.card.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.brand, width: 2),
                      ),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.fromLTRB(6, 3, 4, 0),
                      child: Text(
                        '${minutesToTime(hover.start)}–${minutesToTime(hover.start + hover.lesson.durationMinutes)}',
                        style: TextStyle(color: c.brandText, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A lesson in the timetable: course colour, time, theme, teacher, room.
/// With [draggable], it can be picked up and dropped on another day or
/// time — with the mouse at once, on a touch screen after a long press.
class _Block extends StatelessWidget {
  const _Block({required this.lesson, required this.onOpen, required this.onMenu, this.draggable = false});
  final Lesson lesson;
  final _LessonAction onOpen;
  final _MenuAction onMenu;
  final bool draggable;

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
      if (draggable) 'Перетягніть, щоб перенести',
    ].join('\n');
    final radius = BorderRadius.circular(8);

    final face = Container(
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
    );

    final card = Material(
      color: accent.soft,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => onOpen(lesson), child: face),
    );
    final mouse = isAdminDesktop;

    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onSecondaryTapUp: (d) => onMenu(lesson, d.globalPosition),
        // On a touch screen a long press picks the lesson up instead.
        onLongPressStart: draggable && !mouse ? null : (d) => onMenu(lesson, d.globalPosition),
        child: !draggable
            ? card
            : LayoutBuilder(
                builder: (context, box) {
                  final size = Size(box.maxWidth, box.maxHeight.isFinite ? box.maxHeight : 44);
                  final feedback = SizedBox.fromSize(
                    size: size,
                    // The drag overlay sits outside any Material: give the
                    // label its text style.
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Material(
                            color: accent.soft,
                            elevation: 8,
                            borderRadius: radius,
                            clipBehavior: Clip.antiAlias,
                            child: face,
                          ),
                        ),
                        // The new day and time, right where the eye is.
                        Positioned(
                          right: 4,
                          top: -12,
                          child: ValueListenableBuilder<String?>(
                            valueListenable: _dropLabel,
                            builder: (context, label, _) => label == null
                                ? const SizedBox.shrink()
                                : Material(
                                    type: MaterialType.transparency,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.brand,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                  final ghost = Opacity(opacity: 0.3, child: card);
                  void ended() => _dropLabel.value = null;
                  return mouse
                      ? Draggable<Lesson>(
                          data: lesson,
                          feedback: feedback,
                          childWhenDragging: ghost,
                          onDragEnd: (_) => ended(),
                          child: card,
                        )
                      : LongPressDraggable<Lesson>(
                          data: lesson,
                          feedback: feedback,
                          childWhenDragging: ghost,
                          onDragEnd: (_) => ended(),
                          child: card,
                        );
                },
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

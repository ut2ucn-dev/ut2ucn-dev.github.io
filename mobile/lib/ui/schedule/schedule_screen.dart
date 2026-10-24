import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/studio_data.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lesson_edit_screen.dart';
import 'lesson_screen.dart';

/// Day-by-day agenda. Swipe left/right to change the day; the strip on top
/// shows the week with a dot per lesson.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => ScheduleScreenState();
}

class ScheduleScreenState extends State<ScheduleScreen> {
  // Page index 0 is _origin; pages run far in both directions.
  static const _center = 5000;
  late final DateTime _origin = dateOnly(DateTime.now());
  late final _pages = PageController(initialPage: _center);
  int _page = _center;
  final Set<String> _courses = {};
  final Set<String> _rooms = {};

  DateTime get _day => _dayFor(_page);
  DateTime _dayFor(int page) => DateTime(_origin.year, _origin.month, _origin.day + page - _center);

  void goToDate(DateTime d) {
    final page = _center + dateOnly(d).difference(_origin).inDays;
    if ((page - _page).abs() > 7) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Iterable<Lesson> _visible(Iterable<Lesson> lessons) => lessons.where((l) {
    if (_courses.isNotEmpty && !_courses.contains(l.course)) return false;
    if (_rooms.isNotEmpty && !_rooms.contains(l.room ?? '')) return false;
    return true;
  });

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final byDate = <String, List<Lesson>>{};
    for (final l in _visible(store.scheduleLessons)) {
      byDate.putIfAbsent(l.date, () => []).add(l);
    }
    final filterOn = store.teacherFilter != null || _courses.isNotEmpty || _rooms.isNotEmpty;
    final teacher = store.teacherFilter == null ? null : store.data.profileById[store.teacherFilter];
    final title = !store.isAdmin ? 'Розклад' : (teacher != null ? teacher.fullName : 'Розклад студії');

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Сьогодні',
            onPressed: () => goToDate(DateTime.now()),
            icon: const Icon(Icons.today_rounded),
          ),
          if (store.isAdmin)
            IconButton(
              tooltip: 'Фільтри',
              onPressed: _openFilters,
              icon: Badge(isLabelVisible: filterOn, smallSize: 8, child: const Icon(Icons.filter_list_rounded)),
            ),
          const SyncButton(),
        ],
      ),
      floatingActionButton: store.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LessonEditScreen(presetDate: isoDate(_day), presetOwnerId: store.teacherFilter),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Заняття', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: Column(
        children: [
          _WeekStrip(
            selected: _day,
            counts: {for (final e in byDate.entries) e.key: e.value.length},
            onSelect: goToDate,
          ),
          if (filterOn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_rounded, size: 16, color: c.brandText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        if (teacher != null) teacher.fullName,
                        ..._courses,
                        ..._rooms.map((r) => r.isEmpty ? 'Без кабінету' : r),
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.brandText, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      store.teacherFilter = null;
                      _courses.clear();
                      _rooms.clear();
                    }),
                    child: const Text('Скинути'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, page) {
                final day = _dayFor(page);
                return _DayAgenda(day: day, lessons: byDate[isoDate(day)] ?? const []);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    final store = context.storeRead;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          Widget chips(List<String> options, Set<String> selected, {String Function(String)? label}) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                FilterChip(
                  label: Text(label?.call(o) ?? o),
                  selected: selected.contains(o),
                  onSelected: (v) => update(() => v ? selected.add(o) : selected.remove(o)),
                ),
            ],
          );

          final teachers = store.data.profiles.where((p) => p.active).toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  const Text('Фільтри', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SectionTitle('Викладач'),
                  DropdownButtonFormField<String?>(
                    initialValue: store.teacherFilter,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Уся студія')),
                      for (final t in teachers) DropdownMenuItem(value: t.id, child: Text(t.fullName)),
                    ],
                    onChanged: (v) => update(() => store.teacherFilter = v),
                  ),
                  const SectionTitle('Курс'),
                  chips(courseOptions, _courses),
                  const SectionTitle('Кабінет'),
                  chips(['', ...roomOptions], _rooms, label: (r) => r.isEmpty ? 'Без кабінету' : r),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.selected, required this.counts, required this.onSelect});
  final DateTime selected;
  final Map<String, int> counts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final start = startOfWeek(selected);
    final today = isoDate(DateTime.now());
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 200) return;
        onSelect(selected.add(Duration(days: v < 0 ? 7 : -7)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onSelect(selected.subtract(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${weekRangeLabel(start)} ${start.add(const Duration(days: 6)).year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onSelect(selected.add(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final d = start.add(Duration(days: i));
                        final key = isoDate(d);
                        final isSel = key == isoDate(selected);
                        final isToday = key == today;
                        final n = counts[key] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: Material(
                            color: isSel ? c.brand : c.card,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isSel ? c.brand : (isToday ? c.brand.withValues(alpha: 0.6) : c.line),
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => onSelect(d),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  children: [
                                    Text(
                                      weekdayShort(d),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isSel ? Colors.white70 : (i >= 5 ? c.alertText : c.inkSoft),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${d.day}',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: isSel ? Colors.white : c.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        for (var k = 0; k < (n > 4 ? 4 : n); k++)
                                          Container(
                                            width: 5,
                                            height: 5,
                                            margin: const EdgeInsets.symmetric(horizontal: 1),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isSel ? Colors.white : c.brand,
                                            ),
                                          ),
                                        if (n == 0) const SizedBox(height: 5),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({required this.day, required this.lessons});
  final DateTime day;
  final List<Lesson> lessons;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final sorted = [...lessons]..sort((a, b) => (a.time ?? '').compareTo(b.time ?? ''));
    final isToday = isoDate(day) == isoDate(DateTime.now());
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(
              children: [
                Text(dayHeader(day), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (isToday) ...[const SizedBox(width: 8), Tag('Сьогодні', color: Colors.white, soft: c.brand)],
                const Spacer(),
                if (sorted.isNotEmpty)
                  Text(
                    '${sorted.length} ${_plural(sorted.length)}',
                    style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (!store.hasData && store.refreshing)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: LoadingView(text: 'Завантаження розкладу…'),
            )
          else if (sorted.isEmpty)
            EmptyState(
              emoji: '📅',
              title: 'Немає занять',
              subtitle: store.isAdmin ? 'Додайте заняття кнопкою внизу.' : 'Розклад формує адміністратор.',
            )
          else
            for (final l in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LessonTile(lesson: l, data: store.data),
              ),
        ],
      ),
    );
  }

  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'заняття';
    if (m10 == 1 && m100 != 11) return 'заняття';
    return 'занять';
  }
}

class LessonTile extends StatelessWidget {
  const LessonTile({super.key, required this.lesson, required this.data, this.showDate = false});
  final Lesson lesson;
  final StudioData data;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final accent = c.course(lesson.course);
    final roster = data.roster(lesson);
    final printable = data.printable(lesson);
    final printed = data.printedCount(lesson);
    final end = lessonEndTime(lesson.time, lesson.durationMinutes);
    final owner = data.profileById[lesson.ownerId];
    final substitute = lesson.substituteOwnerId == null ? null : data.profileById[lesson.substituteOwnerId];
    final past = isPast(lesson.date);
    final iCover = !store.isAdmin && lesson.ownerId != store.me.id;
    // A lesson that has started (today or earlier) with children nobody
    // marked yet — the admin's to-do.
    final unmarked =
        store.isAdmin &&
        lesson.date.compareTo(todayStr()) <= 0 &&
        roster.any((s) => data.attendance(lesson.id, s.id) == null);

    return Opacity(
      opacity: past && !lesson.completed ? 0.92 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(lessonId: lesson.id))),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: accent.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (showDate) ...[
                              Text(
                                lessonCardDateTitle(lesson.date),
                                style: TextStyle(fontWeight: FontWeight.w700, color: c.inkSoft, fontSize: 13),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              lesson.time == null ? 'Без часу' : '${lesson.time}${end != null ? '–$end' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            const Spacer(),
                            if (lesson.raw['_pending'] == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.cloud_upload_rounded, size: 16, color: c.alertText),
                              ),
                            if (lesson.completed)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.check_circle_rounded, size: 18, color: c.successText),
                              ),
                          ],
                        ),
                        if (lesson.course != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            lesson.course!,
                            style: TextStyle(color: accent.color, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          lesson.theme,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (lesson.room != null) Tag(lesson.room!, icon: Icons.meeting_room_rounded),
                            if (store.isAdmin && owner != null) Tag(owner.fullName, icon: Icons.person_rounded),
                            if (lesson.format != 'group')
                              Tag(
                                formatLabel(lesson.format),
                                color: isOnlineFormat(lesson.format) ? c.brandText : c.alertText,
                                soft: isOnlineFormat(lesson.format) ? c.brandSoft : c.alertSoft,
                              ),
                            if (iCover)
                              Tag(
                                'Ви на заміні',
                                color: c.alertText,
                                soft: c.alertSoft,
                                icon: Icons.swap_horiz_rounded,
                              ),
                            if (substitute != null && !iCover)
                              Tag(
                                'Заміна: ${substitute.fullName}',
                                color: c.alertText,
                                soft: c.alertSoft,
                                icon: Icons.swap_horiz_rounded,
                              ),
                            Tag('${roster.length}', icon: Icons.groups_rounded),
                            if (printable.isNotEmpty)
                              Tag(
                                '$printed/${printable.length}',
                                icon: Icons.print_rounded,
                                color: printed == printable.length ? c.successText : c.alertText,
                                soft: printed == printable.length ? c.successSoft : c.alertSoft,
                              ),
                            if (unmarked)
                              Tag('Не відмічено', color: c.danger, soft: c.dangerSoft, icon: Icons.how_to_reg_rounded),
                          ],
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
    );
  }
}

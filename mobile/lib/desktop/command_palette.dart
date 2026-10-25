import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/studio_data.dart';
import '../ui/scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/dates.dart';
import '../util/domain.dart';
import '../util/search.dart';
import 'platform.dart';
import 'split_view.dart';

/// Something the palette can run that isn't a record: go to a section,
/// "Нове заняття", "Синхронізувати", a theme…
class PaletteCommand {
  const PaletteCommand({
    required this.title,
    required this.icon,
    required this.run,
    this.shortcut,
    this.keywords = '',
    this.navigation = false,
  });
  final String title;
  final IconData icon;
  final VoidCallback run;

  /// "⌘N", shown on the right.
  final String? shortcut;

  /// Other words it is found by.
  final String keywords;

  /// Listed under "Перейти" (sections) rather than "Дії".
  final bool navigation;
}

/// Opens the ⌘K palette over the app: one field that finds students,
/// lessons, teachers and commands as you type (as Spotlight). ↑↓ pick,
/// ↵ opens, esc closes; with nothing typed it offers what was opened
/// recently, the sections and the actions.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteCommand> commands,
  required void Function(String id) openStudent,
  required void Function(String id) openLesson,
  required void Function(String id) openTeacher,
  void Function(String id)? openStudentWindow,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Закрити пошук',
  barrierColor: Colors.black.withValues(alpha: 0.28),
  transitionDuration: const Duration(milliseconds: 160),
  pageBuilder: (_, _, _) => CommandPalette(
    commands: commands,
    openStudent: openStudent,
    openLesson: openLesson,
    openTeacher: openTeacher,
    openStudentWindow: openStudentWindow,
  ),
  transitionBuilder: (_, animation, _, child) {
    final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
    );
  },
);

/// One line of the palette.
class _Entry {
  const _Entry({
    required this.leading,
    required this.title,
    this.subtitle,
    this.shortcut,
    this.recentKey,
    required this.run,
    this.runInWindow,
  });
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? shortcut;

  /// Remembered as recent when picked.
  final String? recentKey;
  final VoidCallback run;

  /// ⌘↵: opens it in a window of its own (students on the Mac).
  final VoidCallback? runInWindow;
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    required this.openStudent,
    required this.openLesson,
    required this.openTeacher,
    this.openStudentWindow,
  });
  final List<PaletteCommand> commands;
  final void Function(String id) openStudent;
  final void Function(String id) openLesson;
  final void Function(String id) openTeacher;
  final void Function(String id)? openStudentWindow;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  static const _headerHeight = 30.0;
  static const _rowHeight = 54.0;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _selected = 0;

  /// Groups as shown: title and entries.
  List<(String, List<_Entry>)> _groups = const [];
  List<_Entry> get _flat => [for (final (_, g) in _groups) ...g];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _groups = _build();
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _groups = _build();
    _selected = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  });

  void _move(int by) {
    final n = _flat.length;
    if (n == 0) return;
    setState(() => _selected = (_selected + by) % n);
    _reveal();
  }

  /// Keeps the picked line in view.
  void _reveal() {
    if (!_scroll.hasClients) return;
    var top = 0.0, i = 0;
    for (final (_, g) in _groups) {
      top += _headerHeight;
      if (_selected < i + g.length) {
        top += (_selected - i) * _rowHeight;
        break;
      }
      top += g.length * _rowHeight;
      i += g.length;
    }
    final p = _scroll.position;
    if (top < p.pixels) {
      _scroll.jumpTo((top - _headerHeight).clamp(0, p.maxScrollExtent));
    } else if (top + _rowHeight > p.pixels + p.viewportDimension) {
      _scroll.jumpTo((top + _rowHeight - p.viewportDimension).clamp(0, p.maxScrollExtent));
    }
  }

  void _pick([_Entry? entry, bool inWindow = false]) {
    final flat = _flat;
    entry ??= flat.isEmpty ? null : flat[_selected.clamp(0, flat.length - 1)];
    if (entry == null) return;
    if (inWindow && entry.runInWindow == null) return;
    if (entry.recentKey != null) SettingsScope.read(context).addRecentSearch(entry.recentKey!);
    Navigator.of(context).pop();
    (inWindow ? entry.runInWindow! : entry.run)();
  }

  // --- entries --------------------------------------------------------------

  _Entry _student(Student s) => _Entry(
    leading: Avatar(initial: s.initial, url: s.photo, size: 34),
    title: s.name,
    subtitle: [if (s.parentsName.isNotEmpty) s.parentsName, ?s.phone].join(' · '),
    recentKey: 'student:${s.id}',
    run: () => widget.openStudent(s.id),
    runInWindow: widget.openStudentWindow == null ? null : () => widget.openStudentWindow!(s.id),
  );

  _Entry _lesson(Lesson l) {
    final c = context.c;
    final accent = c.course(l.course);
    final data = context.storeRead.data;
    final d = parseDate(l.date);
    return _Entry(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: accent.soft, borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.event_rounded, size: 18, color: accent.color),
      ),
      title: l.theme.isEmpty ? (l.course ?? 'Заняття') : l.theme,
      subtitle: [
        '${d.day} ${months[d.month - 1]}, ${weekdayName(d)}',
        ?l.time,
        ?data.profileById[l.ownerId]?.fullName,
        ?l.course,
        ?l.room,
      ].join(' · '),
      recentKey: 'lesson:${l.id}',
      run: () => widget.openLesson(l.id),
    );
  }

  _Entry _teacher(Profile p) => _Entry(
    leading: Avatar(initial: p.initials, url: p.photo, size: 34),
    title: p.fullName,
    subtitle: [roleLabels[p.role] ?? 'Викладач', if (!p.active) 'деактивовано', 'розклад викладача'].join(' · '),
    recentKey: 'teacher:${p.id}',
    run: () => widget.openTeacher(p.id),
  );

  _Entry _command(PaletteCommand cmd) {
    final c = context.c;
    return _Entry(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: c.sand, borderRadius: BorderRadius.circular(10)),
        child: Icon(cmd.icon, size: 18, color: c.ink),
      ),
      title: cmd.title,
      shortcut: cmd.shortcut,
      run: cmd.run,
    );
  }

  List<(String, List<_Entry>)> _build() {
    final data = context.storeRead.data;
    final tokens = searchTokens(_query.text);
    if (tokens.isEmpty) {
      final recent = <_Entry>[for (final key in SettingsScope.read(context).recentSearch) ?_recent(key, data)];
      return [
        if (recent.isNotEmpty) ('Нещодавні', recent),
        ('Перейти', [for (final c in widget.commands.where((c) => c.navigation)) _command(c)]),
        ('Дії', [for (final c in widget.commands.where((c) => !c.navigation)) _command(c)]),
      ];
    }
    final found = searchStudio(data, _query.text, now: DateTime.now());
    final commands = [
      for (final c in widget.commands)
        if (matchScore(foldForSearch('${c.title} ${c.keywords}'), tokens) case final s when s > 0) (c, s),
    ]..sort((a, b) => b.$2 - a.$2);
    final groups = <(String, List<_Entry>)>[
      if (found.students.isNotEmpty) ('Учні', [for (final h in found.students) _student(data.studentById[h.id]!)]),
      if (found.lessons.isNotEmpty) ('Заняття', [for (final h in found.lessons) _lesson(data.lessonById[h.id]!)]),
      if (found.teachers.isNotEmpty) ('Викладачі', [for (final h in found.teachers) _teacher(data.profileById[h.id]!)]),
    ];
    if (commands.isEmpty) return groups;
    final group = ('Команди', [for (final (c, _) in commands.take(5)) _command(c)]);
    // "звіт" should open the report before any student named Звітенко.
    return commands.first.$2 >= found.best ? [group, ...groups] : [...groups, group];
  }

  _Entry? _recent(String key, StudioData data) {
    final i = key.indexOf(':');
    if (i < 0) return null;
    final id = key.substring(i + 1);
    switch (key.substring(0, i)) {
      case 'student':
        final s = data.studentById[id];
        return s == null ? null : _student(s);
      case 'lesson':
        final l = data.lessonById[id];
        return l == null ? null : _lesson(l);
      case 'teacher':
        final p = data.profileById[id];
        return p == null ? null : _teacher(p);
    }
    return null;
  }

  // --- layout ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    final flat = _flat;
    final tokens = searchTokens(_query.text);
    var index = 0;

    // Pinned near the top, as Spotlight: the field stays put while the
    // results grow and shrink under it.
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: size.height * 0.12, left: 24, right: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: (size.height * 0.7).clamp(240, 560)),
          child: Material(
            color: c.card,
            elevation: 24,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Shortcuts(
              shortcuts: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): const _MoveIntent(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): const _MoveIntent(-1),
                const SingleActivator(LogicalKeyboardKey.tab): const _MoveIntent(1),
                const SingleActivator(LogicalKeyboardKey.tab, shift: true): const _MoveIntent(-1),
                cmd(LogicalKeyboardKey.enter): const _OpenInWindowIntent(),
                cmd(LogicalKeyboardKey.numpadEnter): const _OpenInWindowIntent(),
              },
              child: Actions(
                actions: {
                  _MoveIntent: CallbackAction<_MoveIntent>(onInvoke: (i) => _move(i.by)),
                  _OpenInWindowIntent: CallbackAction<_OpenInWindowIntent>(onInvoke: (_) => _pick(null, true)),
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        onChanged: (_) => _changed(),
                        onSubmitted: (_) => _pick(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'Учні, заняття, викладачі, команди…',
                          prefixIcon: Icon(Icons.search_rounded, color: c.brandText),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          suffixIcon: _query.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Очистити',
                                  onPressed: () {
                                    _query.clear();
                                    _changed();
                                  },
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: c.line),
                    Flexible(
                      child: flat.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                'Нічого не знайдено за «${_query.text.trim()}»',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.inkSoft),
                              ),
                            )
                          : ListView(
                              controller: _scroll,
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              children: [
                                for (final (title, entries) in _groups) ...[
                                  SizedBox(
                                    height: _headerHeight,
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
                                        child: Text(
                                          title.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            letterSpacing: 0.8,
                                            fontWeight: FontWeight.w700,
                                            color: c.inkSoft,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (final e in entries) _row(e, index++, tokens),
                                ],
                              ],
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: c.paper,
                      child: Text(
                        '↑↓ вибрати   ↵ відкрити   '
                        '${widget.openStudentWindow != null ? '${shortcutLabel('↵')} учня в окремому вікні   ' : ''}esc закрити',
                        style: TextStyle(fontSize: 12, color: c.inkSoft, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(_Entry e, int i, List<String> tokens) {
    final c = context.c;
    final selected = i == _selected;
    return SizedBox(
      height: _rowHeight,
      child: MouseRegion(
        onEnter: (_) {
          if (_selected != i) setState(() => _selected = i);
        },
        child: Material(
          color: selected ? c.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pick(e),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  e.leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          highlight(
                            e.title,
                            tokens,
                            TextStyle(fontWeight: FontWeight.w700, color: c.ink),
                            TextStyle(fontWeight: FontWeight.w800, color: c.brandText),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (e.subtitle != null && e.subtitle!.isNotEmpty)
                          Text.rich(
                            highlight(
                              e.subtitle!,
                              tokens,
                              TextStyle(fontSize: 12.5, color: c.inkSoft),
                              TextStyle(fontSize: 12.5, color: c.brandText, fontWeight: FontWeight.w700),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (e.shortcut != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.lineStrong),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        e.shortcut!,
                        style: TextStyle(fontSize: 12, color: c.inkSoft, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.keyboard_return_rounded, size: 16, color: c.brandText),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenInWindowIntent extends Intent {
  const _OpenInWindowIntent();
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.by);
  final int by;
}

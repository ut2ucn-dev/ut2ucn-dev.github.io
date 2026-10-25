import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../export/export_actions.dart';
import '../export/export_doc.dart';
import '../services/updates.dart';
import '../ui/admin/parent_accounts_screen.dart';
import '../ui/admin/print_costs_screen.dart';
import '../ui/admin/studio_calendar_screen.dart';
import '../ui/more/profile_screen.dart';
import '../ui/more/rates_screen.dart';
import '../ui/more/report_screen.dart';
import '../ui/more/settings_screen.dart';
import '../ui/more/users_screen.dart';
import '../ui/payroll_screen.dart';
import '../ui/queue_screen.dart';
import '../ui/schedule/lesson_edit_screen.dart';
import '../ui/schedule/lesson_screen.dart';
import '../ui/schedule/schedule_screen.dart';
import '../ui/scope.dart';
import '../ui/shell.dart';
import '../ui/students/student_edit_screen.dart';
import '../ui/students/students_screen.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/dates.dart';
import '../util/domain.dart';
import '../ui/students/student_card_screen.dart';
import 'command_palette.dart';
import 'platform.dart';
import 'windows.dart';
import 'split_view.dart';

/// Sidebar sections, in the web's order: the workspace, then administration.
enum DeskSection {
  schedule('Розклад', Icons.calendar_month_rounded, LogicalKeyboardKey.digit1),
  students('Учні', Icons.groups_rounded, LogicalKeyboardKey.digit2),
  queue('Черга друку', Icons.print_rounded, LogicalKeyboardKey.digit3),
  payroll('Зарплати', Icons.account_balance_wallet_rounded, LogicalKeyboardKey.digit4),
  teachers('Викладачі', Icons.badge_rounded, LogicalKeyboardKey.digit5),
  calendar('Календар', Icons.calendar_view_week_rounded, LogicalKeyboardKey.digit6),
  print('Друк (бета)', Icons.view_in_ar_rounded, LogicalKeyboardKey.digit7),
  rates('Тарифи', Icons.price_change_rounded, LogicalKeyboardKey.digit8, superOnly: true),
  report('Звіт студії', Icons.insights_rounded, LogicalKeyboardKey.digit9, superOnly: true),
  parents('Кабінети батьків', Icons.favorite_rounded, LogicalKeyboardKey.digit0, superOnly: true),
  settings('Налаштування', Icons.tune_rounded, LogicalKeyboardKey.comma);

  const DeskSection(this.label, this.icon, this.key, {this.superOnly = false});
  final String label;
  final IconData icon;
  final LogicalKeyboardKey key;
  final bool superOnly;

  static const workspace = [schedule, students, queue, payroll];
  static const admin = [teachers, calendar, print, rates, report, parents];
}

/// The signed-in macOS app: the web's sidebar on the left; on the right the
/// phone screens, laid out as list + card where there is a list. Each
/// section keeps its place when you switch away and back, and is only
/// built the first time it is opened.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.onSignOut});
  final Future<void> Function() onSignOut;

  @override
  State<DesktopShell> createState() => DesktopShellState();
}

class DesktopShellState extends State<DesktopShell> with WidgetsBindingObserver {
  DeskSection _section = DeskSection.schedule;
  final _visited = <DeskSection>{DeskSection.schedule};
  final _splits = {for (final s in DeskSection.workspace) s: GlobalKey<SplitViewState>()};
  final _schedule = GlobalKey<ScheduleScreenState>();
  final _calendar = GlobalKey<StudioCalendarScreenState>();
  final _payroll = GlobalKey<PayrollScreenState>();
  final _report = GlobalKey<ReportScreenState>();
  final _printCosts = GlobalKey<PrintCostsScreenState>();
  final _parents = GlobalKey<ParentAccountsScreenState>();
  StreamSubscription<String>? _messages;
  StreamSubscription<String>? _taps;
  StreamSubscription<String>? _studentTaps;
  StreamSubscription<List<ConnectivityResult>>? _net;
  DateTime _pausedAt = DateTime.now();

  DeskSection get section => _section;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  void _afterFirstFrame() {
    if (!mounted) return;
    final store = context.storeRead;
    final reminders = RemindersScope.of(context);
    _messages = store.messages.listen((m) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m), width: 480));
    });
    _taps = reminders.taps.listen(openLesson);
    _studentTaps = reminders.studentTaps.listen(openStudent);
    final launched = reminders.launchLessonId;
    if (launched != null) {
      reminders.launchLessonId = null;
      openLesson(launched);
    }
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) store.sync();
    });
    final settings = SettingsScope.read(context);
    if (settings.remindersEnabled || (store.isAdmin && settings.othersEvents)) reminders.requestPermission();
    checkForUpdate(context);
    AppWindows.main?.adoptLeftovers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On the Mac "inactive" is the window losing focus; a refresh when it
    // comes back after a while picks up what others changed meanwhile.
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_pausedAt).inMinutes >= 2) {
      context.storeRead.sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    _taps?.cancel();
    _studentTaps?.cancel();
    _net?.cancel();
    super.dispose();
  }

  // --- commands (sidebar, menu bar, shortcuts) ----------------------------

  void go(DeskSection s) {
    if (s.superOnly && !context.storeRead.isSuperAdmin) return;
    setState(() {
      _section = s;
      _visited.add(s);
    });
  }

  /// Runs [action] once the split view of [s] exists (it is built lazily).
  void _inSplit(DeskSection s, void Function(SplitViewState split) action) {
    go(s);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final split = _splits[s]!.currentState;
      if (split != null) action(split);
    });
  }

  /// From a reminder: that lesson's day in the schedule, its card on the right.
  void openLesson(String lessonId) {
    final lesson = context.storeRead.data.lessonById[lessonId];
    _inSplit(DeskSection.schedule, (split) {
      if (lesson != null) _schedule.currentState?.goToDate(parseDate(lesson.date));
      split.open(LessonScreen(lessonId: lessonId));
    });
  }

  void newLesson() {
    final store = context.storeRead;
    _inSplit(DeskSection.schedule, (split) {
      final day = _schedule.currentState?.day ?? DateTime.now();
      split.open(LessonEditScreen(presetDate: isoDate(day), presetOwnerId: store.teacherFilter));
    });
  }

  void newStudent() => _inSplit(DeskSection.students, (split) => split.open(const StudentEditScreen()));

  /// Today in the schedule, or this week in the studio calendar.
  void today() {
    if (_section == DeskSection.calendar) return _calendar.currentState?.thisWeek();
    _inSplit(DeskSection.schedule, (_) => _schedule.currentState?.goToDate(DateTime.now()));
  }

  /// A day back or forward in the schedule; a week in the studio calendar.
  void shiftDay(int days) {
    if (_section == DeskSection.calendar) return _calendar.currentState?.shiftWeek(days);
    _inSplit(DeskSection.schedule, (_) {
      final s = _schedule.currentState;
      if (s != null) s.goToDate(s.day.add(Duration(days: days)));
    });
  }

  /// The report of the current section, if it has one.
  ExportableScreen? get _exportable => switch (_section) {
    DeskSection.payroll => _payroll.currentState,
    DeskSection.report => _report.currentState,
    DeskSection.print => _printCosts.currentState,
    _ => null,
  };

  void export(ExportFormat format) => _exportable?.exportAs(format);

  /// A student's card, next to the list of students.
  void openStudent(String id) =>
      _inSplit(DeskSection.students, (split) => split.open(StudentCardScreen(studentId: id)));

  /// A teacher's schedule (the sidebar then says "Переглядаєте як").
  void openTeacher(String id) {
    context.storeRead.teacherFilter = id;
    go(DeskSection.schedule);
  }

  bool _searching = false;

  /// The ⌘K palette. Ignored while it is already open (⌘K from inside it).
  Future<void> openSearch() async {
    if (_searching) return;
    _searching = true;
    try {
      final windows = AppWindows.main;
      final store = context.storeRead;
      await showCommandPalette(
        context,
        commands: _paletteCommands(store),
        openStudent: openStudent,
        openStudentWindow: windows == null
            ? null
            : (id) {
                final s = store.data.studentById[id];
                if (s != null) windows.openStudent(s);
              },
        openLesson: openLesson,
        openTeacher: openTeacher,
      );
    } finally {
      _searching = false;
    }
  }

  /// The menu bar's commands, for the palette.
  List<PaletteCommand> _paletteCommands(AppStore store) {
    final settings = SettingsScope.read(context);
    String key(DeskSection s) => s.key == LogicalKeyboardKey.comma ? '⌘,' : '⌘${s.key.keyLabel}';
    return [
      for (final s in DeskSection.values)
        if (!s.superOnly || store.isSuperAdmin)
          PaletteCommand(
            title: s.label,
            icon: s.icon,
            shortcut: key(s),
            navigation: true,
            keywords: switch (s) {
              DeskSection.payroll => 'зарплата зп оплата',
              DeskSection.print => 'собівартість пластик принтери',
              DeskSection.parents => 'батьки паролі доступ',
              DeskSection.report => 'борги оплачено',
              DeskSection.calendar => 'тиждень сітка',
              _ => '',
            },
            run: () => go(s),
          ),
      PaletteCommand(title: 'Нове заняття', icon: Icons.add_rounded, shortcut: '⌘N', run: newLesson),
      PaletteCommand(title: 'Новий учень', icon: Icons.person_add_alt_1_rounded, shortcut: '⇧⌘N', run: newStudent),
      if (store.isSuperAdmin)
        PaletteCommand(title: 'Новий кабінет батьків', icon: Icons.favorite_rounded, run: newParentAccount),
      PaletteCommand(
        title: _section == DeskSection.calendar ? 'Цей тиждень' : 'Сьогодні',
        icon: Icons.today_rounded,
        shortcut: '⌘T',
        run: today,
      ),
      if (_exportable != null) ...[
        PaletteCommand(
          title: 'Експортувати в Excel',
          icon: Icons.table_view_rounded,
          shortcut: '⌘E',
          keywords: 'xlsx таблиця',
          run: () => export(ExportFormat.xlsx),
        ),
        PaletteCommand(
          title: 'Експортувати в PDF',
          icon: Icons.picture_as_pdf_rounded,
          shortcut: '⇧⌘E',
          run: () => export(ExportFormat.pdf),
        ),
      ],
      PaletteCommand(title: 'Синхронізувати', icon: Icons.sync_rounded, shortcut: '⌘R', keywords: 'оновити', run: sync),
      if (store.teacherFilter != null)
        PaletteCommand(
          title: 'Уся студія (зняти фільтр викладача)',
          icon: Icons.groups_rounded,
          run: () => store.teacherFilter = null,
        ),
      PaletteCommand(title: 'Мій профіль', icon: Icons.account_circle_rounded, run: editProfile),
      PaletteCommand(
        title: 'Тема: світла',
        icon: Icons.light_mode_rounded,
        run: () => settings.themeMode = ThemeMode.light,
      ),
      PaletteCommand(
        title: 'Тема: темна',
        icon: Icons.dark_mode_rounded,
        run: () => settings.themeMode = ThemeMode.dark,
      ),
      PaletteCommand(
        title: 'Тема: як у системі',
        icon: Icons.brightness_auto_rounded,
        run: () => settings.themeMode = ThemeMode.system,
      ),
      PaletteCommand(
        title: 'Перевірити оновлення',
        icon: Icons.system_update_rounded,
        run: () => checkForUpdate(context, manual: true),
      ),
      PaletteCommand(title: 'Вийти з акаунта', icon: Icons.logout_rounded, run: signOut),
    ];
  }

  void newParentAccount() {
    go(DeskSection.parents);
    WidgetsBinding.instance.addPostFrameCallback((_) => _parents.currentState?.create());
  }

  void sync() => context.storeRead.sync();

  void editProfile() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: 560, height: 700, child: ProfileScreen(target: ctx.storeRead.me)),
      ),
    );
  }

  Future<void> signOut() async {
    final store = context.storeRead;
    if (store.pendingCount > 0) {
      final ok = await confirmDialog(
        context,
        'Є ${store.pendingCount} змін, які ще не надіслано на сервер. Якщо вийти зараз, вони пропадуть.',
        title: 'Вийти з акаунта?',
        confirmLabel: 'Вийти',
      );
      if (ok != true) return;
    }
    await AppWindows.main?.discardAll();
    await widget.onSignOut();
  }

  // --- layout -------------------------------------------------------------

  Widget _page(DeskSection s) {
    Widget plain(Widget screen, {double maxWidth = 980}) => Readable(
      maxWidth: maxWidth,
      child: HeroControllerScope.none(
        child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => screen)),
      ),
    );
    switch (s) {
      case DeskSection.schedule:
        return SplitView(
          key: _splits[s],
          list: ScheduleScreen(key: _schedule),
          emptyIcon: Icons.event_rounded,
          emptyText: 'Виберіть заняття в розкладі',
        );
      case DeskSection.students:
        return SplitView(
          key: _splits[s],
          list: const StudentsScreen(),
          listWidth: 400,
          emptyIcon: Icons.person_search_rounded,
          emptyText: 'Виберіть учня зі списку',
        );
      case DeskSection.queue:
        return SplitView(
          key: _splits[s],
          list: const QueueScreen(),
          emptyIcon: Icons.print_rounded,
          emptyText: 'Виберіть модель у черзі',
        );
      case DeskSection.payroll:
        return SplitView(
          key: _splits[s],
          list: PayrollScreen(key: _payroll),
          listWidth: 480,
          emptyIcon: Icons.receipt_long_rounded,
          emptyText: 'Виберіть заняття, щоб побачити деталі',
        );
      case DeskSection.teachers:
        return plain(UsersScreen(onOpenSchedule: () => go(DeskSection.schedule)));
      case DeskSection.calendar:
        return plain(
          StudioCalendarScreen(key: _calendar, onOpenTeacherSchedule: () => go(DeskSection.schedule)),
          maxWidth: double.infinity,
        );
      case DeskSection.print:
        return plain(PrintCostsScreen(key: _printCosts), maxWidth: 1100);
      case DeskSection.parents:
        return plain(ParentAccountsScreen(key: _parents));
      case DeskSection.rates:
        return plain(const RatesScreen(), maxWidth: 1100);
      case DeskSection.report:
        return plain(ReportScreen(key: _report), maxWidth: 1100);
      case DeskSection.settings:
        return plain(const SettingsScreen(), maxWidth: 760);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final sections = DeskSection.values.where((s) => !s.superOnly || store.isSuperAdmin).toList();
    if (!sections.contains(_section)) _section = DeskSection.schedule;

    final body = Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(shell: this, current: _section),
          Expanded(
            child: IndexedStack(
              index: sections.indexOf(_section),
              children: [for (final s in sections) _visited.contains(s) ? _page(s) : const SizedBox.shrink()],
            ),
          ),
        ],
      ),
    );

    if (hasNativeMenuBar) return PlatformMenuBar(menus: _menus(store), child: body);
    // Previewed off the Mac: the same commands as keyboard shortcuts.
    return CallbackShortcuts(
      bindings: {
        for (final s in sections) cmd(s.key, mac: false): () => go(s),
        cmd(LogicalKeyboardKey.keyN, mac: false): newLesson,
        cmd(LogicalKeyboardKey.keyN, shift: true, mac: false): newStudent,
        cmd(LogicalKeyboardKey.keyR, mac: false): sync,
        cmd(LogicalKeyboardKey.keyK, mac: false): openSearch,
        cmd(LogicalKeyboardKey.keyE, mac: false): () => export(ExportFormat.xlsx),
        cmd(LogicalKeyboardKey.keyE, shift: true, mac: false): () => export(ExportFormat.pdf),
        cmd(LogicalKeyboardKey.keyT, mac: false): today,
        cmd(LogicalKeyboardKey.bracketLeft, mac: false): () => shiftDay(-1),
        cmd(LogicalKeyboardKey.bracketRight, mac: false): () => shiftDay(1),
      },
      child: Focus(autofocus: true, child: body),
    );
  }

  List<PlatformMenuItem> _menus(AppStore store) {
    final settings = SettingsScope.read(context);
    PlatformMenuItem item(String label, VoidCallback action, [MenuSerializableShortcut? shortcut]) =>
        PlatformMenuItem(label: label, onSelected: action, shortcut: shortcut);
    PlatformMenuItem theme(String label, ThemeMode mode) =>
        item('${settings.themeMode == mode ? '✓ ' : ''}$label', () => settings.themeMode = mode);
    return [
      PlatformMenu(
        label: 'Stemik Admin',
        menus: [
          if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.about))
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          PlatformMenuItemGroup(
            members: [
              item('Налаштування…', () => go(DeskSection.settings), cmd(LogicalKeyboardKey.comma)),
              item('Перевірити оновлення…', () => checkForUpdate(context, manual: true)),
            ],
          ),
          const PlatformMenuItemGroup(
            members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.servicesSubmenu)],
          ),
          const PlatformMenuItemGroup(
            members: [
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
              PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
            ],
          ),
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ],
      ),
      PlatformMenu(
        label: 'Файл',
        menus: [
          PlatformMenuItemGroup(
            members: [
              item('Нове заняття', newLesson, cmd(LogicalKeyboardKey.keyN)),
              item('Новий учень', newStudent, cmd(LogicalKeyboardKey.keyN, shift: true)),
              if (store.isSuperAdmin) item('Новий кабінет батьків', newParentAccount),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Експортувати в Excel…',
                shortcut: cmd(LogicalKeyboardKey.keyE),
                onSelected: _exportable == null ? null : () => export(ExportFormat.xlsx),
              ),
              PlatformMenuItem(
                label: 'Експортувати в PDF…',
                shortcut: cmd(LogicalKeyboardKey.keyE, shift: true),
                onSelected: _exportable == null ? null : () => export(ExportFormat.pdf),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [item('Синхронізувати', sync, cmd(LogicalKeyboardKey.keyR)), item('Мій профіль…', editProfile)],
          ),
          item('Вийти з акаунта ${store.me.fullName}…', signOut),
        ],
      ),
      PlatformMenu(
        label: 'Перейти',
        menus: [
          PlatformMenuItemGroup(members: [item('Пошук…', openSearch, cmd(LogicalKeyboardKey.keyK))]),
          PlatformMenuItemGroup(
            members: [for (final s in DeskSection.workspace) item(s.label, () => go(s), cmd(s.key))],
          ),
          PlatformMenuItemGroup(
            members: [
              for (final s in DeskSection.admin)
                if (!s.superOnly || store.isSuperAdmin) item(s.label, () => go(s), cmd(s.key)),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              item(_section == DeskSection.calendar ? 'Цей тиждень' : 'Сьогодні', today, cmd(LogicalKeyboardKey.keyT)),
              item(
                _section == DeskSection.calendar ? 'Попередній тиждень' : 'Попередній день',
                () => shiftDay(-1),
                cmd(LogicalKeyboardKey.bracketLeft),
              ),
              item(
                _section == DeskSection.calendar ? 'Наступний тиждень' : 'Наступний день',
                () => shiftDay(1),
                cmd(LogicalKeyboardKey.bracketRight),
              ),
            ],
          ),
          if (store.teacherFilter != null)
            item('Уся студія (зняти фільтр викладача)', () => store.teacherFilter = null),
        ],
      ),
      PlatformMenu(
        label: 'Вигляд',
        menus: [
          PlatformMenu(
            label: 'Тема',
            menus: [
              theme('Як у системі', ThemeMode.system),
              theme('Світла', ThemeMode.light),
              theme('Темна', ThemeMode.dark),
            ],
          ),
          if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.toggleFullScreen))
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen),
        ],
      ),
      const PlatformMenu(
        label: 'Вікно',
        menus: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
        ],
      ),
    ];
  }
}

/// The web version's `.studio-sidebar`: brand, profile, whose workspace is
/// shown, the two groups of sections, sync state and sign-out.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.shell, required this.current});
  final DesktopShellState shell;
  final DeskSection current;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final settings = SettingsScope.of(context);
    final c = context.c;
    final me = store.me;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final teacher = store.teacherFilter == null ? null : store.data.profileById[store.teacherFilter];

    Widget nav(DeskSection s, {int? badge, Color? badgeColor}) {
      final active = s == current;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Material(
          color: active ? c.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => shell.go(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(s.icon, size: 19, color: active ? c.brandText : c.inkSoft),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                        color: active ? c.brandText : c.ink,
                      ),
                    ),
                  ),
                  if (badge != null && badge > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                      decoration: BoxDecoration(color: badgeColor ?? c.sand, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: badgeColor == null ? c.sandText : Colors.white,
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

    Widget group(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: c.inkSoft),
      ),
    );

    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const StemikMark(size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stemik', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
                        Text('Адмін-консоль', style: TextStyle(fontSize: 12, color: c.inkSoft)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: dark ? 'Світла тема' : 'Темна тема',
                    onPressed: () => settings.themeMode = dark ? ThemeMode.light : ThemeMode.dark,
                    icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Material(
                color: c.paper,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: shell.editProfile,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Avatar(initial: me.initials, url: me.photo, size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                me.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Tag(
                                roleLabels[me.role] ?? 'Адмін',
                                color: me.isSuperAdmin ? c.vr : c.brandText,
                                soft: me.isSuperAdmin ? c.vrSoft : c.brandSoft,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _SearchButton(onTap: shell.openSearch),
              if (teacher != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  decoration: BoxDecoration(color: c.alertSoft, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Avatar(initial: teacher.initials, url: teacher.photo, size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Переглядаєте як', style: TextStyle(fontSize: 11, color: c.alertText)),
                            Text(
                              teacher.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Уся студія',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => store.teacherFilter = null,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    group('Робочий кабінет'),
                    nav(DeskSection.schedule),
                    nav(DeskSection.students, badge: store.data.students.length),
                    nav(DeskSection.queue, badge: store.pendingPrintCount, badgeColor: c.alert),
                    nav(DeskSection.payroll),
                    group('Адміністрування'),
                    for (final s in DeskSection.admin)
                      if (!s.superOnly || store.isSuperAdmin) nav(s),
                  ],
                ),
              ),
              nav(DeskSection.settings),
              const SizedBox(height: 6),
              _SyncLine(store: store),
              const SizedBox(height: 4),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: c.danger, alignment: Alignment.centerLeft),
                onPressed: shell.signOut,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Вийти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Пошук ⌘K" under the profile: opens the palette.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.paper,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: c.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Пошук',
                  style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: c.lineStrong),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hasNativeMenuBar ? '⌘K' : 'Ctrl K',
                  style: TextStyle(fontSize: 11.5, color: c.inkSoft, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The web's "Supabase підключено" line, with the offline outbox's state.
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pending = store.pendingCount;
    final (Color dot, String text) = store.refreshing
        ? (c.brand, 'Оновлення…')
        : store.connection == Connection.offline
        ? (c.alert, pending > 0 ? 'Офлайн · чекають $pending' : 'Офлайн — дані з Mac')
        : pending > 0
        ? (c.alert, 'Надсилання: $pending')
        : store.live
        ? (c.success, 'Наживо · зміни приходять самі')
        : (c.success, 'Supabase підключено');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showSyncSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12.5, color: c.inkSoft, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.sync_rounded, size: 16, color: c.inkSoft),
          ],
        ),
      ),
    );
  }
}

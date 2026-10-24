import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/reminders.dart';
import '../services/updates.dart';
import '../util/dates.dart';
import 'more/more_screen.dart';
import 'payroll_screen.dart';
import 'queue_screen.dart';
import 'schedule/lesson_screen.dart';
import 'schedule/schedule_screen.dart';
import 'scope.dart';
import 'students/students_screen.dart';
import 'theme.dart';

class RemindersScope extends InheritedWidget {
  const RemindersScope({super.key, required this.reminders, required super.child});
  final Reminders reminders;

  static Reminders of(BuildContext context) => context.getInheritedWidgetOfExactType<RemindersScope>()!.reminders;

  @override
  bool updateShouldNotify(RemindersScope old) => old.reminders != reminders;
}

/// The signed-in app: five tabs, each its own navigator so a tab keeps its
/// place when you switch away and back.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignOut});
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _navigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final _schedule = GlobalKey<ScheduleScreenState>();
  StreamSubscription<String>? _messages;
  StreamSubscription<String>? _taps;
  StreamSubscription<List<ConnectivityResult>>? _net;
  DateTime _pausedAt = DateTime.now();

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
        ..showSnackBar(SnackBar(content: Text(m)));
    });
    _taps = reminders.taps.listen(_openLesson);
    final launched = reminders.launchLessonId;
    if (launched != null) {
      reminders.launchLessonId = null;
      _openLesson(launched);
    }
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) store.sync();
    });
    if (SettingsScope.read(context).remindersEnabled) reminders.requestPermission();
    checkForUpdate(context);
  }

  /// From a reminder: jump to that lesson's day and open its card.
  void _openLesson(String lessonId) {
    final store = context.storeRead;
    final lesson = store.data.lessonById[lessonId];
    setState(() => _tab = 0);
    final nav = _navigators[0].currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    if (lesson != null) _schedule.currentState?.goToDate(parseDate(lesson.date));
    nav.push(MaterialPageRoute(builder: (_) => LessonScreen(lessonId: lessonId)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_pausedAt).inSeconds > 30) {
      context.storeRead.sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    _taps?.cancel();
    _net?.cancel();
    super.dispose();
  }

  void _select(int i) {
    if (i == _tab) {
      // Second tap on the current tab: back to its first screen.
      _navigators[i].currentState?.popUntil((r) => r.isFirst);
      if (i == 0) _schedule.currentState?.goToDate(DateTime.now());
      return;
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final queue = store.pendingPrintCount;
    final pages = <Widget>[
      ScheduleScreen(key: _schedule),
      const StudentsScreen(),
      const QueueScreen(),
      const PayrollScreen(),
      MoreScreen(onSignOut: widget.onSignOut, onOpenSchedule: () => _select(0)),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navigators[_tab].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < pages.length; i++)
              HeroControllerScope.none(
                child: Navigator(
                  key: _navigators[i],
                  onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => pages[i]),
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _select,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Розклад',
            ),
            const NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Учні',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: queue > 0,
                label: Text('$queue'),
                backgroundColor: c.alert,
                child: const Icon(Icons.print_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: queue > 0,
                label: Text('$queue'),
                backgroundColor: c.alert,
                child: const Icon(Icons.print_rounded),
              ),
              label: 'Друк',
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
              label: store.isAdmin ? 'Зарплати' : 'Зарплата',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: store.pendingCount > 0,
                smallSize: 8,
                backgroundColor: c.alert,
                child: const Icon(Icons.menu_rounded),
              ),
              label: 'Ще',
            ),
          ],
        ),
      ),
    );
  }
}

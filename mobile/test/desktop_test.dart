import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stemik/data/store.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/demo/demo_parent_api.dart';
import 'package:stemik/desktop/desktop_shell.dart';
import 'package:stemik/services/reminders.dart';
import 'package:stemik/services/settings.dart';
import 'package:stemik/ui/app.dart';
import 'package:stemik/ui/login_screen.dart';
import 'package:stemik/ui/scope.dart';
import 'package:stemik/ui/shell.dart';
import 'package:stemik/ui/students/student_card_screen.dart';
import 'package:stemik/ui/students/students_screen.dart';
import 'package:stemik/ui/theme.dart';

import 'store_test.dart' show MemoryFiles;

/// Runs the test as on a Mac.
final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

/// The macOS app, signed in as [role] in the demo studio, in a Mac-sized
/// window.
Future<AppStore> pumpMacApp(WidgetTester tester, {required String role}) async {
  tester.view.physicalSize = const Size(1360, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  final api = DemoApi(role: role);
  final store = AppStore(api, MemoryFiles());
  await tester.pumpWidget(
    SettingsScope(
      settings: settings,
      child: StoreScope(
        store: store,
        child: RemindersScope(
          reminders: Reminders(store, settings),
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
            home: AuthGate(api: api, parentApi: DemoParentApi()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// Takes the app down and stops the store's retry timer.
Future<void> closeMacApp(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(const SizedBox());
  await store.close(discardPending: false);
}

void main() {
  testWidgets('a teacher is turned away with a note, and there is no parents\' side', (tester) async {
    final store = await pumpMacApp(tester, role: 'teacher');
    expect(find.byType(DesktopShell), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('для адміністраторів студії'), findsOneWidget);
    expect(find.text('Батьки'), findsNothing);
    expect(find.text('Адмін-консоль студії'), findsOneWidget);
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('a superadmin gets the sidebar with every section', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    expect(find.byType(DesktopShell), findsOneWidget);
    for (final label in [
      'Розклад',
      'Учні',
      'Черга друку',
      'Зарплати',
      'Викладачі',
      'Календар',
      'Друк (бета)',
      'Тарифи',
      'Звіт студії',
      'Кабінети батьків',
    ]) {
      expect(find.widgetWithText(InkWell, label), findsOneWidget, reason: label);
    }
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('an admin has the calendar and printing, but no rates, report or parents', (tester) async {
    final store = await pumpMacApp(tester, role: 'admin');
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Викладачі'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Календар'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Друк (бета)'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Тарифи'), findsNothing);
    expect(find.widgetWithText(InkWell, 'Звіт студії'), findsNothing);
    expect(find.widgetWithText(InkWell, 'Кабінети батьків'), findsNothing);
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('a student opens next to the list, and the list stays', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    await tester.tap(find.widgetWithText(InkWell, 'Учні'));
    await tester.pumpAndSettle();
    expect(find.text('Виберіть учня зі списку'), findsOneWidget);

    final first = store.data.students.first;
    await tester.tap(find.descendant(of: find.byType(StudentsScreen), matching: find.text(first.name)).first);
    await tester.pumpAndSettle();
    expect(find.byType(StudentsScreen), findsOneWidget);
    expect(find.byType(StudentCardScreen), findsOneWidget);
    expect(find.text('Виберіть учня зі списку'), findsNothing);

    // Another student replaces the card instead of stacking on it.
    final second = store.data.students[1];
    await tester.tap(find.descendant(of: find.byType(StudentsScreen), matching: find.text(second.name)).first);
    await tester.pumpAndSettle();
    expect(find.byType(StudentCardScreen), findsOneWidget);
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('sections keep their place when you come back', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    final shell = tester.state<DesktopShellState>(find.byType(DesktopShell));
    shell.go(DeskSection.students);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(StudentsScreen), matching: find.text(store.data.students.first.name)).first,
    );
    await tester.pumpAndSettle();

    shell.go(DeskSection.report);
    await tester.pumpAndSettle();
    expect(find.byType(StudentCardScreen), findsNothing);

    shell.go(DeskSection.students);
    await tester.pumpAndSettle();
    expect(find.byType(StudentCardScreen), findsOneWidget);
    await closeMacApp(tester, store);
  }, variant: mac);
}

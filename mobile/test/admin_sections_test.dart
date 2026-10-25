import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/desktop/desktop_shell.dart';
import 'package:stemik/ui/admin/parent_accounts_screen.dart';
import 'package:stemik/ui/admin/print_costs_screen.dart';
import 'package:stemik/ui/admin/studio_calendar_screen.dart';
import 'package:stemik/util/dates.dart';
import 'package:stemik/util/domain.dart';

import 'desktop_test.dart' show closeMacApp, mac, pumpMacApp;

void main() {
  test('parent phones are normalized and formatted like sql/0018', () {
    expect(normalizeParentPhone('067 123 45 67'), '380671234567');
    expect(normalizeParentPhone('+380 (67) 123-45-67'), '380671234567');
    expect(normalizeParentPhone('671234567'), '380671234567');
    expect(normalizeParentPhone('80671234567'), '380671234567');
    expect(formatParentPhone('0671234567'), '+380 67 123 45 67');
    expect(parentPasswordMessage('380671234567', 'abc'), contains('Логін: +380 67 123 45 67\nПароль: abc'));
  });

  test('print summaries read like the web', () {
    expect(printSummary(42, 125), '42 г · 2:05 год');
    expect(printSummary(12.5, null), '12,5 г');
    expect(printSummary(null, null), isNull);
    expect(pluralModels(1), '1 модель');
    expect(pluralModels(3), '3 моделі');
    expect(pluralModels(11), '11 моделей');
  });

  testWidgets('the studio calendar shows the week as a timetable', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    final shell = tester.state<DesktopShellState>(find.byType(DesktopShell));
    shell.go(DeskSection.calendar);
    await tester.pumpAndSettle();
    expect(find.byType(StudioCalendarScreen), findsOneWidget);

    final weekStart = isoDate(startOfWeek(DateTime.now()));
    final weekEnd = addDays(weekStart, 6);
    final lesson = store.data.lessons.firstWhere(
      (l) => l.date.compareTo(weekStart) >= 0 && l.date.compareTo(weekEnd) <= 0 && l.time != null,
    );
    expect(find.text(lesson.theme), findsWidgets);

    // A week back: other lessons, and ⌘T comes back to this week.
    shell.shiftDay(-1);
    await tester.pumpAndSettle();
    expect(find.textContaining(weekRangeLabel(startOfWeek(DateTime.now()))), findsNothing);
    shell.today();
    await tester.pumpAndSettle();
    expect(find.textContaining(weekRangeLabel(startOfWeek(DateTime.now()))), findsOneWidget);
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('print costs: analytics for the month and the directories', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    tester.state<DesktopShellState>(find.byType(DesktopShell)).go(DeskSection.print);
    await tester.pumpAndSettle();
    expect(find.byType(PrintCostsScreen), findsOneWidget);
    expect(find.text('Витрачено за період'), findsOneWidget);
    expect(find.text('За напрямком'), findsOneWidget);

    await tester.tap(find.text('Принтери і пластик'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Creality K1'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'PETG'), findsOneWidget);

    await tester.tap(find.text('Додати принтер'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Bambu Lab P1S').last, 'Prusa MK4');
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.descendant(of: find.byType(PrintCostsScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Зберегти'));
    await tester.pumpAndSettle();
    expect((store.api as DemoApi).printers.map((p) => p['name']), contains('Prusa MK4'));
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('a new parent account shows its password once', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    tester.state<DesktopShellState>(find.byType(DesktopShell)).go(DeskSection.parents);
    await tester.pumpAndSettle();
    expect(find.byType(ParentAccountsScreen), findsOneWidget);
    expect(find.text('Сидоренко Сергій'), findsOneWidget);

    await tester.tap(find.text('Новий кабінет'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Телефон (логін)'), '063 555 44 33');
    await tester.enterText(find.widgetWithText(TextField, "Ім'я батьків"), 'Мороз Андрій');
    await tester.tap(find.widgetWithText(FilterChip, store.data.students.first.name));
    await tester.pump();
    await tester.tap(find.text('Створити й отримати пароль'));
    await tester.pumpAndSettle();

    expect(find.text('Кабінет батьків створено'), findsOneWidget);
    expect(find.textContaining('Логін: +380 63 555 44 33'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Мороз Андрій'), findsOneWidget);
    final api = store.api as DemoApi;
    final created = api.parentAccounts.firstWhere((a) => a['phone'] == '380635554433');
    expect(api.parentLinks.where((l) => l['parent_id'] == created['id']), hasLength(1));
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('marking a model printed asks for its weight and time', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    tester.state<DesktopShellState>(find.byType(DesktopShell)).go(DeskSection.queue);
    await tester.pumpAndSettle();
    final before = store.pendingPrintCount;
    await tester.tap(find.text('Не надруковано').first);
    await tester.pumpAndSettle();
    expect(find.text('Вага моделі'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await tester.pump();
    expect(find.text('Вкажіть вагу моделі в грамах'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Вага моделі'), '37,5');
    await tester.enterText(find.widgetWithText(TextField, 'Час друку'), '1');
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(store.pendingPrintCount, before - 1);
    // Through the outbox to the server, with the cost inputs.
    await tester.pump(const Duration(seconds: 1));
    final work = (store.api as DemoApi).works.firstWhere((w) => w['weight_g'] == 37.5);
    expect(work['printed'], isTrue);
    expect(work['print_minutes'], 60);
    expect(store.pendingCount, 0);
    await closeMacApp(tester, store);
  }, variant: mac);
}

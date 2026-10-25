import 'package:flutter/widgets.dart' show EditableText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/desktop/command_palette.dart';
import 'package:stemik/desktop/desktop_shell.dart';
import 'package:stemik/ui/more/report_screen.dart';
import 'package:stemik/ui/students/student_card_screen.dart';
import 'package:stemik/util/dates.dart';
import 'package:stemik/util/search.dart';

import 'desktop_test.dart' show closeMacApp, mac, pumpMacApp;
import 'store_test.dart' show MemoryFiles, openStore;

void main() {
  test('a match at the start beats one at a word start, which beats one inside', () {
    expect(matchScore('злата кравець', ['злат']), 4);
    expect(matchScore('злата кравець', ['крав']), 3);
    expect(matchScore('злата кравець', ['ата']), 1);
    expect(matchScore('злата кравець', ['злат', 'нема']), 0);
    expect(searchTokens("  П'ятниця +380 (67) "), ['пятниця', '380', '67']);
  });

  test('finds students, lessons and teachers the way people type them', () async {
    final store = await openStore(DemoApi(), MemoryFiles());
    final data = store.data;
    final now = DateTime.now();
    List<String> students(String q) => [
      for (final h in searchStudio(data, q, now: now).students) data.studentById[h.id]!.name,
    ];

    expect(students('злат').first, 'Злата Кравець');
    expect(students('кравець злата'), ['Злата Кравець']);
    // By the parents' names and by any part of the phone, typed any way.
    final s = data.students.firstWhere((s) => s.phone != null);
    final digits = s.phone!.replaceAll(RegExp(r'\D'), '');
    expect(students(digits.substring(digits.length - 7)), contains(s.name));
    expect(students('0${digits.substring(3, 5)} ${digits.substring(5)}'), contains(s.name));
    expect(students(s.parentsName.split(' ').first), contains(s.name));

    // A lesson by theme, date and weekday ("пятниця" without the apostrophe).
    final lesson = data.lessons.firstWhere((l) => parseDate(l.date).weekday == DateTime.friday);
    final d = parseDate(lesson.date);
    final byDate = searchStudio(
      data,
      '${d.day}.${d.month.toString().padLeft(2, '0')} ${lesson.theme.split(' ').first}',
      now: now,
    ).lessons;
    expect(byDate.map((h) => h.id), contains(lesson.id));
    final friday = searchStudio(data, 'пятниця', now: now, limit: 100).lessons;
    expect(friday, isNotEmpty);
    expect(friday.every((h) => parseDate(data.lessonById[h.id]!.date).weekday == DateTime.friday), isTrue);

    // Several words narrow it down: Anna's 3D lessons only.
    final anna3d = searchStudio(data, 'шевчук 3d', now: now, limit: 100).lessons;
    expect(anna3d, isNotEmpty);
    for (final h in anna3d) {
      final l = data.lessonById[h.id]!;
      expect(data.profileById[l.ownerId]!.fullName, contains('Шевчук'));
      expect(l.course, startsWith('3D'));
    }

    expect(searchStudio(data, 'бонд', now: now).teachers.map((h) => data.profileById[h.id]!.fullName), [
      'Бондар Максим',
    ]);
    expect(searchStudio(data, '   ', now: now).isEmpty, isTrue);
    await store.close(discardPending: false);
  });

  testWidgets('⌘K: type, ↵ opens the student, and it is then among the recent', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    final shell = tester.state<DesktopShellState>(find.byType(DesktopShell));

    // The sidebar button opens it too.
    await tester.tap(find.text('Пошук'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.text('ПЕРЕЙТИ'), findsOneWidget);

    await tester.enterText(
      find.descendant(of: find.byType(CommandPalette), matching: find.byType(EditableText)),
      'злата',
    );
    await tester.pump();
    expect(find.text('УЧНІ'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(shell.section, DeskSection.students);
    expect(find.byType(StudentCardScreen), findsOneWidget);

    shell.openSearch();
    await tester.pumpAndSettle();
    expect(find.text('НЕЩОДАВНІ'), findsOneWidget);
    expect(find.descendant(of: find.byType(CommandPalette), matching: find.text('Злата Кравець')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('⌘K: a section by name comes first; arrows move the choice', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    final shell = tester.state<DesktopShellState>(find.byType(DesktopShell));
    shell.openSearch();
    await tester.pumpAndSettle();
    final field = find.descendant(of: find.byType(CommandPalette), matching: find.byType(EditableText));

    await tester.enterText(field, 'звіт');
    await tester.pump();
    expect(find.text('КОМАНДИ'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(shell.section, DeskSection.report);
    expect(find.byType(ReportScreen), findsOneWidget);

    // ↓ then ↵ takes the second line: with nothing typed, "Перейти" starts
    // with Розклад, then Учні.
    shell.openSearch();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(shell.section, DeskSection.students);
    await closeMacApp(tester, store);
  }, variant: mac);
}

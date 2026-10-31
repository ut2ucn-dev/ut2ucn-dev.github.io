import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/desktop/desktop_shell.dart';
import 'package:stemik/ui/admin/print_costs_screen.dart';
import 'package:stemik/ui/schedule/lesson_edit_screen.dart';
import 'package:stemik/ui/widgets.dart';
import 'package:stemik/util/dates.dart';
import 'package:stemik/util/domain.dart';

import 'desktop_test.dart' show closeMacApp, mac, pumpMacApp;

/// Lets the (demo) server answer: pumpAndSettle alone doesn't wait for timers.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  test('series edits carry students over as a difference', () {
    expect(seriesStudentIds(['a', 'b'], ['d'], ['b']), ['a', 'd']);
    // A later lesson with its own extra student keeps it.
    expect(seriesStudentIds(['a', 'b', 'c'], ['d'], ['b']), ['a', 'c', 'd']);
    // Already there: not added twice.
    expect(seriesStudentIds(['a', 'd'], ['d'], const []), ['a', 'd']);
  });

  test('print directories: saving keeps ids, so a retry never duplicates', () async {
    final api = DemoApi(role: 'superadmin');
    final before = api.printers.length;
    final ids = await api.savePrintRows('printers', [
      {'id': null, 'name': 'Snapmaker U1', 'power_watts': 127, 'depreciation_per_hour': 15, 'active': true},
    ]);
    expect(ids, hasLength(1));
    await api.savePrintRows('printers', [
      {'id': ids.first, 'name': 'Snapmaker U1', 'power_watts': 130, 'depreciation_per_hour': 15, 'active': true},
    ]);
    expect(api.printers, hasLength(before + 1));
    expect(api.printers.firstWhere((p) => p['id'] == ids.first)['power_watts'], 130);

    api.works.add({'id': 'w-x', 'printer_id': ids.first, 'printed': true});
    expect(await api.countWorksUsing('printer_id', ids.first), 1);
    await api.setPrintRowActive('printers', ids.first, false);
    expect(api.printers.firstWhere((p) => p['id'] == ids.first)['active'], isFalse);
    await api.deletePrintRow('printers', ids.first);
    expect(api.printers.where((p) => p['id'] == ids.first), isEmpty);
    expect(api.works.firstWhere((w) => w['id'] == 'w-x')['printer_id'], isNull);
  });

  testWidgets('editing a series lesson can update the later lessons too', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    final api = store.api as DemoApi;
    final teacher = api.profiles.firstWhere((p) => p['role'] == 'teacher');
    final s = api.students.map((x) => x['id'] as String).toList();
    final names = {for (final x in api.students) x['id'] as String: x['name'] as String};
    final base = todayStr();
    DbRowSeries row(String id, int week, List<String> ids) => {
      'id': id,
      'owner_id': teacher['id'],
      'series_id': 'ser-test',
      'date': addDays(base, 7 * week),
      'time': '17:00:00',
      'theme': 'Серія $id',
      'course': courseOptions.first,
      'format': 'group',
      'student_ids': ids,
      'extra_service': false,
      'duration_minutes': 60,
      'room': null,
      'substitute_owner_id': null,
      'completed': false,
      'payroll_amount': 0,
      'price_amount': 0,
    };
    api.lessons.addAll([
      row('ser-0', 1, [s[0], s[1]]),
      row('ser-1', 2, [s[0], s[1]]),
      row('ser-2', 3, [s[0], s[1], s[2]]),
    ]);
    // Not awaited: the shell's own sync is in flight, and pumping lets both finish.
    unawaited(store.sync());
    await settle(tester);

    Future<void> openEdit() async {
      final lesson = store.data.lessons.firstWhere((l) => l.id == 'ser-0');
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => LessonEditScreen(lesson: lesson)));
      await tester.pumpAndSettle();
    }

    Future<void> tapStudent(String id) async {
      final chip = find.widgetWithText(PickChip, names[id]!);
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.descendant(of: find.byType(LessonEditScreen), matching: find.byType(Scrollable)).first,
      );
      await tester.tap(chip);
      await tester.pump();
    }

    // Add s[3], remove s[1]; apply to the following lessons too.
    await openEdit();
    await tapStudent(s[3]);
    await tapStudent(s[1]);
    await tester.tap(find.text('Зберегти'));
    await tester.pumpAndSettle();
    expect(find.text('Змінити серію'), findsOneWidget);
    expect(find.textContaining('учнів +1 −1'), findsOneWidget);
    await tester.tap(find.text('Це і наступні (3)'));
    await settle(tester);

    List<String> ids(String id) => (api.lessons.firstWhere((l) => l['id'] == id)['student_ids'] as List).cast<String>();
    expect(ids('ser-0'), unorderedEquals([s[0], s[3]]));
    expect(ids('ser-1'), unorderedEquals([s[0], s[3]]));
    expect(ids('ser-2'), unorderedEquals([s[0], s[2], s[3]]), reason: 'its own extra student stays');

    // "Тільки це" changes the edited lesson only.
    await openEdit();
    await tapStudent(s[4]);
    await tester.tap(find.text('Зберегти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тільки це'));
    await settle(tester);
    expect(ids('ser-0'), contains(s[4]));
    expect(ids('ser-1'), isNot(contains(s[4])));
    await closeMacApp(tester, store);
  }, variant: mac);

  testWidgets('print directories: consumption in kW, instant hide, delete with confirmation', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    final api = store.api as DemoApi;
    tester.state<DesktopShellState>(find.byType(DesktopShell)).go(DeskSection.print);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Принтери і пластик'));
    await settle(tester);

    expect(find.text('(Вага моделі × Вартість філаменту)'), findsOneWidget);
    expect(find.text('Споживання, кВт/год'), findsOneWidget);
    // Bambu Lab P1S is 350 W in the demo data: shown as 0.35 kW.
    expect(find.widgetWithText(TextField, '0.35'), findsOneWidget);

    // Hide is saved at once, without "Зберегти".
    final bambu = api.printers.firstWhere((p) => p['name'] == 'Bambu Lab P1S');
    await tester.tap(find.text('Приховати').first);
    await settle(tester);
    expect(bambu['active'], isFalse);

    // Delete a printer a model uses: the confirmation says so.
    final creality = api.printers.firstWhere((p) => p['name'] == 'Creality K1');
    api.works.add({'id': 'w-del', 'printer_id': creality['id'], 'printed': true});
    final bin = find.byTooltip('Видалити назавжди').at(1);
    await tester.ensureVisible(bin);
    await tester.pumpAndSettle();
    await tester.tap(bin);
    await settle(tester);
    expect(find.textContaining('«Creality K1»'), findsOneWidget);
    final used = api.works.where((w) => w['printer_id'] == creality['id']).length;
    expect(find.textContaining('указаний у ${pluralModels(used)}'), findsOneWidget);
    await tester.tap(find.text('Так, видалити'));
    await settle(tester);
    expect(api.printers.where((p) => p['name'] == 'Creality K1'), isEmpty);
    expect(api.works.firstWhere((w) => w['id'] == 'w-del')['printer_id'], isNull);

    // kW typed in is saved as watts.
    await tester.enterText(find.widgetWithText(TextField, '0.35'), '0.2');
    final list = find.descendant(of: find.byType(PrintCostsScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Зберегти'), 300, scrollable: list);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(bambu['power_watts'], 200);
    await closeMacApp(tester, store);
  }, variant: mac);
}

typedef DbRowSeries = Map<String, dynamic>;

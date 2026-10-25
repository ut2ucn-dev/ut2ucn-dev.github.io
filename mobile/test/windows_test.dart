import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stemik/data/models.dart';
import 'package:stemik/data/store.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/desktop/windows.dart';
import 'package:stemik/services/settings.dart';
import 'package:stemik/ui/students/student_card_screen.dart';

import 'store_test.dart' show MemoryFiles, openStore, unmarkedPair;

void main() {
  tearDown(() => AppWindows.main = null);

  test("a window starts from the main window's cache but keeps its own files", () async {
    final files = MemoryFiles();
    files.json['snapshot_u.json'] = {'from': 'main'};
    files.json['outbox_u.json'] = {'ops': []};
    final w = WindowFiles(files, 'student-1');

    expect(await w.readJson('snapshot_u.json'), {'from': 'main'});
    // Never the main window's queue: those changes are the main window's to send.
    expect(await w.readJson('outbox_u.json'), isNull);

    await w.writeJson('snapshot_u.json', {'from': 'window'});
    expect(files.json['snapshot_u.json'], {'from': 'main'});
    expect(files.json[windowFiles('student-1', 'snapshot_u.json')], {'from': 'window'});
    expect(await w.readJson('snapshot_u.json'), {'from': 'window'});
  });

  test("what a window couldn't send is taken over by the main window", () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    final api = DemoApi();
    final files = MemoryFiles();
    final main = await openStore(api, files);

    // The window marks attendance while offline, then is closed.
    api.offline = true;
    final window = AppStore(api, WindowFiles(files, 'student-x'));
    await window.open(main.me);
    final (lesson, student) = unmarkedPair(main);
    await window.markAttendance(lesson, student, 'present', paymentMethod: 'cash');
    expect(window.pendingCount, 1);
    await window.shutDown();
    expect(main.pendingCount, 0);

    AppWindows.start(main, files, settings);
    settings.rememberWindow('student-x');
    api.offline = false;
    await AppWindows.main!.adoptLeftovers();
    await main.sync();

    expect(main.pendingCount, 0);
    expect(api.attendance.any((a) => a['lesson_id'] == lesson.id && a['student_id'] == student.id), isTrue);
    expect(settings.openWindows, isEmpty);
    expect(files.json.keys.where((k) => k.startsWith('w_student-x_')), isEmpty);
    await window.close(discardPending: false);
    await main.close(discardPending: false);
  });

  testWidgets("a student's window shows the card and names itself after the student", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    late AppStore store;
    late Student student;
    await tester.runAsync(() async {
      store = await openStore(DemoApi(), MemoryFiles());
      student = store.data.students.first;
    });
    final titles = <String>[];
    await tester.pumpWidget(
      WindowApp(
        store: store,
        settings: settings,
        child: StudentWindow(studentId: student.id, onTitle: titles.add),
      ),
    );
    await tester.pump();
    expect(find.byType(StudentCardScreen), findsOneWidget);
    expect(find.text(student.name), findsWidgets);
    expect(titles, ['${student.name} — Stemik']);
    // Let the card's loading (the demo server answers after a delay; the
    // parents' block loads after the history) finish.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => store.close(discardPending: false));
  });
}

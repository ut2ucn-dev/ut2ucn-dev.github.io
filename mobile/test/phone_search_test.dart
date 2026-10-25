import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stemik/data/store.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/services/settings.dart';
import 'package:stemik/ui/scope.dart';
import 'package:stemik/ui/search_screen.dart';
import 'package:stemik/ui/students/student_card_screen.dart';
import 'package:stemik/ui/theme.dart';

import 'store_test.dart' show MemoryFiles, openStore;

Future<(AppStore, Settings)> pumpSearch(WidgetTester tester, {VoidCallback? onTeacher}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  late AppStore store;
  await tester.runAsync(() async => store = await openStore(DemoApi(), MemoryFiles()));
  await tester.pumpWidget(
    SettingsScope(
      settings: settings,
      child: StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: SearchScreen(onOpenTeacherSchedule: onTeacher),
        ),
      ),
    ),
  );
  return (store, settings);
}

Future<void> finish(WidgetTester tester, AppStore store) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => store.close(discardPending: false));
}

void main() {
  testWidgets('a student found on the phone opens their card and becomes recent', (tester) async {
    final (store, settings) = await pumpSearch(tester);
    expect(find.textContaining("за ім'ям"), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'злат');
    await tester.pump();
    expect(find.text('УЧНІ'), findsOneWidget);
    // No teachers group where picking one has nowhere to go.
    expect(find.text('ВИКЛАДАЧІ'), findsNothing);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(StudentCardScreen), findsOneWidget);
    expect(settings.recentSearch.first, startsWith('student:'));
    await finish(tester, store);
  });

  testWidgets('admins can jump to a teacher’s schedule from it', (tester) async {
    var opened = false;
    final (store, _) = await pumpSearch(tester, onTeacher: () => opened = true);
    await tester.enterText(find.byType(TextField), 'бондар');
    await tester.pump();
    expect(find.text('ВИКЛАДАЧІ'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Бондар Максим').last);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(store.data.profileById[store.teacherFilter]!.fullName, 'Бондар Максим');
    await finish(tester, store);
  });
}

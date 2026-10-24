import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stemik/data/parent_portal.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/demo/demo_parent_api.dart';
import 'package:stemik/services/settings.dart';
import 'package:stemik/ui/login_screen.dart';
import 'package:stemik/ui/parent/parent_home.dart';
import 'package:stemik/ui/scope.dart';
import 'package:stemik/ui/theme.dart';

void main() {
  test('summary counts paid, unpaid, certificates, trials and models like the web portal', () async {
    final api = DemoParentApi();
    final session = await api.login('0671234567', 'pw');
    final portal = await api.fetchPortal(session.token);
    final marko = PortalSummary(portal.students.first, portal.today);

    expect(marko.attended.length, 4);
    expect(marko.unpaid.length, 1);
    expect(marko.due, 470);
    expect(marko.paidCount, 3);
    expect(marko.certificates.length, 1);
    expect(marko.trials.length, 1);
    expect(marko.lessonsLeftInSubscriptions, 2);
    expect(marko.upcoming.first.theme, 'Космічна станція');
    expect(marko.models.length, 4);
    // 3D-course models go to the printer.
    expect(marko.models.first.prints, isTrue);
    expect(marko.courses.map((c) => c.course), contains('Robo AI (Ukit 6-8)'));
  });

  test('a lesson without attendance is upcoming from today on, unmarked before', () {
    final l = PortalLesson({'id': 'x', 'date': '2026-10-24'});
    expect(l.state('2026-10-24'), LessonState.upcoming);
    expect(l.state('2026-10-25'), LessonState.unmarked);
    expect(
      PortalLesson({'id': 'x', 'date': '2026-10-01', 'status': 'present'}).state('2026-10-24'),
      LessonState.unpaid,
    );
  });

  test('a stale token is rejected', () async {
    expect(() => DemoParentApi().fetchPortal('nope'), throwsA(isA<ParentSessionExpired>()));
  });

  testWidgets('portal renders every tab for a signed-in parent', (tester) async {
    SharedPreferences.setMockInitialValues({'parentToken': 'demo-parent-token'});
    final settings = await Settings.load();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      SettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: ParentHome(api: DemoParentApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Марко Коваль'), findsOneWidget);
    expect(find.text('Оплатити онлайн'), findsOneWidget);
    expect(find.text('В РОЗРОБЦІ'), findsOneWidget);

    await tester.tap(find.text('Моделі'));
    await tester.pumpAndSettle();
    expect(find.text('Брелок з іменем'), findsOneWidget);

    await tester.tap(find.text('Оплати'));
    await tester.pumpAndSettle();
    expect(find.text('Абонементи'), findsOneWidget);

    await tester.tap(find.text('Заняття'));
    await tester.pumpAndSettle();
    expect(find.text('Не сплачені'), findsOneWidget);

    await tester.tap(find.text('Софія'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Знайомство з VR'), findsOneWidget);
    expect(settings.parentChildId, 'demo-kid-2');
  });

  testWidgets('parents sign in with phone and password from the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    await tester.pumpWidget(
      SettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: LoginScreen(api: DemoApi(), parentApi: DemoParentApi()),
        ),
      ),
    );
    await tester.tap(find.text('Батьки'));
    await tester.pumpAndSettle();
    expect(find.text('Номер телефону'), findsOneWidget);
    expect(find.text('Забули пароль?'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '067 123 45 67');
    await tester.enterText(find.byType(TextField).last, 'abcd2345');
    await tester.tap(find.text('Увійти'));
    await tester.pumpAndSettle();

    expect(settings.parentToken, 'demo-parent-token');
    expect(settings.lastParentPhone, '067 123 45 67');
    expect(settings.parentLoginMode, isTrue);
  });
}

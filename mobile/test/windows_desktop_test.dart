import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stemik/desktop/desktop_shell.dart';
import 'package:stemik/services/settings.dart';
import 'package:stemik/ui/students/students_screen.dart';

import 'desktop_test.dart' show closeMacApp, pumpMacApp;

/// Runs the test as on Windows.
final windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  testWidgets('Windows: the same admin app, with its menus under the title bar and Ctrl shortcuts', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(MenuBar), findsOneWidget);
    for (final menu in ['Файл', 'Перейти', 'Вигляд']) {
      expect(find.widgetWithText(SubmenuButton, menu), findsOneWidget);
    }
    // What the Mac has in the app's own menu is under File; macOS-only
    // menus are left out.
    expect(find.widgetWithText(SubmenuButton, 'Stemik Admin'), findsNothing);
    expect(find.widgetWithText(SubmenuButton, 'Вікно'), findsNothing);
    expect(find.text('Ctrl+K'), findsOneWidget);

    await tester.tap(find.widgetWithText(SubmenuButton, 'Файл'));
    await tester.pumpAndSettle();
    expect(find.text('Нове заняття'), findsOneWidget);
    expect(find.text('Ctrl+N'), findsOneWidget);
    expect(find.text('Налаштування…'), findsOneWidget);
    expect(find.text('Закрити Stemik Admin'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(StudentsScreen), findsOneWidget);
    await closeMacApp(tester, store);
  }, variant: windows);

  test("an extra window's settings stay in memory", () async {
    SharedPreferences.setMockInitialValues({
      'theme': 'dark',
      'recentSearch': <String>['student:1'],
    });
    final window = await Settings.load(persist: false);
    expect(window.themeMode, ThemeMode.dark);
    expect(window.recentSearch, ['student:1']);

    window.themeMode = ThemeMode.light;
    window.addRecentSearch('lesson:2');
    expect(window.themeMode, ThemeMode.light);
    expect(window.recentSearch, ['lesson:2', 'student:1']);

    final saved = await SharedPreferences.getInstance();
    expect(saved.getString('theme'), 'dark');
    expect(saved.getStringList('recentSearch'), ['student:1']);
  });
}

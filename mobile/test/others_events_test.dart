import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/data/models.dart';
import 'package:stemik/data/snapshot.dart';
import 'package:stemik/data/studio_data.dart';
import 'package:stemik/data/studio_events.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/services/reminders.dart';
import 'package:stemik/util/dates.dart';

import 'store_test.dart' show MemoryFiles, openStore;

void main() {
  test('a model printed by a colleague is news; one printed under my name is not', () async {
    final api = DemoApi();
    final store = await openStore(api, MemoryFiles());
    await Future<void>.delayed(Duration.zero);
    final events = <List<StudioEvent>>[];
    store.othersEvents.listen(events.add);

    final unprinted = api.works.where((w) => w['printed'] != true).take(2).toList();
    expect(unprinted, hasLength(2));
    unprinted[0]
      ..['printed'] = true
      ..['printed_by_name'] = 'Олена Колега';
    unprinted[1]
      ..['printed'] = true
      ..['printed_by_name'] = store.me.fullName;
    api.simulateRemoteChange();
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(events, hasLength(1));
    final e = events.single.single;
    final student = store.data.studentById[unprinted[0]['student_id']]!;
    expect(e.title, 'Модель надруковано');
    expect(e.body, contains(student.name));
    expect(e.body, contains('Олена Колега'));
    expect(e.lessonId, unprinted[0]['lesson_id']);
    await store.close(discardPending: false);
  });

  test("the store's own changes are not news, even when the server echoes them", () async {
    final api = DemoApi();
    final store = await openStore(api, MemoryFiles());
    await Future<void>.delayed(Duration.zero);
    final events = <List<StudioEvent>>[];
    store.othersEvents.listen(events.add);

    final today = todayStr();
    final lesson = store.data.lessons.firstWhere((l) => l.date.compareTo(today) > 0);
    await store.online(() async {
      await api.updateLesson(lesson.id, {'time': '19:45'});
      // The echo arrives while the change is still under way.
      api.simulateRemoteChange();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(store.data.lessonById[lesson.id]!.time, '19:45');
    expect(events, isEmpty);
    await store.close(discardPending: false);
  });

  group('findOthersEvents', () {
    final me = Profile({'id': 'me', 'last_name': 'Адмін', 'first_name': 'Я', 'role': 'admin'});
    final now = DateTime(2026, 10, 25, 12);
    Map<String, dynamic> lesson(String id, String date, String time) => {
      'id': id,
      'owner_id': 't',
      'date': date,
      'time': time,
      'theme': 'Тема',
      'course': '3D-друк',
      'student_ids': <String>[],
    };
    StudioData data({List<Map<String, dynamic>> lessons = const [], List<Map<String, dynamic>> students = const []}) =>
        StudioData.from(
          Snapshot(
            profiles: [
              {'id': 't', 'last_name': 'Шевчук', 'first_name': 'Анна', 'role': 'teacher'},
            ],
            lessons: lessons,
            students: students,
          ),
        );

    test('moved and cancelled lessons from today on; the past is left alone', () {
      final before = data(
        lessons: [
          lesson('a', '2026-10-27', '16:00:00'),
          lesson('b', '2026-10-25', '18:00:00'),
          lesson('c', '2026-10-20', '10:00:00'),
          lesson('d', '2026-10-19', '10:00:00'),
        ],
      );
      final after = data(lessons: [lesson('a', '2026-10-28', '17:30:00'), lesson('c', '2026-10-21', '10:00:00')]);
      final events = findOthersEvents(before, after, me: me, now: now);
      expect(events.map((e) => e.title), ['Заняття скасовано', 'Заняття перенесено']);
      expect(events[0].body, '3D-друк · сьогодні 18:00 · Шевчук Анна');
      expect(events[1].body, '3D-друк: 27 жовтня 16:00 → 28 жовтня 17:30 · Шевчук Анна');
      expect(events[1].lessonId, 'a');
    });

    test('a new student', () {
      final events = findOthersEvents(
        data(),
        data(
          students: [
            {'id': 's', 'name': 'Марко', 'parent_last_name': 'Коваль', 'parent_first_name': 'Ірина'},
          ],
        ),
        me: me,
        now: now,
      );
      expect(events.single.title, 'Новий учень');
      expect(events.single.body, 'Марко · Коваль Ірина');
      expect(events.single.studentId, 's');
    });
  });

  test('a burst of news comes as one notification', () {
    final few = [for (var i = 0; i < 3; i++) StudioEvent('Новий учень', 'Учень $i', studentId: '$i')];
    expect(Reminders.notificationsFor(few), hasLength(3));
    expect(Reminders.notificationsFor(few).first.tapTo, same(few.first));

    final many = [for (var i = 0; i < 6; i++) StudioEvent('Новий учень', 'Учень $i')];
    final one = Reminders.notificationsFor(many).single;
    expect(one.title, 'Колеги: 6 змін');
    expect(one.body.split('\n'), hasLength(5));
    expect(one.body, endsWith('і ще 2'));
    expect(one.tapTo, isNull);
  });
}

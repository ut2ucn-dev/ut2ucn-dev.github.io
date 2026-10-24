import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/data/local_files.dart';
import 'package:stemik/data/models.dart';
import 'package:stemik/data/outbox.dart';
import 'package:stemik/data/store.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/util/dates.dart';
import 'package:stemik/util/domain.dart';
import 'package:stemik/util/text.dart';

class MemoryFiles implements LocalFiles {
  final json = <String, Object?>{};
  final photos = <String, Uint8List>{};
  var _n = 0;

  @override
  Future<Object?> readJson(String name) async => json[name];
  @override
  Future<void> writeJson(String name, Object? data) async => json[name] = data;
  @override
  Future<void> delete(String name) async => json.remove(name);
  @override
  Future<String> savePhoto(Uint8List bytes) async {
    final id = 'p${_n++}';
    photos[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> readPhoto(String handle) async => photos[handle];
  @override
  Future<void> deletePhoto(String handle) async => photos.remove(handle);
  @override
  ImageProvider photoImage(String handle) => MemoryImage(photos[handle]!);
}

Future<AppStore> openStore(DemoApi api, MemoryFiles files) async {
  final store = AppStore(api, files);
  final me = Profile((await api.fetchProfile(api.currentUserId!))!);
  await store.open(me);
  await store.sync();
  return store;
}

/// A lesson that has happened and has a roster child with no attendance.
(Lesson, Student) unmarkedPair(AppStore store) {
  for (final l in store.data.lessons) {
    if (l.date.compareTo(todayStr()) > 0) continue;
    for (final s in store.data.roster(l)) {
      if (store.data.attendance(l.id, s.id) == null) return (l, s);
    }
  }
  throw StateError('no unmarked pair in demo data');
}

void main() {
  test('attendance marked offline shows at once and syncs later', () async {
    final api = DemoApi();
    final files = MemoryFiles();
    final store = await openStore(api, files);
    final (lesson, student) = unmarkedPair(store);

    api.offline = true;
    await store.markAttendance(lesson, student, 'present', paymentMethod: 'cash');
    expect(store.pendingCount, 1);
    expect(store.connection, Connection.offline);
    final local = store.data.attendance(lesson.id, student.id)!;
    expect(local.status, 'present');
    expect(local.pending, isTrue);
    expect(local.amount, lesson.priceAmount);

    // The outbox survives a restart.
    final restarted = AppStore(api, files);
    await restarted.open(store.me);
    expect(restarted.pendingCount, 1);
    expect(restarted.data.attendance(lesson.id, student.id)?.status, 'present');

    api.offline = false;
    await restarted.sync();
    expect(restarted.pendingCount, 0);
    final synced = restarted.data.attendance(lesson.id, student.id)!;
    expect(synced.pending, isFalse);
    expect(synced.paymentMethod, 'cash');
    expect(api.attendance.where((a) => a['lesson_id'] == lesson.id && a['student_id'] == student.id), hasLength(1));
  });

  test('a change sent while online stops showing as pending at once', () async {
    final store = await openStore(DemoApi(), MemoryFiles());
    final (lesson, student) = unmarkedPair(store);
    await store.markAttendance(lesson, student, 'present', paymentMethod: 'card');
    expect(store.pendingCount, 0);
    final att = store.data.attendance(lesson.id, student.id)!;
    expect(att.status, 'present');
    expect(att.pending, isFalse);
  });

  test('a change the server refuses is dropped and reported', () async {
    final api = DemoApi();
    final store = await openStore(api, MemoryFiles());
    final (lesson, student) = unmarkedPair(store);
    final messages = <String>[];
    store.messages.listen(messages.add);

    // set_attendance_print() requires the child to be marked present first.
    await store.markAttendance(lesson, student, 'absent');
    await store.setAttendancePrint(lesson, student, true, null);
    await Future<void>.delayed(Duration.zero);
    expect(store.pendingCount, 0);
    expect(store.rejected.single, contains('Спочатку позначте учня присутнім'));
    expect(messages.last, contains('Не збережено'));
  });

  test('work photo taken offline uploads when back online', () async {
    final api = DemoApi();
    final files = MemoryFiles();
    final store = await openStore(api, files);
    final lesson = store.data.lessons.firstWhere(
      (l) =>
          (l.course ?? '').startsWith('3D') && l.date.compareTo(todayStr()) <= 0 && store.data.printable(l).isNotEmpty,
    );
    final student = store.data.printable(lesson).first;

    api.offline = true;
    await store.attachWorkPhoto(lesson, student, Uint8List.fromList([1, 2, 3]));
    expect(store.data.work(lesson.id, student.id)?.localPhoto, isNotNull);
    expect(files.photos, hasLength(1));

    api.offline = false;
    await store.sync();
    expect(store.pendingCount, 0);
    final w = store.data.work(lesson.id, student.id)!;
    expect(w.photo, startsWith('data:image/jpeg'));
    expect(w.localPhoto, isNull);
    expect(files.photos, isEmpty, reason: 'uploaded photo files are cleaned up');
  });

  test('a teacher sees only their own lessons and no prices', () async {
    final api = DemoApi(role: 'teacher');
    final store = await openStore(api, MemoryFiles());
    expect(store.isAdmin, isFalse);
    expect(store.data.lessons, isNotEmpty);
    expect(store.data.lessons.every((l) => l.ownerId == store.me.id || l.substituteOwnerId == store.me.id), isTrue);
    expect(store.data.lessons.every((l) => l.priceAmount == null), isTrue);
    expect(store.ownedLessons.every((l) => l.ownerId == store.me.id), isTrue);
  });

  test('print queue only lists children marked present on 3D lessons', () async {
    final store = await openStore(DemoApi(), MemoryFiles());
    final rows = store.data.queue(store.ownedLessons, includePrinted: true);
    expect(rows, isNotEmpty);
    for (final r in rows) {
      expect(courseHasPrinting(r.lesson.course), isTrue);
      expect(r.attendance.isPresent, isTrue);
      expect(r.lesson.date.compareTo(todayStr()) <= 0, isTrue);
    }
    final pending = store.data.queue(store.ownedLessons, includePrinted: false);
    expect(pending.every((r) => !(r.work?.printed ?? false)), isTrue);
  });

  test('ops round-trip through JSON', () {
    final op = PendingOp(OpType.markAttendance, {'lessonId': 'l', 'studentId': 's', 'status': 'present'});
    final back = PendingOp.fromJson(op.toJson())!;
    expect(back.id, op.id);
    expect(back.type, OpType.markAttendance);
    expect(back.lessonId, 'l');
  });

  group('rules ported from index.html', () {
    test('payroll buckets', () {
      expect(payrollBucket('group', 1), 'group_1');
      expect(payrollBucket('group', 4), 'group_2_6');
      expect(payrollBucket('individual_online', 1), 'individual_online');
    });

    test('lessonPrintsFor', () {
      Lesson l(String course, String format) =>
          Lesson({'id': 'x', 'owner_id': 'o', 'date': '2026-01-01', 'course': course, 'format': format});
      Attendance a(bool print) =>
          Attendance({'lesson_id': 'x', 'student_id': 's', 'status': 'present', 'print_enabled': print});
      expect(lessonPrintsFor(l('3D Makers PRO (6-8)', 'group'), null), isTrue);
      expect(lessonPrintsFor(l('VR ІГРОВИЙ', 'group'), null), isFalse);
      expect(lessonPrintsFor(l('3D Makers PRO (6-8)', 'group_online'), a(false)), isFalse);
      expect(lessonPrintsFor(l('3D Makers PRO (6-8)', 'group_online'), a(true)), isTrue);
    });

    test('Ukrainian alphabetical order', () {
      final names = ['Яна', 'Ігор', 'Євген', 'Анна', 'Іван', 'Ґанна', 'Їжак', 'Галина'];
      names.sort(ukCompare);
      expect(names, ['Анна', 'Галина', 'Ґанна', 'Євген', 'Іван', 'Ігор', 'Їжак', 'Яна']);
    });

    test('dates stay local', () {
      expect(addDays('2026-03-29', 1), '2026-03-30');
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(lessonEndTime('16:30', 90), '18:00');
      expect(formatMoney(1234.5), contains('грн'));
    });
  });
}

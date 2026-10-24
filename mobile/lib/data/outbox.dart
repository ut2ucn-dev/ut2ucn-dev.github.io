import 'package:uuid/uuid.dart';

import 'api.dart';
import 'local_files.dart';
import 'snapshot.dart';

/// Kinds of change that can be made without a connection. Each is replayed
/// against the server in the order it was made, and is written so that
/// replaying it twice (after a crash mid-sync) leaves the same result.
enum OpType {
  markAttendance,
  unmarkAttendance,
  setAttendancePrint,
  setWork,
  uploadWorkPhoto,
  setLessonCompleted,
  addComment,
}

class PendingOp {
  final String id;
  final OpType type;
  final Map<String, dynamic> data;
  final String createdAt;

  PendingOp(this.type, this.data, {String? id, String? createdAt})
    : id = id ?? const Uuid().v4(),
      createdAt = createdAt ?? DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, 'data': data, 'createdAt': createdAt};

  static PendingOp? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = OpType.values.where((t) => t.name == json['type']).firstOrNull;
    if (type == null) return null;
    return PendingOp(
      type,
      Map<String, dynamic>.from(json['data'] as Map),
      id: json['id'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  String get lessonId => data['lessonId'] as String? ?? '';
  String get studentId => data['studentId'] as String? ?? '';

  /// Short human description for the sync screen.
  String describe() {
    switch (type) {
      case OpType.markAttendance:
        return 'Відмітка присутності';
      case OpType.unmarkAttendance:
        return 'Зняття відмітки присутності';
      case OpType.setAttendancePrint:
        return 'Друк для учня';
      case OpType.setWork:
        return data['patch']?['printed'] != null ? 'Статус друку' : 'Пробне заняття';
      case OpType.uploadWorkPhoto:
        return 'Фото роботи';
      case OpType.setLessonCompleted:
        return 'Завершення заняття';
      case OpType.addComment:
        return 'Коментар про учня';
    }
  }
}

int _indexWhere(List<DbRow> rows, bool Function(DbRow r) test) {
  for (var i = 0; i < rows.length; i++) {
    if (test(rows[i])) return i;
  }
  return -1;
}

double? _toDouble(Object? v) => v is num ? v.toDouble() : null;

/// Applies [op] to [s] (a mutable copy) the way the server will once it is
/// synced, so the screen shows the change straight away. Amounts the
/// database computes are estimated until a refresh brings the real ones.
/// [pending] flags the row as not yet sent (the cloud icon on screen).
void applyOp(Snapshot s, PendingOp op, {bool pending = true}) {
  final d = op.data;
  bool sameAtt(DbRow r) => r['lesson_id'] == op.lessonId && r['student_id'] == op.studentId;
  DbRow? lessonRow() {
    final i = _indexWhere(s.lessons, (r) => r['id'] == op.lessonId);
    return i < 0 ? null : s.lessons[i];
  }

  switch (op.type) {
    case OpType.markAttendance:
      final i = _indexWhere(s.attendance, sameAtt);
      final lesson = lessonRow();
      final base = i >= 0
          ? s.attendance[i]
          : <String, dynamic>{
              'lesson_id': op.lessonId,
              'student_id': op.studentId,
              'owner_id': lesson?['owner_id'],
              'print_enabled': false,
              'print_price': null,
            };
      final present = d['status'] == 'present';
      final row = {
        ...base,
        'status': d['status'],
        'payment_method': present ? d['paymentMethod'] : null,
        'discount_percent': present ? (d['discountPercent'] ?? 0) : 0,
        'amount': present ? _estimateAmount(s, lesson, base, d) : 0,
        '_pending': pending,
      };
      if (i >= 0) {
        s.attendance[i] = row;
      } else {
        s.attendance.add(row);
      }
    case OpType.unmarkAttendance:
      s.attendance.removeWhere(sameAtt);
    case OpType.setAttendancePrint:
      final i = _indexWhere(s.attendance, sameAtt);
      if (i < 0) return;
      final enabled = d['enabled'] == true;
      final row = {
        ...s.attendance[i],
        'print_enabled': enabled,
        'print_price': enabled ? d['price'] : null,
        '_pending': pending,
      };
      row['amount'] = _estimateAmount(s, lessonRow(), row, {
        'paymentMethod': row['payment_method'],
        'discountPercent': row['discount_percent'],
      });
      s.attendance[i] = row;
    case OpType.setWork:
    case OpType.uploadWorkPhoto:
      final patch = op.type == OpType.setWork
          ? Map<String, dynamic>.from(d['patch'] as Map)
          : {'_local_photo': d['photoHandle']};
      final i = _indexWhere(s.works, sameAtt);
      final base = i >= 0
          ? s.works[i]
          : <String, dynamic>{
              'lesson_id': op.lessonId,
              'student_id': op.studentId,
              'owner_id': d['ownerId'],
              'printed': false,
              'trial': false,
            };
      final row = {...base, ...patch, '_pending': pending};
      if (i >= 0) {
        s.works[i] = row;
      } else {
        s.works.add(row);
      }
    case OpType.setLessonCompleted:
      final i = _indexWhere(s.lessons, (r) => r['id'] == op.lessonId);
      if (i >= 0) s.lessons[i] = {...s.lessons[i], 'completed': d['completed'], '_pending': pending};
    case OpType.addComment:
      // Comments aren't part of the snapshot; the student card merges the
      // pending ones in itself (see AppStore.pendingComments).
      break;
  }
}

/// What mark_attendance()/set_attendance_print() will most likely charge
/// (sql/0017), so the admin sees a sensible number while offline.
double _estimateAmount(Snapshot s, DbRow? lesson, DbRow att, Map<String, dynamic> d) {
  final method = d['paymentMethod'] as String?;
  final discount = _toDouble(d['discountPercent']) ?? 0;
  var amount = _toDouble(lesson?['price_amount']) ?? 0;
  final online = lesson?['format'] == 'individual_online' || lesson?['format'] == 'group_online';
  if (online && att['print_enabled'] == true) {
    final rc = s.rateCards.where((r) => r['course'] == lesson?['course']).firstOrNull;
    amount += _toDouble(att['print_price']) ?? _toDouble(rc?['price_print_online']) ?? 100;
  }
  if (method == 'subscription') {
    final sub = s.subscriptions
        .where(
          (r) =>
              r['student_id'] == att['student_id'] &&
              r['course'] == lesson?['course'] &&
              r['status'] == 'active' &&
              ((r['remaining_lessons'] as num?) ?? 0) > 0,
        )
        .firstOrNull;
    final total = _toDouble(sub?['total_price']) ?? 0;
    final count = (sub?['total_lessons'] as num?)?.toInt() ?? 0;
    if (total > 0 && count > 0) amount = total / count;
  }
  return (amount * (1 - discount / 100) * 100).round() / 100;
}

/// Sends one op to the server. Throws [ServerRejected] if the server
/// refused it (the op is then dropped), anything else to retry later.
Future<void> executeOp(StemikApi api, LocalFiles files, PendingOp op) async {
  final d = op.data;
  switch (op.type) {
    case OpType.markAttendance:
      await api.markAttendance(
        lessonId: op.lessonId,
        studentId: op.studentId,
        status: d['status'] as String,
        paymentMethod: d['paymentMethod'] as String?,
        discountPercent: _toDouble(d['discountPercent']) ?? 0,
        purchaseDate: d['purchaseDate'] as String?,
        purchaseMethod: d['purchaseMethod'] as String?,
      );
    case OpType.unmarkAttendance:
      await api.unmarkAttendance(op.lessonId, op.studentId);
    case OpType.setAttendancePrint:
      await api.setAttendancePrint(op.lessonId, op.studentId, d['enabled'] == true, _toDouble(d['price']));
    case OpType.setWork:
      await api.upsertWork(
        op.lessonId,
        op.studentId,
        d['ownerId'] as String,
        Map<String, dynamic>.from(d['patch'] as Map),
      );
    case OpType.uploadWorkPhoto:
      final bytes = await files.readPhoto(d['photoHandle'] as String);
      if (bytes == null) throw ServerRejected('Фото не знайдено на пристрої');
      final owner = d['ownerId'] as String;
      final url = await api.uploadPhoto('works-photos', '$owner/${op.lessonId}_${op.studentId}.jpg', bytes);
      await api.upsertWork(op.lessonId, op.studentId, owner, {'photo': url});
    case OpType.setLessonCompleted:
      await api.updateLesson(op.lessonId, {'completed': d['completed'] == true});
    case OpType.addComment:
      await api.insertComment({
        'id': d['id'],
        'student_id': op.studentId,
        'author_id': d['authorId'],
        'body': d['body'],
        'created_at': d['createdAt'],
      });
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'api.dart';

/// [StemikApi] over the studio's Supabase project — the same tables, views,
/// RPCs and Edge Functions index.html uses.
class SupabaseApi implements StemikApi {
  SupabaseClient get _sb => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // Implicit flow: password-reset links then carry the token in the URL
        // fragment, which the web version (supabase-js defaults) understands.
        authFlowType: AuthFlowType.implicit,
        detectSessionInUri: false,
      ),
    );
  }

  /// Turns "the server said no" into [ServerRejected]; everything else
  /// (no network, timeouts, 5xx, an expired token that can't be refreshed
  /// offline) is rethrown untouched so the outbox retries it later.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      final retryable = code.startsWith('PGRST3') || RegExp(r'^5\d\d$').hasMatch(code);
      if (retryable) rethrow;
      throw ServerRejected(e.message);
    } on StorageException catch (e) {
      final status = int.tryParse(e.statusCode ?? '') ?? 0;
      if (status == 0 || status == 401 || status >= 500) rethrow;
      throw ServerRejected(e.message);
    } on FunctionException catch (e) {
      if (e.status >= 500 && e.details == null) rethrow;
      final d = e.details;
      final msg = d is Map && d['error'] != null ? '${d['error']}' : 'Помилка сервера (код ${e.status})';
      throw ServerRejected(msg);
    } on AuthRetryableFetchException {
      rethrow;
    } on AuthException catch (e) {
      throw ServerRejected(e.message);
    }
  }

  /// Supabase caps one response at 1000 rows; page through to get them all.
  Future<List<DbRow>> _paged(PostgrestFilterBuilder<PostgrestList> Function() build, {String orderBy = 'id'}) {
    return _guard(() async {
      const size = 1000;
      final out = <DbRow>[];
      for (var from = 0; ; from += size) {
        final page = await build().order(orderBy, ascending: true).range(from, from + size - 1);
        out.addAll(page);
        if (page.length < size) return out;
      }
    });
  }

  // --- auth ---------------------------------------------------------------

  @override
  String? get currentUserId => _sb.auth.currentUser?.id;

  @override
  Stream<AuthEvent> get authEvents => _sb.auth.onAuthStateChange.map((s) {
    switch (s.event) {
      case AuthChangeEvent.passwordRecovery:
        return AuthEvent.passwordRecovery;
      case AuthChangeEvent.signedOut:
        return AuthEvent.signedOut;
      default:
        return s.session == null ? AuthEvent.signedOut : AuthEvent.signedIn;
    }
  });

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _sb.auth.signInWithPassword(email: email, password: password));

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _sb.auth.resetPasswordForEmail(email, redirectTo: siteUrl));

  @override
  Future<void> updatePassword(String password) => _guard(() => _sb.auth.updateUser(UserAttributes(password: password)));

  @override
  Future<void> signOut() => _sb.auth.signOut();

  // --- reads --------------------------------------------------------------

  @override
  Future<DbRow?> fetchProfile(String id) => _guard(() => _sb.from('profiles').select().eq('id', id).maybeSingle());

  @override
  Future<List<DbRow>> fetchProfiles() => _paged(() => _sb.from('profiles').select());

  @override
  Future<List<DbRow>> fetchStudents() => _paged(() => _sb.from('students').select());

  @override
  Future<List<DbRow>> fetchLessons({String? ownerId}) => _paged(() {
    final q = _sb.from('lessons_safe').select();
    return ownerId == null ? q : q.or('owner_id.eq.$ownerId,substitute_owner_id.eq.$ownerId');
  });

  @override
  Future<List<DbRow>> fetchWorks({String? ownerId}) => _paged(() {
    final q = _sb.from('works').select();
    return ownerId == null ? q : q.eq('owner_id', ownerId);
  });

  @override
  Future<List<DbRow>> fetchAttendance({String? ownerId, List<String> lessonIds = const []}) async {
    if (ownerId == null) return _paged(() => _sb.from('lesson_attendance').select());
    final own = await _paged(() => _sb.from('lesson_attendance').select().eq('owner_id', ownerId));
    if (lessonIds.isEmpty) return own;
    // Lessons covered as a substitute belong to someone else's owner_id.
    final extra = await _paged(() => _sb.from('lesson_attendance').select().inFilter('lesson_id', lessonIds));
    final seen = own.map((r) => r['id']).toSet();
    return [...own, ...extra.where((r) => !seen.contains(r['id']))];
  }

  @override
  Future<List<DbRow>> fetchSubscriptions({String? studentId}) => _paged(() {
    final q = _sb.from('subscriptions').select();
    return studentId == null ? q : q.eq('student_id', studentId);
  });

  @override
  Future<List<DbRow>> fetchRateCards() => _guard(() => _sb.from('rate_cards_safe').select());

  @override
  Future<List<DbRow>> fetchComments(String studentId) => _guard(
    () => _sb.from('student_comments').select().eq('student_id', studentId).order('created_at', ascending: false),
  );

  @override
  Future<List<DbRow>> fetchStudentLessons(String studentId) =>
      _paged(() => _sb.from('lessons_safe').select().contains('student_ids', [studentId]));

  @override
  Future<List<DbRow>> fetchStudentWorks(String studentId) =>
      _paged(() => _sb.from('works').select().eq('student_id', studentId));

  @override
  Future<List<DbRow>> fetchStudentAttendance(String studentId) =>
      _paged(() => _sb.from('lesson_attendance').select().eq('student_id', studentId));

  @override
  Future<String?> fetchCalcStartDate() => _guard(() async {
    final row = await _sb.from('studio_settings').select('calc_start_date').limit(1).maybeSingle();
    return row?['calc_start_date'] as String?;
  });

  @override
  Future<DbRow?> fetchReportSummary(String from, String to) => _guard(() async {
    final res = await _sb.rpc('studio_report_summary', params: {'p_from': from, 'p_to': to});
    if (res is List && res.isNotEmpty) return Map<String, dynamic>.from(res.first as Map);
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  });

  @override
  Future<List<DbRow>> fetchReportView(String view, {String? from, String? to, required String orderBy}) =>
      _guard(() async {
        var q = _sb.from(view).select();
        if (from != null) q = q.gte('lesson_date', from);
        if (to != null) q = q.lte('lesson_date', to);
        return await q.order(orderBy);
      });

  // --- outbox writes ------------------------------------------------------

  @override
  Future<void> markAttendance({
    required String lessonId,
    required String studentId,
    required String status,
    String? paymentMethod,
    double discountPercent = 0,
    String? purchaseDate,
    String? purchaseMethod,
  }) => _guard(
    () => _sb.rpc(
      'mark_attendance',
      params: {
        'p_lesson_id': lessonId,
        'p_student_id': studentId,
        'p_status': status,
        'p_payment_method': paymentMethod,
        'p_discount_percent': discountPercent,
        'p_purchase_date': purchaseDate,
        'p_purchase_method': purchaseMethod,
      },
    ),
  );

  @override
  Future<void> unmarkAttendance(String lessonId, String studentId) =>
      _guard(() => _sb.rpc('unmark_attendance', params: {'p_lesson_id': lessonId, 'p_student_id': studentId}));

  @override
  Future<void> setAttendancePrint(String lessonId, String studentId, bool enabled, double? price) => _guard(
    () => _sb.rpc(
      'set_attendance_print',
      params: {'p_lesson_id': lessonId, 'p_student_id': studentId, 'p_enabled': enabled, 'p_price': price},
    ),
  );

  @override
  Future<void> upsertWork(String lessonId, String studentId, String ownerId, DbRow patch) => _guard(() async {
    final existing = await _sb
        .from('works')
        .select('id')
        .eq('lesson_id', lessonId)
        .eq('student_id', studentId)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      await _sb.from('works').update(patch).eq('id', existing['id'] as Object);
    } else {
      await _sb.from('works').insert({'owner_id': ownerId, 'lesson_id': lessonId, 'student_id': studentId, ...patch});
    }
  });

  @override
  Future<String> uploadPhoto(String bucket, String path, Uint8List bytes) => _guard(() async {
    await _sb.storage
        .from(bucket)
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
    // Same cache-busting suffix as index.html's uploadPhoto().
    return '${_sb.storage.from(bucket).getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
  });

  @override
  Future<void> updateLesson(String id, DbRow patch) => _guard(() => _sb.from('lessons').update(patch).eq('id', id));

  @override
  Future<void> insertComment(DbRow row) => _guard(() => _sb.from('student_comments').insert(row));

  // --- online-only writes -------------------------------------------------

  @override
  Future<void> insertLessons(List<DbRow> rows) => _guard(() => _sb.from('lessons').insert(rows));

  @override
  Future<void> deleteLesson(String id) => _guard(() => _sb.from('lessons').delete().eq('id', id));

  @override
  Future<void> deleteLessonSeries(String seriesId, String fromDate) =>
      _guard(() => _sb.from('lessons').delete().eq('series_id', seriesId).gte('date', fromDate));

  @override
  Future<void> reassignLessonOwner(String lessonId, String ownerId) => _guard(() async {
    // Photos/prints and attendance carry the owner too (see LessonModal
    // in index.html); move them along with the lesson.
    await Future.wait([
      _sb.from('works').update({'owner_id': ownerId}).eq('lesson_id', lessonId),
      _sb.from('lesson_attendance').update({'owner_id': ownerId}).eq('lesson_id', lessonId),
    ]);
  });

  @override
  Future<DbRow> saveStudent(DbRow payload, {String? id}) => _guard(() async {
    if (id != null) return await _sb.from('students').update(payload).eq('id', id).select().single();
    return await _sb.from('students').insert(payload).select().single();
  });

  @override
  Future<void> insertStudents(List<DbRow> rows) => _guard(() => _sb.from('students').insert(rows));

  @override
  Future<void> deleteStudent(String id) => _guard(() => _sb.from('students').delete().eq('id', id));

  @override
  Future<void> updateSubscription(String id, DbRow patch) =>
      _guard(() => _sb.from('subscriptions').update(patch).eq('id', id));

  @override
  Future<void> updateProfile(String id, DbRow patch) => _guard(() => _sb.from('profiles').update(patch).eq('id', id));

  @override
  Future<void> upsertRateCards(List<DbRow> rows) =>
      _guard(() => _sb.from('rate_cards').upsert(rows, onConflict: 'course'));

  @override
  Future<void> setCalcStartDate(String? date) => _guard(() => _sb.rpc('set_calc_start_date', params: {'p_date': date}));

  @override
  Future<DbRow> callFunction(String name, DbRow body) => _guard(() async {
    final res = await _sb.functions.invoke(name, body: body);
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  });
}

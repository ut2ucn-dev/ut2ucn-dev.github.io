import 'dart:typed_data';

typedef DbRow = Map<String, dynamic>;

enum AuthEvent { signedIn, signedOut, passwordRecovery }

/// Raised for a request the server answered and refused (validation, RLS,
/// a raise in a database function). Anything else thrown by an [StemikApi]
/// call is treated as "couldn't reach the server" and retried later.
class ServerRejected implements Exception {
  final String message;
  ServerRejected(this.message);
  @override
  String toString() => message;
}

/// The tables whose changes the apps hear about (sql/0020_realtime.sql).
const liveTables = [
  'lessons',
  'lesson_attendance',
  'works',
  'students',
  'subscriptions',
  'profiles',
  'student_comments',
  'rate_cards',
];

/// A running [StemikApi.watchStudio]; [cancel] stops it.
class LiveWatch {
  const LiveWatch(this.cancel);
  final Future<void> Function() cancel;

  static final none = LiveWatch(() async {});
}

/// Everything the app asks of the backend. [SupabaseApi] is the real one;
/// the demo build and the tests use an in-memory fake.
abstract class StemikApi {
  // --- auth ---------------------------------------------------------------
  String? get currentUserId;
  Stream<AuthEvent> get authEvents;
  Future<void> signIn(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<void> signOut();

  /// The signed-in person's current access token, and every new one as it
  /// is refreshed — handed to the Mac's extra windows, which don't keep a
  /// session of their own. Null and empty where there is none (demo).
  String? get accessToken;
  Stream<String?> get accessTokens;

  // --- live updates (sql/0020) ---------------------------------------------

  /// Calls [onChange] whenever studio data ([liveTables]) changes on the
  /// server, whoever changed it; [onLive] says whether the connection is
  /// up. For admins only: a change event carries the whole row, prices
  /// included.
  LiveWatch watchStudio({required void Function() onChange, required void Function(bool live) onLive});

  // --- reads --------------------------------------------------------------
  Future<DbRow?> fetchProfile(String id);
  Future<List<DbRow>> fetchProfiles();
  Future<List<DbRow>> fetchStudents();

  /// All lessons when [ownerId] is null, otherwise that teacher's own plus
  /// the ones they cover as a substitute.
  Future<List<DbRow>> fetchLessons({String? ownerId});
  Future<List<DbRow>> fetchWorks({String? ownerId});
  Future<List<DbRow>> fetchAttendance({String? ownerId, List<String> lessonIds = const []});
  Future<List<DbRow>> fetchSubscriptions({String? studentId});
  Future<List<DbRow>> fetchRateCards();
  Future<List<DbRow>> fetchComments(String studentId);
  Future<List<DbRow>> fetchStudentLessons(String studentId);
  Future<List<DbRow>> fetchStudentWorks(String studentId);
  Future<List<DbRow>> fetchStudentAttendance(String studentId);
  Future<String?> fetchCalcStartDate();
  Future<DbRow?> fetchReportSummary(String from, String to);
  Future<List<DbRow>> fetchReportView(String view, {String? from, String? to, required String orderBy});

  // --- writes the outbox replays (must be safe to retry) -------------------
  Future<void> markAttendance({
    required String lessonId,
    required String studentId,
    required String status,
    String? paymentMethod,
    double discountPercent = 0,
    String? purchaseDate,
    String? purchaseMethod,
  });
  Future<void> unmarkAttendance(String lessonId, String studentId);
  Future<void> setAttendancePrint(String lessonId, String studentId, bool enabled, double? price);

  /// Updates the (lesson, student) works row, creating it if there is none.
  Future<void> upsertWork(String lessonId, String studentId, String ownerId, DbRow patch);

  /// Uploads a JPEG to a public bucket (overwriting) and returns its URL.
  Future<String> uploadPhoto(String bucket, String path, Uint8List bytes);
  Future<void> updateLesson(String id, DbRow patch);
  Future<void> insertComment(DbRow row);

  // --- online-only writes -------------------------------------------------
  Future<void> insertLessons(List<DbRow> rows);
  Future<void> deleteLesson(String id);
  Future<void> deleteLessonSeries(String seriesId, String fromDate);
  Future<void> reassignLessonOwner(String lessonId, String ownerId);
  Future<DbRow> saveStudent(DbRow payload, {String? id});
  Future<void> insertStudents(List<DbRow> rows);
  Future<void> deleteStudent(String id);
  Future<void> updateSubscription(String id, DbRow patch);
  Future<void> updateProfile(String id, DbRow patch);
  Future<void> upsertRateCards(List<DbRow> rows);
  Future<void> setCalcStartDate(String? date);

  /// Calls a Supabase Edge Function (create-teacher, reset-password).
  Future<DbRow> callFunction(String name, DbRow body);

  // --- cost of printed models (sql/0019) ----------------------------------

  /// Printers and filaments, oldest first (printers_safe / filaments_safe):
  /// everyone picks from them when marking a model printed; the prices come
  /// back for admins only.
  Future<List<DbRow>> fetchPrinters();
  Future<List<DbRow>> fetchFilaments();

  /// The electricity tariff and filament waste % (studio_settings).
  Future<DbRow?> fetchPrintCostSettings();

  /// One row per model printed in [from]..[to] (report_print_costs), newest
  /// first; admins only.
  Future<List<DbRow>> fetchPrintCosts(String from, String to);

  /// Saves one directory, 'printers' or 'filaments' (rows without an id are
  /// added) and returns every row's id in the same order — so the screen
  /// can keep them, and saving again after a later step failed updates the
  /// new rows instead of adding them a second time.
  Future<List<String>> savePrintRows(String table, List<DbRow> rows);

  /// The electricity tariff and filament waste % (set_print_cost_settings).
  Future<void> savePrintCostSettings({required double tariff, required double wastePercent});

  /// "Приховати"/"Показати": only takes a printer or filament out of (or
  /// back into) the teachers' choice; it stays in the directory and history.
  Future<void> setPrintRowActive(String table, String id, bool active);

  /// "Видалити": removes it for good. Models printed on it keep their
  /// frozen cost; their link to it is cleared.
  Future<void> deletePrintRow(String table, String id);

  /// How many works use this printer or filament ('printer_id' or
  /// 'filament_id'), for the delete confirmation.
  Future<int> countWorksUsing(String column, String id);

  // --- parents' portal accounts (sql/0018), superadmin only ---------------

  /// Newest first.
  Future<List<DbRow>> fetchParentAccounts();

  /// Which children each account sees: rows of (parent_id, student_id).
  Future<List<DbRow>> fetchParentLinks();

  /// parent_create_account, parent_reset_password or
  /// parent_password_for_student: each returns the new plain-text password.
  Future<DbRow> parentRpc(String name, DbRow params);
  Future<void> saveParentAccount(
    String id, {
    required String phone,
    String? name,
    required List<String> linkStudents,
    required List<String> unlinkStudents,
  });
  Future<void> setParentAccountActive(String id, bool active);
  Future<void> deleteParentAccount(String id);
}

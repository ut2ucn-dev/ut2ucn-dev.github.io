// Plain data classes mirroring the Supabase tables/views the web version
// reads. Each keeps the raw row it was built from, so it can be written to
// the offline cache and read back without losing columns this app doesn't
// use yet.

double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

class Profile {
  final Map<String, dynamic> raw;
  Profile(this.raw);

  String get id => raw['id'] as String;
  String? get email => raw['email'] as String?;
  String get firstName => (raw['first_name'] as String?) ?? '';
  String get lastName => (raw['last_name'] as String?) ?? '';
  String? get photo => raw['photo'] as String?;
  String get role => (raw['role'] as String?) ?? 'teacher';
  bool get active => raw['active'] != false;

  bool get isSuperAdmin => role == 'superadmin';
  bool get isAdmin => role == 'admin' || isSuperAdmin;

  String get fullName {
    final n = '$lastName $firstName'.trim();
    return n.isNotEmpty ? n : (email ?? '');
  }

  String get initials {
    if (lastName.isNotEmpty) return lastName[0].toUpperCase();
    if ((email ?? '').isNotEmpty) return email![0].toUpperCase();
    return '?';
  }

  Profile copyWith(Map<String, dynamic> patch) => Profile({...raw, ...patch});
}

class Student {
  final Map<String, dynamic> raw;
  Student(this.raw);

  String get id => raw['id'] as String;
  String get name => (raw['name'] as String?) ?? '';
  String? get phone => _blankToNull(raw['phone']);
  String? get birthday => raw['birthday'] as String?;
  String? get parentLastName => _blankToNull(raw['parent_last_name']);
  String? get parentFirstName => _blankToNull(raw['parent_first_name']);
  String? get notes => _blankToNull(raw['notes']);
  String? get photo => _blankToNull(raw['photo']);

  String get parentsName => [parentLastName, parentFirstName].whereType<String>().join(' ');

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

String? _blankToNull(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

class Lesson {
  final Map<String, dynamic> raw;
  Lesson(this.raw);

  String get id => raw['id'] as String;
  String get ownerId => raw['owner_id'] as String;
  String get date => raw['date'] as String;
  String? get time {
    final t = raw['time'] as String?;
    if (t == null || t.isEmpty) return null;
    // Postgres `time` comes back as HH:MM:SS; the UI only ever shows HH:MM.
    return t.length > 5 ? t.substring(0, 5) : t;
  }

  String get theme => (raw['theme'] as String?) ?? '';
  String? get course => _blankToNull(raw['course']);
  String get format => (raw['format'] as String?) ?? 'group';
  List<String> get studentIds => ((raw['student_ids'] as List?) ?? const []).cast<String>();
  bool get extraService => raw['extra_service'] == true;
  String? get seriesId => raw['series_id'] as String?;
  double get payrollAmount => _num(raw['payroll_amount']) ?? 0;
  double? get priceAmount => _num(raw['price_amount']);
  int get durationMinutes => (raw['duration_minutes'] as num?)?.toInt() ?? 60;
  String? get room => _blankToNull(raw['room']);
  String? get substituteOwnerId => raw['substitute_owner_id'] as String?;
  bool get completed => raw['completed'] == true;

  /// "+ друк" on an online lesson (sql/0021): children marked "П" get their
  /// print switched on.
  bool get printDefault => raw['print_default'] == true;

  /// Sort key: date then time, lessons without a time first.
  String get sortKey => '$date${time ?? ''}';

  Lesson copyWith(Map<String, dynamic> patch) => Lesson({...raw, ...patch});
}

class Attendance {
  final Map<String, dynamic> raw;
  Attendance(this.raw);

  String? get id => raw['id'] as String?;
  String get lessonId => raw['lesson_id'] as String;
  String get studentId => raw['student_id'] as String;
  String? get ownerId => raw['owner_id'] as String?;
  String get status => raw['status'] as String;
  String? get paymentMethod => raw['payment_method'] as String?;
  double get amount => _num(raw['amount']) ?? 0;
  double get discountPercent => _num(raw['discount_percent']) ?? 0;
  String? get subscriptionId => raw['subscription_id'] as String?;
  bool get printEnabled => raw['print_enabled'] == true;
  double? get printPrice => _num(raw['print_price']);

  /// Set on rows changed on this device and not yet confirmed by the server.
  bool get pending => raw['_pending'] == true;

  bool get isPresent => status == 'present';

  Attendance copyWith(Map<String, dynamic> patch) => Attendance({...raw, ...patch});
}

class Work {
  final Map<String, dynamic> raw;
  Work(this.raw);

  String? get id => raw['id'] as String?;
  String get ownerId => raw['owner_id'] as String;
  String get lessonId => raw['lesson_id'] as String;
  String get studentId => raw['student_id'] as String;
  String? get photo => _blankToNull(raw['photo']);
  bool get printed => raw['printed'] == true;
  String? get printedByName => raw['printed_by_name'] as String?;
  bool get trial => raw['trial'] == true;

  // What was entered when it was marked printed (sql/0019).
  double? get weightG => _num(raw['weight_g']);
  double? get printMinutes => _num(raw['print_minutes']);
  String? get printerId => raw['printer_id'] as String?;
  String? get filamentId => raw['filament_id'] as String?;

  /// A photo taken on this device that hasn't been uploaded yet.
  String? get localPhoto => raw['_local_photo'] as String?;
  bool get pending => raw['_pending'] == true;

  Work copyWith(Map<String, dynamic> patch) => Work({...raw, ...patch});
}

class Subscription {
  final Map<String, dynamic> raw;
  Subscription(this.raw);

  String get id => raw['id'] as String;
  String get studentId => raw['student_id'] as String;
  String get course => (raw['course'] as String?) ?? '';
  int get totalLessons => (raw['total_lessons'] as num?)?.toInt() ?? 4;
  int get remainingLessons => (raw['remaining_lessons'] as num?)?.toInt() ?? 0;
  double get totalPrice => _num(raw['total_price']) ?? 0;
  String get purchasedAt => (raw['purchased_at'] as String?) ?? '';
  String? get paymentMethod => raw['payment_method'] as String?;
  String get status => (raw['status'] as String?) ?? 'active';

  /// Purchase dates are stored as midnight UTC of the chosen day (see
  /// sql/0016), so the first 10 characters are always that day.
  String get purchaseDate => purchasedAt.length >= 10 ? purchasedAt.substring(0, 10) : purchasedAt;
}

class StudentComment {
  final Map<String, dynamic> raw;
  StudentComment(this.raw);

  String get id => raw['id'] as String;
  String get studentId => raw['student_id'] as String;
  String? get authorId => raw['author_id'] as String?;
  String get body => (raw['body'] as String?) ?? '';
  String get createdAt => (raw['created_at'] as String?) ?? '';
  bool get pending => raw['_pending'] == true;
}

/// One course's row from rate_cards_safe. Prices are null for non-admins.
class RateCard {
  final Map<String, dynamic> raw;
  RateCard(this.raw);

  String get course => raw['course'] as String;
  double? value(String column) => _num(raw[column]);
}

/// A printer from printers_safe; the numbers are null for teachers.
class Printer {
  final Map<String, dynamic> raw;
  Printer(this.raw);

  String? get id => raw['id'] as String?;
  String get name => (raw['name'] as String?) ?? '';
  double? get powerWatts => _num(raw['power_watts']);
  double? get depreciationPerHour => _num(raw['depreciation_per_hour']);
  bool get active => raw['active'] != false;
}

/// A filament from filaments_safe; the price is null for teachers.
class Filament {
  final Map<String, dynamic> raw;
  Filament(this.raw);

  String? get id => raw['id'] as String?;
  String get material => (raw['material'] as String?) ?? '';
  String? get color => raw['color'] as String?;
  double? get pricePerKg => _num(raw['price_per_kg']);
  bool get active => raw['active'] != false;
}

/// One printed model from report_print_costs. The costs are null until
/// weight or time was entered.
class PrintCost {
  final Map<String, dynamic> raw;
  PrintCost(this.raw);

  String get workId => raw['work_id'] as String;
  String get printDate => (raw['print_date'] as String?) ?? '';
  String? get course => raw['course'] as String?;
  String? get theme => raw['theme'] as String?;
  String? get studentName => raw['student_name'] as String?;
  double? get weightG => _num(raw['weight_g']);
  double? get printMinutes => _num(raw['print_minutes']);
  String? get printerName => raw['printer_name'] as String?;
  String? get filamentMaterial => raw['filament_material'] as String?;
  String? get filamentColor => raw['filament_color'] as String?;
  double? get materialCost => _num(raw['material_cost']);
  double? get electricityCost => _num(raw['electricity_cost']);
  double? get depreciationCost => _num(raw['depreciation_cost']);
  double? get totalCost => _num(raw['total_cost']);
}

/// A parents' portal account (parent_accounts). The phone is digits with
/// the 380 prefix.
class ParentAccount {
  final Map<String, dynamic> raw;
  ParentAccount(this.raw);

  String get id => raw['id'] as String;
  String get phone => (raw['phone'] as String?) ?? '';
  String? get name => raw['name'] as String?;
  bool get active => raw['active'] != false;
  String? get passwordSetAt => raw['password_set_at'] as String?;
  String? get lastLoginAt => raw['last_login_at'] as String?;
}

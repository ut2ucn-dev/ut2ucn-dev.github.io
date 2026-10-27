// Studio vocabulary and business rules ported from index.html. The values
// here must match the database constraints (sql/0015-0017) and the web UI.

import '../config.dart';
import '../data/models.dart';

const courseOptions = [
  '3D Tinkercad FIRST (9-12)',
  '3D Tinkercad PRO (9-12)',
  '3D Makers FIRST (6-8)',
  '3D Makers PRO (6-8)',
  'VR ІГРОВИЙ',
  'VR РОЗРОБКА (Delightex)',
  'Robo AI (Ukit 6-8)',
  'Robo AI (UGot 9-12)',
  '3D слайсинг',
];

const roomOptions = ['Клас AI', 'Клас VR', "Комп'ютерний клас", 'Клас 3D'];

class Option {
  final String value;
  final String label;
  const Option(this.value, this.label);
}

const formatOptions = [
  Option('group', 'Група (очно)'),
  Option('individual', 'Індив (очно)'),
  Option('individual_online', 'Індив (online)'),
  Option('group_online', 'Група (online)'),
];

const attendanceStatuses = [Option('present', 'П'), Option('absent', 'Н'), Option('excused', 'ВПП')];

const attendanceStatusTitles = {
  'present': 'Присутній',
  'absent': 'Відсутній',
  'excused': 'Відсутній з поважної причини',
};

const paymentMethods = [
  Option('card', 'Картка'),
  Option('cash', 'Готівка'),
  Option('subscription', 'Абонемент'),
  Option('certificate', 'Сертифікат'),
];

const subscriptionPaymentMethods = [Option('card', 'Картка'), Option('cash', 'Готівка')];

const roleLabels = {'teacher': 'Викладач', 'admin': 'Адмін', 'superadmin': 'Суперадмін'};

String? optionLabel(List<Option> options, String? value) {
  for (final o in options) {
    if (o.value == value) return o.label;
  }
  return null;
}

bool isOnlineFormat(String format) => format == 'individual_online' || format == 'group_online';

String formatLabel(String format) => optionLabel(formatOptions, format) ?? 'Група (очно)';

/// `att` (optional) is one child's attendance row: adds "+друк" when that
/// child's work on an online lesson is being printed.
/// Without `att`, "+друк" means the lesson's own "+ друк" tick (sql/0021).
String lessonFormatLabel(Lesson lesson, [Attendance? att]) =>
    formatLabel(lesson.format) +
    (isOnlineFormat(lesson.format) && (att != null ? att.printEnabled : lesson.printDefault) ? ' +друк' : '');

/// Must match the default in lesson_print_surcharge() (sql/0017).
const defaultOnlinePrintPrice = 100.0;

double defaultPrintPrice(RateCard? rc) => rc?.value('price_print_online') ?? defaultOnlinePrintPrice;

/// Only 3D courses involve a physically printed model.
bool courseHasPrinting(String? course) => course == null || course.startsWith('3D');

/// Whether one child's work on this lesson goes to the printer: a 3D course,
/// and on an online lesson only if the admin ticked "Друк" for that child.
bool lessonPrintsFor(Lesson lesson, Attendance? att) =>
    courseHasPrinting(lesson.course) && (!isOnlineFormat(lesson.format) || (att?.printEnabled ?? false));

/// Which bucket of the rate card a lesson's amounts fall into. Only the
/// plain in-person group format is split by headcount.
String payrollBucket(String format, int studentCount) {
  switch (format) {
    case 'individual':
    case 'individual_online':
    case 'group_online':
      return format;
    default:
      return studentCount <= 1 ? 'group_1' : 'group_2_6';
  }
}

const payrollBucketLabels = {
  'group_1': 'Група (1)',
  'group_2_6': 'Група (2-6)',
  'individual': 'Індив (очно)',
  'individual_online': 'Індив (online)',
  'group_online': 'Група (online)',
  'extra_service': 'Додаткова послуга',
};

/// The six billable categories: each is a `zp_<key>` and a `price_<key>` column.
const rateBuckets = [
  Option('group_1', 'Група (1)'),
  Option('group_2_6', 'Група (2-6)'),
  Option('individual', 'Індив (очно)'),
  Option('individual_online', 'Індив (online)'),
  Option('group_online', 'Група (online)'),
  Option('extra_service', 'Додаткова послуга'),
];

/// One 4-lesson package price per format: `rate_cards.price_sub_<key>`.
const subscriptionFormats = [
  Option('group', 'Група (очно)'),
  Option('individual', 'Індив (очно)'),
  Option('individual_online', 'Індив (online)'),
  Option('group_online', 'Група (online)'),
];

class Amounts {
  final double zp;
  final double price;
  const Amounts(this.zp, this.price);
}

/// Preview of what the database trigger will freeze onto a lesson. `price`
/// must only ever be shown to admins.
Amounts computeAmounts(RateCard? rc, String format, int studentCount, bool extraService) {
  if (rc == null) return const Amounts(0, 0);
  final bucket = payrollBucket(format, studentCount);
  var zp = rc.value('zp_$bucket') ?? 0;
  var price = rc.value('price_$bucket') ?? 0;
  if (extraService) {
    zp += rc.value('zp_extra_service') ?? 0;
    price += rc.value('price_extra_service') ?? 0;
  }
  return Amounts(zp, price);
}

enum CourseTrack { threeD, vr, robo, other }

CourseTrack courseTrack(String? course) {
  if (course == null) return CourseTrack.other;
  if (course.startsWith('VR')) return CourseTrack.vr;
  if (course.startsWith('3D')) return CourseTrack.threeD;
  if (course.startsWith('Robo')) return CourseTrack.robo;
  return CourseTrack.other;
}

// --- cost of printed models (sql/0019) ------------------------------------

/// "PLA Matte · Чорний", as filamentLabel() on the web.
String filamentLabel(String? material, String? color) =>
    [material, color].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

/// "2:05" for 125 minutes.
String formatPrintMinutes(num minutes) {
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// "42 г · 2:05 год", or null when nothing was entered (workPrintSummary()).
String? printSummary(double? weightG, double? minutes) {
  if (weightG == null && minutes == null) return null;
  return [
    if (weightG != null) '${formatGrams(weightG)} г',
    if (minutes != null) '${formatPrintMinutes(minutes)} год',
  ].join(' · ');
}

/// One decimal at most, as formatMoneyless() on the web.
String formatGrams(num g) {
  final v = (g * 10).round() / 10;
  return v == v.roundToDouble() ? '${v.round()}' : v.toString().replaceAll('.', ',');
}

/// "3 моделі", "5 моделей".
String pluralUk(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n $one';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n $few';
  return '$n $many';
}

String pluralModels(int n) => pluralUk(n, 'модель', 'моделі', 'моделей');

// --- parents' portal (sql/0018) -------------------------------------------

/// Digits with the 380 prefix, like parent_normalize_phone(): "067 123 45
/// 67", "+380671234567" and "380 (67) 123-45-67" are the same login.
String normalizeParentPhone(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^0\d{9}$').hasMatch(d)) return '38$d';
  if (RegExp(r'^\d{9}$').hasMatch(d)) return '380$d';
  if (RegExp(r'^80\d{9}$').hasMatch(d)) return '3$d';
  return d;
}

/// "+380 67 123 45 67", as formatParentPhone() on the web.
String formatParentPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  final d = normalizeParentPhone(phone);
  final m = RegExp(r'^380(\d{2})(\d{3})(\d{2})(\d{2})$').firstMatch(d);
  return m == null ? '+$d' : '+380 ${m[1]} ${m[2]} ${m[3]} ${m[4]}';
}

/// What to send a parent with a new password (ParentPasswordModal).
String parentPasswordMessage(String phone, String password) =>
    'Кабінет батьків Stemik: $parentPortalUrl\nЛогін: ${formatParentPhone(phone)}\nПароль: $password';

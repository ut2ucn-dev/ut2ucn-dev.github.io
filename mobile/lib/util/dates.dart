// Date helpers. Lessons store a plain local date ("2026-10-24") and time
// ("16:30"); everything here works on local wall-clock values and never
// goes through UTC, which would shift dates for Ukraine (see the note on
// addDays() in index.html).

import 'package:intl/intl.dart';

const months = [
  'січня',
  'лютого',
  'березня',
  'квітня',
  'травня',
  'червня',
  'липня',
  'серпня',
  'вересня',
  'жовтня',
  'листопада',
  'грудня',
];
const monthsNominative = [
  'Січень',
  'Лютий',
  'Березень',
  'Квітень',
  'Травень',
  'Червень',
  'Липень',
  'Серпень',
  'Вересень',
  'Жовтень',
  'Листопад',
  'Грудень',
];
const weekdays = ['понеділок', 'вівторок', 'середа', 'четвер', "п'ятниця", 'субота', 'неділя'];
const weekdaysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'НД'];

DateTime parseDate(String d) {
  final p = d.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String todayStr() => isoDate(DateTime.now());

String addDays(String d, int n) {
  final dt = parseDate(d);
  return isoDate(DateTime(dt.year, dt.month, dt.day + n));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

bool isPast(String d) => d.compareTo(todayStr()) < 0;

String weekdayName(DateTime d) => weekdays[d.weekday - 1];
String weekdayShort(DateTime d) => weekdaysShort[d.weekday - 1];

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "24 жовтня 2026 · субота"
String formatDateLong(String d) {
  final dt = parseDate(d);
  return '${dt.day} ${months[dt.month - 1]} ${dt.year} · ${weekdayName(dt)}';
}

/// "Субота, 24.10"
String lessonCardDateTitle(String d) {
  final dt = parseDate(d);
  return '${_cap(weekdayName(dt))}, ${_two(dt.day)}.${_two(dt.month)}';
}

/// "24 жовтня, субота"
String dayHeader(DateTime dt) => '${dt.day} ${months[dt.month - 1]}, ${weekdayName(dt)}';

String formatDateDMY(String? d) {
  if (d == null || d.isEmpty) return '';
  final dt = parseDate(d);
  return '${_two(dt.day)}.${_two(dt.month)}.${dt.year}';
}

String weekRangeLabel(DateTime start) {
  final end = start.add(const Duration(days: 6));
  if (start.month == end.month) return '${start.day}–${end.day} ${months[end.month - 1]}';
  return '${start.day} ${months[start.month - 1]} – ${end.day} ${months[end.month - 1]}';
}

int? timeToMinutes(String? t) {
  if (t == null || t.isEmpty) return null;
  final p = t.split(':');
  final h = int.tryParse(p[0]);
  if (h == null) return null;
  final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return h * 60 + m;
}

String minutesToTime(int mins) => '${_two((mins ~/ 60) % 24)}:${_two(mins % 60)}';

String? lessonEndTime(String? time, int duration) {
  final start = timeToMinutes(time);
  return start == null ? null : minutesToTime(start + duration);
}

String _two(int n) => n.toString().padLeft(2, '0');

final _money = NumberFormat.decimalPattern('uk');

String formatMoney(num? n) {
  final v = ((n ?? 0) * 100).round() / 100;
  _money.maximumFractionDigits = 2;
  _money.minimumFractionDigits = 0;
  return '${_money.format(v)} грн';
}

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../export/export_actions.dart';
import '../export/export_doc.dart';
import '../export/reports.dart';
import '../util/dates.dart';
import '../util/domain.dart';
import 'schedule/lesson_screen.dart';
import 'scope.dart';
import 'split.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pay for a date range: one teacher's own, or (admin) every teacher with a
/// studio total. Amounts are the ones the database froze on each lesson.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => PayrollScreenState();
}

class PayrollScreenState extends State<PayrollScreen> with ExportableScreen {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _to = dateOnly(DateTime.now());
  String? _expanded;

  void _preset(int monthsBack) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - monthsBack);
    setState(() {
      _from = start;
      _to = monthsBack == 0 ? dateOnly(now) : DateTime(start.year, start.month + 1, 0);
    });
  }

  /// The period and scope on screen, as an Excel or PDF file.
  @override
  Future<ExportDoc?> exportDoc() async => payrollDoc(context.storeRead, isoDate(_from), isoDate(_to));

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r != null) {
      setState(() {
        _from = r.start;
        _to = r.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final from = isoDate(_from), to = isoDate(_to);
    final lessons = store.ownedLessons.where((l) => l.date.compareTo(from) >= 0 && l.date.compareTo(to) <= 0).toList();
    final total = lessons.fold<double>(0, (s, l) => s + l.payrollAmount);
    final totalPrice = lessons.fold<double>(0, (s, l) => s + (l.priceAmount ?? 0));
    final aggregate = store.isAdmin && store.teacherFilter == null;
    final byTeacher = <String, List<Lesson>>{};
    for (final l in lessons) {
      byTeacher.putIfAbsent(l.ownerId, () => []).add(l);
    }
    final teacherRows = byTeacher.entries.toList()
      ..sort(
        (a, b) => b.value
            .fold<double>(0, (s, l) => s + l.payrollAmount)
            .compareTo(a.value.fold<double>(0, (s, l) => s + l.payrollAmount)),
      );
    final now = DateTime.now();
    final isThisMonth = _from == DateTime(now.year, now.month) && _to == dateOnly(now);
    final prev = DateTime(now.year, now.month - 1);
    final isLastMonth = _from == prev && _to == DateTime(prev.year, prev.month + 1, 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(aggregate ? 'Зарплата студії' : (store.isAdmin ? 'Зарплата викладача' : 'Моя зарплата')),
        actions: [
          ExportButton(onExport: exportAs),
          const SyncButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PickChip(label: const Text('Цей місяць'), selected: isThisMonth, onSelected: (_) => _preset(0)),
                PickChip(
                  label: Text(monthsNominative[prev.month - 1]),
                  selected: isLastMonth,
                  onSelected: (_) => _preset(1),
                ),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text('${formatDateDMY(from)} – ${formatDateDMY(to)}'),
                  onPressed: _pickRange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.account_balance_wallet_rounded,
                      value: formatMoney(total),
                      label: aggregate ? 'ЗП по студії' : 'ЗП за період',
                      color: c.successText,
                      soft: c.successSoft,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (store.isAdmin) ...[
                    Expanded(
                      child: StatTile(
                        icon: Icons.payments_rounded,
                        value: formatMoney(totalPrice),
                        label: 'ціна за період',
                        color: c.alertText,
                        soft: c.alertSoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: StatTile(icon: Icons.event_rounded, value: '${lessons.length}', label: 'занять'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (lessons.isEmpty)
              const EmptyState(emoji: '💸', title: 'За цей період занять немає')
            else if (aggregate)
              for (final e in teacherRows) _teacherGroup(context, e.key, e.value)
            else
              for (final l in lessons) _LessonPayRow(lesson: l),
          ],
        ),
      ),
    );
  }

  Widget _teacherGroup(BuildContext context, String teacherId, List<Lesson> lessons) {
    final store = context.store;
    final c = context.c;
    final t = store.data.profileById[teacherId];
    final open = _expanded == teacherId;
    final sum = lessons.fold<double>(0, (s, l) => s + l.payrollAmount);
    final price = lessons.fold<double>(0, (s, l) => s + (l.priceAmount ?? 0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = open ? null : teacherId),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Avatar(initial: t?.initials ?? '?', url: t?.photo, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t?.fullName ?? 'Невідомо', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${lessons.length} занять', style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(sum),
                          style: TextStyle(fontWeight: FontWeight.w800, color: c.successText),
                        ),
                        Text('Ціна: ${formatMoney(price)}', style: TextStyle(color: c.inkSoft, fontSize: 12)),
                      ],
                    ),
                    Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(children: [for (final l in lessons) _LessonPayRow(lesson: l, flat: true)]),
              ),
          ],
        ),
      ),
    );
  }
}

class _LessonPayRow extends StatelessWidget {
  const _LessonPayRow({required this.lesson, this.flat = false});
  final Lesson lesson;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final bucket = payrollBucket(lesson.format, lesson.studentIds.length);
    final body = InkWell(
      onTap: () => openPage(context, LessonScreen(lessonId: lesson.id)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            DateBadge(lesson.date),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.theme,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (lesson.course != null) CourseTag(lesson.course!),
                      Tag(payrollBucketLabels[bucket] ?? bucket),
                      if (lesson.extraService) Tag('+ дод. послуга', color: c.brandText, soft: c.brandSoft),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(lesson.payrollAmount),
                  style: TextStyle(fontWeight: FontWeight.w800, color: c.successText),
                ),
                if (store.isAdmin)
                  Text('Ціна: ${formatMoney(lesson.priceAmount)}', style: TextStyle(color: c.inkSoft, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
    if (flat) return body;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(clipBehavior: Clip.antiAlias, child: body),
    );
  }
}

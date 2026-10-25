import '../data/models.dart';
import '../data/store.dart';
import '../util/dates.dart';
import '../util/domain.dart';
import '../util/text.dart';
import 'export_doc.dart';

String _period(String from, String to) => '${formatDateDMY(from)} – ${formatDateDMY(to)}';
String _stem(String title, String from, String to) => 'Stemik — $title ${formatDateDMY(from)}–${formatDateDMY(to)}';

/// Pay for [from]..[to], exactly as the payroll screen shows it: the
/// lessons in the current scope (the whole studio, or the teacher picked
/// in the sidebar, or a teacher's own) with the amounts the database froze
/// on them. Prices only for admins.
ExportDoc payrollDoc(AppStore store, String from, String to) {
  final data = store.data;
  final admin = store.isAdmin;
  final aggregate = admin && store.teacherFilter == null;
  final lessons = store.ownedLessons.where((l) => l.date.compareTo(from) >= 0 && l.date.compareTo(to) <= 0).toList()
    ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  double pay(Iterable<Lesson> ls) => ls.fold(0.0, (s, l) => s + l.payrollAmount);
  double price(Iterable<Lesson> ls) => ls.fold(0.0, (s, l) => s + (l.priceAmount ?? 0));
  String teacher(String id) => data.profileById[id]?.fullName ?? 'Невідомо';

  final title = aggregate
      ? 'Зарплата студії'
      : admin
      ? 'Зарплата: ${teacher(store.teacherFilter!)}'
      : 'Зарплата: ${store.me.fullName}';

  final byTeacher = <String, List<Lesson>>{};
  for (final l in lessons) {
    byTeacher.putIfAbsent(l.ownerId, () => []).add(l);
  }
  final teachers = byTeacher.entries.toList()..sort((a, b) => pay(b.value).compareTo(pay(a.value)));

  return ExportDoc(
    title: title,
    period: _period(from, to),
    fileStem: _stem(title, from, to),
    summary: [
      (aggregate ? 'ЗП по студії' : 'ЗП за період', formatMoney(pay(lessons))),
      if (admin) ('Ціна занять', formatMoney(price(lessons))),
      ('Занять', '${lessons.length}'),
    ],
    tables: [
      if (aggregate)
        ExportTable(
          title: 'Викладачі',
          columns: [
            const ExportColumn('Викладач', width: 30),
            const ExportColumn('Занять', kind: ColKind.integer, width: 10),
            const ExportColumn('ЗП', kind: ColKind.money, width: 16),
            const ExportColumn('Ціна занять', kind: ColKind.money, width: 16),
          ],
          rows: [
            for (final e in teachers) [teacher(e.key), e.value.length, pay(e.value), price(e.value)],
          ],
          total: ['Разом', lessons.length, pay(lessons), price(lessons)],
          empty: 'За цей період занять немає.',
        ),
      ExportTable(
        title: 'Заняття',
        columns: [
          const ExportColumn('Дата', kind: ColKind.date, width: 12),
          const ExportColumn('Час', width: 8),
          if (aggregate) const ExportColumn('Викладач', width: 24),
          const ExportColumn('Напрямок', width: 24),
          const ExportColumn('Тема', width: 30),
          const ExportColumn('Формат', width: 16),
          const ExportColumn('Учнів', kind: ColKind.integer, width: 8),
          const ExportColumn('ЗП', kind: ColKind.money, width: 14),
          if (admin) const ExportColumn('Ціна', kind: ColKind.money, width: 14),
        ],
        rows: [
          for (final l in lessons)
            [
              l.date,
              l.time ?? '',
              if (aggregate) teacher(l.ownerId),
              l.course ?? '',
              l.theme,
              payrollBucketLabels[payrollBucket(l.format, l.studentIds.length)] ?? formatLabel(l.format),
              l.studentIds.length,
              l.payrollAmount,
              if (admin) l.priceAmount,
            ],
        ],
        total: [
          'Разом',
          null,
          if (aggregate) null,
          null,
          null,
          null,
          lessons.fold<int>(0, (n, l) => n + l.studentIds.length),
          pay(lessons),
          if (admin) price(lessons),
        ],
        empty: 'За цей період занять немає.',
      ),
    ],
  );
}

/// The superadmin's studio report: the same summary and lists as the
/// report screen (studio_report_summary() and the report_* views).
ExportDoc studioReportDoc({
  required String from,
  required String to,
  required Map<String, dynamic> summary,
  required List<Map<String, dynamic>> paid,
  required List<Map<String, dynamic>> debt,
  required List<Map<String, dynamic>> subscriptions,
  required List<Map<String, dynamic>> excused,
}) {
  num n(String k) => (summary[k] as num?) ?? 0;
  num amount(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  String pm(Object? m) => optionLabel(paymentMethods, m as String?) ?? (m ?? '');
  int byDateThenName(Map<String, dynamic> a, Map<String, dynamic> b) {
    final d = '${a['lesson_date'] ?? ''}'.compareTo('${b['lesson_date'] ?? ''}');
    return d != 0 ? d : ukCompare('${a['student_name'] ?? ''}', '${b['student_name'] ?? ''}');
  }

  final paidRows = [...paid]..sort(byDateThenName);
  final debtRows = [...debt]..sort(byDateThenName);
  const title = 'Звіт студії';
  return ExportDoc(
    title: title,
    period: _period(from, to),
    fileStem: _stem(title, from, to),
    summary: [
      ('Оплачено · ${n('paid_count')} занять', formatMoney(n('paid_total'))),
      ('Заборгованість · ${n('debt_count')} занять', formatMoney(n('debt_total'))),
      ('Невикористані заняття (станом на зараз)', '${n('unused_subscription_lessons') + n('unused_excused_count')}'),
    ],
    tables: [
      ExportTable(
        title: 'Оплачено',
        columns: const [
          ExportColumn('Дата', kind: ColKind.date, width: 12),
          ExportColumn('Учень', width: 26),
          ExportColumn('Напрямок', width: 24),
          ExportColumn('Оплата', width: 14),
          ExportColumn('Сума', kind: ColKind.money, width: 14),
        ],
        rows: [
          for (final r in paidRows)
            [r['lesson_date'], r['student_name'], r['course'], pm(r['payment_method']), amount(r['amount'])],
        ],
        total: ['Разом', null, null, null, paidRows.fold<num>(0, (s, r) => s + amount(r['amount']))],
        empty: 'За цей період оплачених занять немає.',
      ),
      ExportTable(
        title: 'Заборгованість',
        columns: const [
          ExportColumn('Дата', kind: ColKind.date, width: 12),
          ExportColumn('Учень', width: 26),
          ExportColumn('Напрямок', width: 24),
          ExportColumn('Ціна', kind: ColKind.money, width: 14),
        ],
        rows: [
          for (final r in debtRows) [r['lesson_date'], r['student_name'], r['course'], amount(r['price_amount'])],
        ],
        total: ['Разом', null, null, debtRows.fold<num>(0, (s, r) => s + amount(r['price_amount']))],
        empty: 'Заборгованості за цей період немає.',
      ),
      ExportTable(
        title: 'Невикористані',
        columns: const [
          ExportColumn('Учень', width: 26),
          ExportColumn('Напрямок', width: 24),
          ExportColumn('Що лишилось', width: 30),
          ExportColumn('Занять', kind: ColKind.integer, width: 9),
          ExportColumn('Сума', kind: ColKind.money, width: 14),
        ],
        rows: [
          for (final r in subscriptions)
            [
              r['student_name'],
              r['course'],
              'Абонемент ${r['remaining_lessons']}/${r['total_lessons']}',
              amount(r['remaining_lessons']),
              null,
            ],
          for (final r in excused)
            [
              r['student_name'],
              r['course'],
              'ВПП ${formatDateDMY(r['lesson_date'] as String?)}, ${pm(r['payment_method'])}',
              1,
              amount(r['amount']),
            ],
        ],
        total: [
          'Разом',
          null,
          null,
          n('unused_subscription_lessons') + n('unused_excused_count'),
          excused.fold<num>(0, (s, r) => s + amount(r['amount'])),
        ],
        empty: 'Невикористаних оплачених занять немає.',
      ),
    ],
  );
}

/// What printing cost over [from]..[to] (the «Друк (бета)» analytics).
ExportDoc printCostsDoc(List<PrintCost> rows, String from, String to) {
  final costed = rows.where((r) => r.totalCost != null).toList()..sort((a, b) => a.printDate.compareTo(b.printDate));
  final missing = rows.where((r) => r.totalCost == null).toList()..sort((a, b) => a.printDate.compareTo(b.printDate));
  double sum(double? Function(PrintCost) f) => costed.fold(0.0, (s, r) => s + (f(r) ?? 0));
  final total = sum((r) => r.totalCost);

  ExportTable group(String title, String column, String Function(PrintCost) key) {
    final map = <String, (int, double)>{};
    for (final r in costed) {
      final g = map[key(r)] ?? (0, 0.0);
      map[key(r)] = (g.$1 + 1, g.$2 + (r.totalCost ?? 0));
    }
    final groups = map.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return ExportTable(
      title: title,
      columns: [
        ExportColumn(column, width: 30),
        const ExportColumn('Моделей', kind: ColKind.integer, width: 10),
        const ExportColumn('Сума', kind: ColKind.money, width: 14),
      ],
      rows: [
        for (final g in groups) [g.key, g.value.$1, g.value.$2],
      ],
      total: ['Разом', costed.length, total],
      empty: 'За цей період немає моделей з даними друку.',
    );
  }

  const title = 'Собівартість друку';
  return ExportDoc(
    title: title,
    period: _period(from, to),
    fileStem: _stem(title, from, to),
    summary: [
      ('Витрачено за період', formatMoney(total)),
      ('Моделей надруковано', '${rows.length}'),
      ('Середня вартість моделі', formatMoney(costed.isEmpty ? 0 : total / costed.length)),
      ('Пластик', formatMoney(sum((r) => r.materialCost))),
      ('Електроенергія', formatMoney(sum((r) => r.electricityCost))),
      ('Амортизація', formatMoney(sum((r) => r.depreciationCost))),
      ('Пластику', '${formatGrams(sum((r) => r.weightG))} г'),
    ],
    tables: [
      group('За напрямком', 'Напрямок', (r) => r.course ?? 'Без напрямку'),
      group('За принтером', 'Принтер', (r) => r.printerName ?? 'Принтер не вказано'),
      group(
        'За пластиком',
        'Пластик',
        (r) => r.filamentMaterial == null ? 'Пластик не вказано' : filamentLabel(r.filamentMaterial, r.filamentColor),
      ),
      ExportTable(
        title: 'Усі моделі',
        newPage: true,
        columns: const [
          ExportColumn('Дата', kind: ColKind.date, width: 12),
          ExportColumn('Учень', width: 22),
          ExportColumn('Напрямок', width: 22),
          ExportColumn('Вага, г', kind: ColKind.decimal, width: 9),
          ExportColumn('Час', width: 8),
          ExportColumn('Принтер', width: 16),
          ExportColumn('Пластик', width: 16),
          ExportColumn('Пластик, грн', kind: ColKind.money, width: 13),
          ExportColumn('Електрика, грн', kind: ColKind.money, width: 13),
          ExportColumn('Амортизація, грн', kind: ColKind.money, width: 13),
          ExportColumn('Разом', kind: ColKind.money, width: 13),
        ],
        rows: [
          for (final r in costed)
            [
              r.printDate,
              r.studentName ?? '—',
              r.course ?? '',
              r.weightG,
              r.printMinutes == null ? '' : formatPrintMinutes(r.printMinutes!),
              r.printerName ?? '',
              r.filamentMaterial == null ? '' : filamentLabel(r.filamentMaterial, r.filamentColor),
              r.materialCost,
              r.electricityCost,
              r.depreciationCost,
              r.totalCost,
            ],
        ],
        total: [
          'Разом',
          null,
          null,
          sum((r) => r.weightG),
          null,
          null,
          null,
          sum((r) => r.materialCost),
          sum((r) => r.electricityCost),
          sum((r) => r.depreciationCost),
          total,
        ],
        empty: 'Немає даних.',
      ),
      ExportTable(
        title: 'Без даних друку',
        columns: const [
          ExportColumn('Дата', kind: ColKind.date, width: 12),
          ExportColumn('Учень', width: 24),
          ExportColumn('Напрямок', width: 24),
          ExportColumn('Тема', width: 30),
        ],
        rows: [
          for (final r in missing) [r.printDate, r.studentName ?? '—', r.course ?? '', r.theme ?? ''],
        ],
        empty: 'Усі надруковані моделі за період мають дані.',
      ),
    ],
  );
}

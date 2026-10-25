import 'package:flutter/material.dart';

import '../../export/export_actions.dart';
import '../../export/export_doc.dart';
import '../../export/reports.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Superadmin studio report. Every sum comes from studio_report_summary()
/// and the report_* views; the database returns nothing to anyone else.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => ReportScreenState();
}

class ReportScreenState extends State<ReportScreen> with ExportableScreen {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _to = dateOnly(DateTime.now());
  bool _loading = true;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _paid = [], _debt = [], _subs = [], _excused = [];
  String? _open;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _summary == null) _load();
  }

  Future<void> _load() async {
    final store = context.storeRead;
    final api = store.api;
    final from = isoDate(_from), to = isoDate(_to);
    setState(() => _loading = true);
    final res = await store.fetch(
      () => Future.wait<Object?>([
        api.fetchReportSummary(from, to),
        api.fetchReportView('report_paid', from: from, to: to, orderBy: 'lesson_date'),
        api.fetchReportView('report_debt', from: from, to: to, orderBy: 'lesson_date'),
        api.fetchReportView('report_unused_subscriptions', orderBy: 'purchased_at'),
        api.fetchReportView('report_unused_excused', orderBy: 'lesson_date'),
      ]),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) return;
      _summary = res[0] as Map<String, dynamic>?;
      _paid = (res[1] as List).cast();
      _debt = (res[2] as List).cast();
      _subs = (res[3] as List).cast();
      _excused = (res[4] as List).cast();
    });
  }

  @override
  Future<ExportDoc?> exportDoc() async {
    if (_loading || _summary == null) {
      context.storeRead.say('Звіт ще завантажується');
      return null;
    }
    return studioReportDoc(
      from: isoDate(_from),
      to: isoDate(_to),
      summary: _summary!,
      paid: _paid,
      debt: _debt,
      subscriptions: _subs,
      excused: _excused,
    );
  }

  String _pm(Object? m) => optionLabel(paymentMethods, m as String?) ?? m ?? '';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _summary ?? const {};
    num n(String k) => (s[k] as num?) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Звіт студії'),
        actions: [ExportButton(onExport: exportAs)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            ActionChip(
              avatar: const Icon(Icons.date_range_rounded, size: 18),
              label: Text('${formatDateDMY(isoDate(_from))} – ${formatDateDMY(isoDate(_to))}'),
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDateRange: DateTimeRange(start: _from, end: _to),
                );
                if (r != null) {
                  _from = r.start;
                  _to = r.end;
                  _load();
                }
              },
            ),
            const SizedBox(height: 6),
            Text(
              '«Невикористані» — станом на зараз, незалежно від обраного періоду.',
              style: TextStyle(color: c.inkSoft, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: LoadingView(text: 'Завантаження звіту…'),
              )
            else ...[
              _section(
                'paid',
                'Оплачено',
                formatMoney(n('paid_total')),
                '${n('paid_count')} занять · П + оплата',
                c.successText,
                c.successSoft,
                [
                  for (final r in _paid)
                    _row(
                      '${r['student_name']}',
                      '${formatDateLong(r['lesson_date'] as String)} · ${r['course']} · ${_pm(r['payment_method'])}',
                      r['amount'],
                    ),
                ],
                'За цей період оплачених занять немає.',
              ),
              _section(
                'debt',
                'Заборгованість',
                formatMoney(n('debt_total')),
                '${n('debt_count')} занять · П без оплати',
                c.alertText,
                c.alertSoft,
                [
                  for (final r in _debt)
                    _row(
                      '${r['student_name']}',
                      '${formatDateLong(r['lesson_date'] as String)} · ${r['course']}',
                      r['price_amount'],
                    ),
                ],
                'Заборгованості за цей період немає.',
              ),
              _section(
                'unused',
                'Невикористані заняття',
                '${n('unused_subscription_lessons') + n('unused_excused_count')}',
                'абонементи, що лишились + ВПП з оплатою',
                c.brandText,
                c.brandSoft,
                [
                  for (final r in _subs)
                    _row(
                      '${r['student_name']}',
                      '${r['course']} · абонемент ${r['remaining_lessons']}/${r['total_lessons']}',
                      null,
                    ),
                  for (final r in _excused)
                    _row(
                      '${r['student_name']}',
                      '${formatDateLong(r['lesson_date'] as String)} · ${r['course']} · ВПП, ${_pm(r['payment_method'])}',
                      r['amount'],
                    ),
                ],
                'Невикористаних оплачених занять немає.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String title, String sub, Object? amount) => ListTile(
    dense: true,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub),
    trailing: amount == null
        ? null
        : Text(formatMoney(amount as num?), style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _section(
    String id,
    String title,
    String value,
    String label,
    Color fg,
    Color bg,
    List<Widget> rows,
    String empty,
  ) {
    final c = context.c;
    final open = _open == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _open = open ? null : id),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
                      child: Icon(Icons.insights_rounded, color: fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(label, style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  ],
                ),
              ),
            ),
            if (open)
              rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(empty, style: TextStyle(color: c.inkSoft)),
                    )
                  : Column(children: rows),
          ],
        ),
      ),
    );
  }
}

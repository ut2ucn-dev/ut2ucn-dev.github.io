import 'package:flutter/material.dart';

import '../../util/dates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Pay rates and prices per course (superadmin; RateCardsTab in index.html).
class RatesScreen extends StatefulWidget {
  const RatesScreen({super.key});

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends State<RatesScreen> {
  String _view = 'zp'; // zp | price | sub
  final Map<String, Map<String, TextEditingController>> _fields = {};
  String? _calcStart;
  String? _calcInput;
  bool _loading = true;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  List<String> get _columns => [
    for (final b in rateBuckets) ...['zp_${b.value}', 'price_${b.value}'],
    'price_print_online',
    for (final f in subscriptionFormats) 'price_sub_${f.value}',
  ];

  Future<void> _load() async {
    final store = context.storeRead;
    final rows =
        await store.fetch(() => store.api.fetchRateCards()) ??
        store.data.rateCardByCourse.values.map((r) => r.raw).toList();
    final calc = await store.fetch(() => store.api.fetchCalcStartDate(), quiet: true);
    if (!mounted) return;
    for (final m in _fields.values) {
      for (final ctl in m.values) {
        ctl.dispose();
      }
    }
    _fields.clear();
    for (final course in courseOptions) {
      final row = rows.where((r) => r['course'] == course).firstOrNull ?? const {};
      _fields[course] = {
        for (final col in _columns)
          col: TextEditingController(
            text: row[col] == null ? (col == 'price_print_online' ? '' : '0') : _fmt(row[col]),
          ),
      };
    }
    setState(() {
      _calcStart = calc;
      _calcInput = calc;
      _loading = false;
    });
  }

  static String _fmt(Object? v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  @override
  void dispose() {
    for (final m in _fields.values) {
      for (final ctl in m.values) {
        ctl.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _saveAll() async {
    final store = context.storeRead;
    final rows = [
      for (final course in courseOptions)
        {
          'course': course,
          for (final col in _columns)
            col: col == 'price_print_online'
                ? (_fields[course]![col]!.text.trim().isEmpty
                      ? null
                      : (num.tryParse(_fields[course]![col]!.text.trim()) ?? 0).clamp(0, double.infinity))
                : num.tryParse(_fields[course]![col]!.text.trim()) ?? 0,
        },
    ];
    setState(() => _saving = true);
    await store.online(() => store.api.upsertRateCards(rows), done: 'Тарифи збережено');
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _applyCalc(String? date) async {
    final store = context.storeRead;
    final ok = await confirmDialog(
      context,
      date == null
          ? 'Прибрати поріг? Нові й відредаговані заняття знову рахуватимуться незалежно від дати. Уже обнулені старі заняття залишаться з сумою 0 — це не відновлюється.'
          : 'Усі заняття до ${formatDateDMY(date)} (включно з уже проведеними) отримають ЗП і Ціну = 0 назавжди. Заняття з цієї дати й пізніше рахуються як завжди. Це незворотно. Продовжити?',
      title: date == null ? 'Вимкнути поріг' : 'Увімкнути розрахунок з дати',
      confirmLabel: date == null ? 'Вимкнути' : 'Так, застосувати',
    );
    if (ok != true) return;
    if (await store.online(
      () => store.api.setCalcStartDate(date),
      done: date == null ? 'Поріг вимкнено' : 'Дату застосовано, старі заняття обнулено',
    )) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тарифи')),
        body: const LoadingView(),
      );
    }
    final cols = _view == 'sub'
        ? [for (final f in subscriptionFormats) ('price_sub_${f.value}', f.label, false)]
        : [
            for (final b in rateBuckets) ('${_view}_${b.value}', b.label, false),
            if (_view == 'price') ('price_print_online', 'Друк (online)', true),
          ];
    return Scaffold(
      appBar: AppBar(title: const Text('Тарифи')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _saveAll,
            child: Text(_saving ? 'Збереження…' : 'Зберегти всі тарифи'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.alertSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.alert, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Дата початку розрахунку для студії',
                  style: TextStyle(color: c.alertText, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _calcStart != null
                      ? 'Зараз увімкнено з ${formatDateDMY(_calcStart)}: усі заняття до цієї дати мають ЗП і Ціну = 0.'
                      : 'Поки вимкнено — всі заняття рахуються як завжди, незалежно від дати.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _calcInput != null ? parseDate(_calcInput!) : DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _calcInput = isoDate(d));
                      },
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(_calcInput == null ? 'Обрати дату' : formatDateDMY(_calcInput)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: c.danger),
                      onPressed: _calcInput == null || _calcInput == _calcStart ? null : () => _applyCalc(_calcInput),
                      child: const Text('Застосувати'),
                    ),
                    if (_calcStart != null)
                      TextButton(onPressed: () => _applyCalc(null), child: const Text('Вимкнути поріг')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'zp', label: Text('ЗП')),
                ButtonSegment(value: 'price', label: Text('Ціна')),
                ButtonSegment(value: 'sub', label: Text('Абонемент')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _view == 'sub'
                ? 'Ціна всіх 4 занять пакету одразу, окремо для кожного формату. Її визначає формат заняття, на якому купують абонемент. На онлайн-заняттях абонемент покриває і друк.'
                : _view == 'price'
                ? 'За одне заняття, грн. «Друк (online)» додається до оплати учня онлайн-заняття з галочкою «Друк»; порожнє поле = 100 грн.'
                : 'ЗП викладачу за одне заняття, грн. «Додаткова послуга» додається зверху. Друк ЗП не змінює.',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          for (final course in courseOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text(
                    course,
                    style: TextStyle(fontWeight: FontWeight.w700, color: c.course(course).color),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final (col, label, nullable) in cols)
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: _fields[course]![col],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: label,
                                suffixText: 'грн',
                                hintText: nullable ? '100' : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

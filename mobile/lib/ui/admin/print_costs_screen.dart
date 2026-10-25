import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../export/export_actions.dart';
import '../../export/export_doc.dart';
import '../../export/reports.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Cost of printed models (admins; PrintCostsTab in index.html, sql/0019):
/// what printing cost over a period, and the printers, filaments, tariff
/// and waste % it is computed from. The database computes and freezes each
/// model's cost when it is marked printed; this only shows and edits.
class PrintCostsScreen extends StatefulWidget {
  const PrintCostsScreen({super.key});

  @override
  State<PrintCostsScreen> createState() => PrintCostsScreenState();
}

class PrintCostsScreenState extends State<PrintCostsScreen> with ExportableScreen {
  bool _setup = false;
  final _stats = GlobalKey<_PrintStatsState>();

  /// The analytics for the period on screen (from either tab).
  @override
  Future<ExportDoc?> exportDoc() async {
    if (_setup) {
      setState(() => _setup = false);
      await WidgetsBinding.instance.endOfFrame;
    }
    return _stats.currentState?.exportDoc();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Собівартість друку'),
        actions: [ExportButton(onExport: exportAs)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Аналітика'), icon: Icon(Icons.insights_rounded)),
                  ButtonSegment(value: true, label: Text('Принтери і пластик'), icon: Icon(Icons.tune_rounded)),
                ],
                selected: {_setup},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _setup = v.first),
              ),
            ),
          ),
        ),
      ),
      body: _setup ? const _PrintSetup() : _PrintStats(key: _stats),
    );
  }
}

// --- analytics --------------------------------------------------------------

class _PrintStats extends StatefulWidget {
  const _PrintStats({super.key});

  @override
  State<_PrintStats> createState() => _PrintStatsState();
}

class _PrintStatsState extends State<_PrintStats> {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _to = dateOnly(DateTime.now());
  bool _loading = true;
  bool _started = false;
  List<PrintCost> _rows = [];
  String? _open = 'course';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void>? _loadingDone;

  Future<ExportDoc?> exportDoc() async {
    await _loadingDone;
    return printCostsDoc(_rows, isoDate(_from), isoDate(_to));
  }

  Future<void> _load() => _loadingDone = _fetch();

  Future<void> _fetch() async {
    final store = context.storeRead;
    setState(() => _loading = true);
    final rows = await store.fetch(() => store.api.fetchPrintCosts(isoDate(_from), isoDate(_to)));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (rows != null) _rows = rows.map(PrintCost.new).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final costed = _rows.where((r) => r.totalCost != null).toList();
    final missing = _rows.where((r) => r.totalCost == null).toList();
    double sum(double? Function(PrintCost) f) => costed.fold(0.0, (s, r) => s + (f(r) ?? 0));
    final total = sum((r) => r.totalCost);
    final avg = costed.isEmpty ? 0.0 : total / costed.length;

    List<({String key, int count, double total})> groupBy(String Function(PrintCost) key) {
      final map = <String, ({String key, int count, double total})>{};
      for (final r in costed) {
        final k = key(r);
        final g = map[k];
        map[k] = (key: k, count: (g?.count ?? 0) + 1, total: (g?.total ?? 0) + (r.totalCost ?? 0));
      }
      return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    }

    List<Widget> groupRows(List<({String key, int count, double total})> groups) => [
      for (final g in groups) _row(g.key, pluralModels(g.count), g.total),
    ];
    final byCourse = groupBy((r) => r.course ?? 'Без напрямку');
    final byPrinter = groupBy((r) => r.printerName ?? 'Принтер не вказано');
    final byFilament = groupBy(
      (r) => r.filamentMaterial == null ? 'Пластик не вказано' : filamentLabel(r.filamentMaterial, r.filamentColor),
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
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
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 60), child: LoadingView())
          else ...[
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.payments_rounded,
                    value: formatMoney(total),
                    label: 'Витрачено за період',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.print_rounded,
                    value: '${_rows.length}',
                    label: 'Моделей надруковано',
                    color: c.successText,
                    soft: c.successSoft,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.insights_rounded,
                    value: formatMoney(avg),
                    label: 'Середня вартість моделі',
                    color: c.vr,
                    soft: c.vrSoft,
                  ),
                ),
              ],
            ),
            if (costed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Text(
                  'З них: пластик ${formatMoney(sum((r) => r.materialCost))} · '
                  'електроенергія ${formatMoney(sum((r) => r.electricityCost))} · '
                  'амортизація ${formatMoney(sum((r) => r.depreciationCost))} · '
                  '${formatGrams(sum((r) => r.weightG))} г пластику',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 10),
            _section(
              'course',
              Icons.category_rounded,
              'За напрямком',
              pluralUk(byCourse.length, 'напрямок', 'напрямки', 'напрямків'),
              formatMoney(total),
              groupRows(byCourse),
              'За цей період немає моделей з даними друку.',
            ),
            _section(
              'printer',
              Icons.print_rounded,
              'За принтером',
              pluralUk(byPrinter.length, 'принтер', 'принтери', 'принтерів'),
              null,
              groupRows(byPrinter),
              'Немає даних.',
            ),
            _section(
              'filament',
              Icons.palette_rounded,
              'За пластиком',
              pluralUk(byFilament.length, 'вид', 'види', 'видів'),
              null,
              groupRows(byFilament),
              'Немає даних.',
            ),
            _section('models', Icons.view_in_ar_rounded, 'Усі моделі', pluralModels(costed.length), null, [
              for (final r in costed)
                _row(
                  r.studentName ?? '—',
                  [
                    formatDateLong(r.printDate),
                    ?r.course,
                    ?printSummary(r.weightG, r.printMinutes),
                    ?r.printerName,
                    if (r.filamentMaterial != null) filamentLabel(r.filamentMaterial, r.filamentColor),
                  ].join(' · '),
                  r.totalCost,
                ),
            ], 'Немає даних.'),
            _section(
              'missing',
              Icons.help_outline_rounded,
              'Без даних друку',
              missing.isEmpty ? 'Усі моделі мають дані' : '${pluralModels(missing.length)} — не вказано вагу й час',
              null,
              [
                for (final r in missing)
                  _row(
                    r.studentName ?? '—',
                    '${formatDateLong(r.printDate)} · ${r.course ?? ''} · ${r.theme ?? ''}',
                    null,
                  ),
              ],
              'Усі надруковані моделі за період мають дані.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String title, String sub, double? amount) => ListTile(
    dense: true,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub),
    trailing: amount == null ? null : Text(formatMoney(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _section(
    String id,
    IconData icon,
    String title,
    String label,
    String? value,
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
                      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, color: c.brandText),
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
                    if (value != null)
                      Text(
                        value,
                        style: TextStyle(color: c.brandText, fontWeight: FontWeight.w800, fontSize: 16),
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

// --- printers, filaments, tariff --------------------------------------------

/// An editable directory row: text fields by column name, plus "active".
class _EditRow {
  _EditRow(this.id, Map<String, String> values, {this.active = true})
    : fields = {for (final e in values.entries) e.key: TextEditingController(text: e.value)};
  final String? id;
  final Map<String, TextEditingController> fields;
  bool active;

  String text(String key) => fields[key]!.text.trim();
  double number(String key) {
    final v = double.tryParse(text(key).replaceAll(',', '.')) ?? 0;
    return v < 0 ? 0 : v;
  }

  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
  }
}

String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');

class _PrintSetup extends StatefulWidget {
  const _PrintSetup();

  @override
  State<_PrintSetup> createState() => _PrintSetupState();
}

class _PrintSetupState extends State<_PrintSetup> {
  final _printers = <_EditRow>[];
  final _filaments = <_EditRow>[];
  final _tariff = TextEditingController();
  final _waste = TextEditingController();
  bool _loading = true;
  bool _started = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final store = context.storeRead;
    final api = store.api;
    final res = await store.fetch(
      () => Future.wait<Object?>([api.fetchPrinters(), api.fetchFilaments(), api.fetchPrintCostSettings()]),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) return;
      for (final r in [..._printers, ..._filaments]) {
        r.dispose();
      }
      _printers
        ..clear()
        ..addAll([
          for (final p in (res[0] as List).cast<Map<String, dynamic>>().map(Printer.new))
            _EditRow(p.id, {
              'name': p.name,
              'power_watts': _num(p.powerWatts),
              'depreciation_per_hour': _num(p.depreciationPerHour),
            }, active: p.active),
        ]);
      _filaments
        ..clear()
        ..addAll([
          for (final f in (res[1] as List).cast<Map<String, dynamic>>().map(Filament.new))
            _EditRow(f.id, {
              'material': f.material,
              'color': f.color ?? '',
              'price_per_kg': _num(f.pricePerKg),
            }, active: f.active),
        ]);
      final s = res[2] as Map<String, dynamic>?;
      _tariff.text = _num((s?['electricity_tariff'] as num?)?.toDouble());
      _waste.text = _num((s?['filament_waste_percent'] as num?)?.toDouble());
    });
  }

  @override
  void dispose() {
    for (final r in [..._printers, ..._filaments]) {
      r.dispose();
    }
    _tariff.dispose();
    _waste.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.storeRead;
    if (_printers.any((p) => p.text('name').isEmpty)) return store.say('Вкажіть назву кожного принтера');
    if (_filaments.any((f) => f.text('material').isEmpty)) return store.say('Вкажіть тип кожного пластику');
    double parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
    setState(() => _saving = true);
    final ok = await store.online(
      () => store.api.savePrintSetup(
        printers: [
          for (final p in _printers)
            {
              'id': p.id,
              'name': p.text('name'),
              'power_watts': p.number('power_watts'),
              'depreciation_per_hour': p.number('depreciation_per_hour'),
              'active': p.active,
            },
        ],
        filaments: [
          for (final f in _filaments)
            {
              'id': f.id,
              'material': f.text('material'),
              'color': f.text('color').isEmpty ? null : f.text('color'),
              'price_per_kg': f.number('price_per_kg'),
              'active': f.active,
            },
        ],
        tariff: parse(_tariff).clamp(0, double.infinity),
        wastePercent: parse(_waste).clamp(0, 100),
      ),
      done: 'Збережено. Нові ціни діятимуть для моделей, позначених надрукованими відтепер',
      reload: false,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _load();
      store.loadPrintDirectory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_loading) return const LoadingView();
    final tariff = double.tryParse(_tariff.text.replaceAll(',', '.')) ?? 0;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    Widget cell(TextEditingController ctl, {String? hint, bool number = false, VoidCallback? onChanged}) => TextField(
      controller: ctl,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: number ? numbers : null,
      textAlign: number ? TextAlign.right : TextAlign.left,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      decoration: InputDecoration(hintText: hint),
    );

    Widget hideButton(_EditRow r) => TextButton(
      onPressed: () => setState(() => r.active = !r.active),
      child: Text(r.active ? 'Приховати' : 'Показати'),
    );

    Widget header(List<(String, int)> cols) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          for (final (label, flex) in cols)
            Expanded(
              flex: flex,
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkSoft),
              ),
            ),
          const SizedBox(width: 104),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Як рахується собівартість моделі', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Пластик = вага × (1 + відходи %) × ціна за кг / 1000'),
                const Text('Електроенергія = години друку × потужність (Вт) / 1000 × тариф'),
                const Text('Амортизація = години друку × ₴ за годину принтера'),
                const SizedBox(height: 8),
                Text(
                  'Вагу, час, принтер і пластик вказує викладач, коли позначає модель надрукованою. Сума '
                  'фіксується в цей момент: зміна цін нижче не змінює вже порахованих моделей. Викладачі цін '
                  'не бачать.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tariff,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Тариф електроенергії', suffixText: '₴ / кВт·год'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _waste,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: numbers,
                  decoration: const InputDecoration(labelText: 'Відходи пластику', suffixText: '%'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            'Відходи — продувка, башта очищення, підтримки, браковані спроби: додаються до ваги кожної моделі.',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5),
          ),
        ),
        const SectionTitle('Принтери'),
        if (_printers.isEmpty)
          Text('Ще немає жодного принтера.', style: TextStyle(color: c.inkSoft))
        else ...[
          header([('Назва', 4), ('Потужність, Вт', 2), ('Електрика, ₴/год', 2), ('Амортизація, ₴/год', 2)]),
          for (final p in _printers)
            Opacity(
              opacity: p.active ? 1 : 0.5,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: cell(p.fields['name']!, hint: 'Bambu Lab P1S')),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: cell(p.fields['power_watts']!, number: true, onChanged: () => setState(() {})),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatMoney(p.number('power_watts') / 1000 * tariff),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: c.inkSoft),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: cell(p.fields['depreciation_per_hour']!, number: true)),
                    SizedBox(width: 104, child: hideButton(p)),
                  ],
                ),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
              () => _printers.add(_EditRow(null, {'name': '', 'power_watts': '', 'depreciation_per_hour': ''})),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Додати принтер'),
          ),
        ),
        const SectionTitle('Пластик'),
        if (_filaments.isEmpty)
          Text('Ще немає жодного пластику.', style: TextStyle(color: c.inkSoft))
        else ...[
          header([('Тип', 3), ('Колір', 3), ('₴ / кг', 2)]),
          for (final f in _filaments)
            Opacity(
              opacity: f.active ? 1 : 0.5,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: cell(f.fields['material']!, hint: 'PLA Matte')),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: cell(f.fields['color']!, hint: 'Чорний')),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: cell(f.fields['price_per_kg']!, number: true)),
                    SizedBox(width: 104, child: hideButton(f)),
                  ],
                ),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _filaments.add(_EditRow(null, {'material': '', 'color': '', 'price_per_kg': ''}))),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Додати пластик'),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Збереження…' : 'Зберегти'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Прихований принтер чи пластик зникає з вибору у викладачів, але лишається в історії вже надрукованих '
            'моделей.',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

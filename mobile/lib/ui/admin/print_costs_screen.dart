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

  /// Filled in as soon as a new row is saved, so saving again updates it.
  String? id;
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
              // The database stores watts; the admin edits consumption in kW.
              'power_kw': _num(p.powerWatts == null ? null : p.powerWatts! / 1000),
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
    final printers = [..._printers];
    final filaments = [..._filaments];
    final ok = await store.online(
      () async {
        // Each step keeps the new rows' ids right away (see _EditRow.id).
        final printerIds = await store.api.savePrintRows('printers', [
          for (final p in printers)
            {
              'id': p.id,
              'name': p.text('name'),
              'power_watts': (p.number('power_kw') * 1000 * 100).round() / 100,
              'depreciation_per_hour': p.number('depreciation_per_hour'),
              'active': p.active,
            },
        ]);
        for (var i = 0; i < printers.length; i++) {
          printers[i].id = printerIds[i];
        }
        final filamentIds = await store.api.savePrintRows('filaments', [
          for (final f in filaments)
            {
              'id': f.id,
              'material': f.text('material'),
              'color': f.text('color').isEmpty ? null : f.text('color'),
              'price_per_kg': f.number('price_per_kg'),
              'active': f.active,
            },
        ]);
        for (var i = 0; i < filaments.length; i++) {
          filaments[i].id = filamentIds[i];
        }
        await store.api.savePrintCostSettings(
          tariff: parse(_tariff).clamp(0, double.infinity),
          wastePercent: parse(_waste).clamp(0, 100),
        );
      },
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

    // "Приховати" only takes it out of the teachers' choice and is saved at
    // once; "Видалити" (bin) removes it for good after a confirmation.
    Future<void> toggleHidden(String table, _EditRow r) async {
      final store = context.storeRead;
      final id = r.id;
      if (id != null && !await store.online(() => store.api.setPrintRowActive(table, id, !r.active), reload: false)) {
        return;
      }
      if (!mounted) return;
      setState(() => r.active = !r.active);
      if (id != null) store.loadPrintDirectory();
    }

    Future<void> remove(String table, List<_EditRow> list, _EditRow r, String label) async {
      final store = context.storeRead;
      final id = r.id;
      if (id == null) {
        setState(() => list.remove(r));
        r.dispose();
        return;
      }
      final used = await store.fetch(
        () => store.api.countWorksUsing(table == 'printers' ? 'printer_id' : 'filament_id', id),
      );
      if (!context.mounted || used == null) return;
      final choice = await confirmDialog(
        context,
        'Видалити «${label.isEmpty ? 'без назви' : label}» назавжди?'
        '${used > 0 ? ' Він указаний у ${pluralModels(used)} — їхня порахована собівартість збережеться, але в аналітиці там буде «не вказано». Щоб лише прибрати його з вибору у викладачів, натисніть «Приховати».' : ''}',
        title: 'Видалити',
        confirmLabel: 'Так, видалити',
      );
      if (choice != true || !context.mounted) return;
      if (!await store.online(() => store.api.deletePrintRow(table, id), done: 'Видалено', reload: false)) return;
      if (!mounted) return;
      setState(() => list.remove(r));
      r.dispose();
      store.loadPrintDirectory();
    }

    Widget rowActions(String table, List<_EditRow> list, _EditRow r, String label) => Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => toggleHidden(table, r),
            child: Text(r.active ? 'Приховати' : 'Показати', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        IconButton(
          tooltip: 'Видалити назавжди',
          visualDensity: VisualDensity.compact,
          color: c.danger,
          onPressed: () => remove(table, list, r, label),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
        ),
      ],
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
          const SizedBox(width: 150),
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
                const Text('(Вага моделі × Вартість філаменту)'),
                const Text('+ (Час друку × Споживання принтера кВт/год × Тариф електроенергії)'),
                const Text('+ (Амортизація ₴/год × Час друку)'),
                const SizedBox(height: 6),
                Text(
                  'Вартість філаменту береться за грам (ціна за кг ÷ 1000). Якщо «Відходи пластику» більше 0 %, '
                  'вони додаються до ваги моделі; при 0 % рахунок точно за формулою вище.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                ),
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
            "Необов'язково. Відходи — продувка, башта очищення, підтримки, браковані спроби: додаються до ваги "
            'кожної моделі. Залиште 0, щоб рахувати лише вагу моделі.',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5),
          ),
        ),
        const SectionTitle('Принтери'),
        if (_printers.isEmpty)
          Text('Ще немає жодного принтера.', style: TextStyle(color: c.inkSoft))
        else ...[
          header([('Назва', 4), ('Споживання, кВт/год', 2), ('Електрика, ₴/год', 2), ('Амортизація, ₴/год', 2)]),
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
                      child: cell(p.fields['power_kw']!, number: true, onChanged: () => setState(() {})),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatMoney(p.number('power_kw') * tariff),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: c.inkSoft),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: cell(p.fields['depreciation_per_hour']!, number: true)),
                    SizedBox(width: 150, child: rowActions('printers', _printers, p, p.text('name'))),
                  ],
                ),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
              () => _printers.add(_EditRow(null, {'name': '', 'power_kw': '', 'depreciation_per_hour': ''})),
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
                    SizedBox(
                      width: 150,
                      child: rowActions(
                        'filaments',
                        _filaments,
                        f,
                        [f.text('material'), f.text('color')].where((x) => x.isNotEmpty).join(' · '),
                      ),
                    ),
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
            '«Приховати» — прибрати з вибору у викладачів, коли вони позначають модель надрукованою (у списку тут '
            'і в історії лишається). «Видалити» — прибрати назавжди, з підтвердженням.',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

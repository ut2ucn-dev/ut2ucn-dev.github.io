import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../util/domain.dart';
import 'scope.dart';
import 'theme.dart';

/// Marks a model printed at once, or un-marks it. Weight, time, printer
/// and filament are optional: they can be added afterwards from the
/// "+ дані друку" chip ([editPrintData]). True when it ends up printed.
Future<bool> togglePrinted(BuildContext context, Lesson lesson, Student student, Work? work) async {
  final store = context.storeRead;
  final printed = !(work?.printed ?? false);
  HapticFeedback.selectionClick();
  await store.setPrinted(lesson, student, printed);
  return printed;
}

/// Adds or corrects the print data of a printed model.
Future<void> editPrintData(BuildContext context, Lesson lesson, Student student, Work? work) async {
  final store = context.storeRead;
  final data = await showPrintDataDialog(context, work: work, title: student.name);
  if (data != null) await store.setPrintData(lesson, student, data);
}

/// The entered fields, or null when dismissed.
Future<Map<String, Object?>?> showPrintDataDialog(BuildContext context, {Work? work, String? title}) {
  context.storeRead.loadPrintDirectory();
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => _PrintDataDialog(work: work, title: title),
  );
}

class _PrintDataDialog extends StatefulWidget {
  const _PrintDataDialog({this.work, this.title});
  final Work? work;
  final String? title;

  @override
  State<_PrintDataDialog> createState() => _PrintDataDialogState();
}

class _PrintDataDialogState extends State<_PrintDataDialog> {
  late final _weight = TextEditingController(
    text: widget.work?.weightG == null ? '' : formatGrams(widget.work!.weightG!),
  );
  late final int? _minutes = widget.work?.printMinutes?.round();
  late final _hours = TextEditingController(text: _minutes == null ? '' : '${_minutes ~/ 60}');
  late final _mins = TextEditingController(text: _minutes == null ? '' : '${_minutes % 60}');
  String? _printerId;
  String? _filamentId;
  bool _picked = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_picked) return;
    _picked = true;
    final settings = SettingsScope.read(context);
    _printerId = widget.work?.printerId ?? settings.lastPrinterId;
    _filamentId = widget.work?.filamentId ?? settings.lastFilamentId;
  }

  @override
  void dispose() {
    _weight.dispose();
    _hours.dispose();
    _mins.dispose();
    super.dispose();
  }

  double _number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  void _save() {
    final weight = _number(_weight);
    final minutes = (_number(_hours) * 60 + _number(_mins)).round();
    if (weight <= 0) return setState(() => _error = 'Вкажіть вагу моделі в грамах');
    if (minutes <= 0) return setState(() => _error = 'Вкажіть час друку');
    SettingsScope.read(context).saveLastPrintChoice(_printerId, _filamentId);
    Navigator.pop(context, <String, Object?>{
      'weight_g': weight,
      'print_minutes': minutes,
      'printer_id': _printerId,
      'filament_id': _filamentId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    // Hidden ones stay pickable only for the model that already uses them.
    final printers = store.printers.where((p) => p.active || p.id == widget.work?.printerId).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final filaments = store.filaments.where((f) => f.active || f.id == widget.work?.filamentId).toList()
      ..sort((a, b) => a.material.compareTo(b.material));
    // A remembered choice that's since been hidden falls back to "none"; a
    // single option is picked by itself.
    final printerId = printers.any((p) => p.id == _printerId)
        ? _printerId
        : (printers.length == 1 ? printers.first.id : null);
    final filamentId = filaments.any((f) => f.id == _filamentId)
        ? _filamentId
        : (filaments.length == 1 ? filaments.first.id : null);
    _printerId = printerId;
    _filamentId = filamentId;

    // Labels stay up, so the hints and units are always visible.
    InputDecoration field(String label, {String? hint, String? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    return AlertDialog(
      title: const Text('Дані друку', style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(widget.title!, style: TextStyle(color: c.inkSoft)),
                ),
              TextField(
                controller: _weight,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: field('Вага моделі', hint: '42', suffix: 'г'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hours,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: field('Час друку', hint: '2', suffix: 'год'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _mins,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: field('і хвилин', hint: '15', suffix: 'хв'),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('printer-${printers.length}'),
                initialValue: printerId,
                isExpanded: true,
                decoration: field('Принтер'),
                hint: Text(printers.isEmpty ? 'Принтери ще не додані' : 'Оберіть принтер…'),
                items: [for (final p in printers) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => setState(() => _printerId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('filament-${filaments.length}'),
                initialValue: filamentId,
                isExpanded: true,
                decoration: field('Пластик'),
                hint: Text(filaments.isEmpty ? 'Пластик ще не доданий' : 'Оберіть пластик…'),
                items: [
                  for (final f in filaments)
                    DropdownMenuItem(value: f.id, child: Text(filamentLabel(f.material, f.color))),
                ],
                onChanged: (v) => setState(() => _filamentId = v),
              ),
              const SizedBox(height: 10),
              Text(
                'Вагу й час видно у слайсері або на екрані принтера — для цієї моделі окремо.',
                style: TextStyle(color: c.inkSoft, fontSize: 12.5),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
        FilledButton(onPressed: _save, child: const Text('Готово')),
      ],
    );
  }
}

/// "42 г · 2:05 год" under a printed model, or "+ дані друку" when nothing
/// was entered; tap to correct (PrintDataChip on the web).
class PrintDataChip extends StatelessWidget {
  const PrintDataChip({super.key, required this.work, this.onTap});
  final Work? work;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final summary = printSummary(work?.weightG, work?.printMinutes);
    final fg = summary == null ? c.alertText : c.inkSoft;
    return Material(
      color: summary == null ? c.alertSoft : c.sand,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(summary == null ? Icons.add_rounded : Icons.scale_rounded, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(
                summary ?? 'дані друку',
                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

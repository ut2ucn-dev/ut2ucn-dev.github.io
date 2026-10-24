import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme.dart';

/// Paste a list, one student per line: "Ім'я, Телефон, Прізвище батьків,
/// Ім'я батьків" — only the name is required.
class BulkAddScreen extends StatefulWidget {
  const BulkAddScreen({super.key});

  @override
  State<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends State<BulkAddScreen> {
  final _text = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rows => _text.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map((l) {
        final p = l.split(',').map((e) => e.trim()).toList();
        String at(int i) => i < p.length ? p[i] : '';
        return {'name': at(0), 'phone': at(1), 'parent_last_name': at(2), 'parent_first_name': at(3)};
      })
      .where((r) => (r['name'] as String).isNotEmpty)
      .toList();

  Future<void> _save() async {
    final store = context.storeRead;
    final rows = _rows;
    setState(() => _saving = true);
    final ok = await store.online(
      () => store.api.insertStudents([
        for (final r in rows) {...r, 'owner_id': store.me.id, 'photo': null},
      ]),
      done: 'Додано учнів: ${rows.length}',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final n = _rows.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Додати кількох учнів')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving || n == 0 ? null : _save,
            child: Text(_saving ? 'Додавання…' : (n == 0 ? 'Додати' : 'Додати ($n)')),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'По одному учню на рядок',
              alignLabelWithHint: true,
              hintText: 'Тимофій Бондаренко\nСоломія Іванчук, +380 63 234 56 78\nНазар Петренко, +380 50 345 67 89, Петренко, Ганна',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Достатньо самого імені. За бажанням через кому можна одразу додати телефон, а тоді прізвище та ім\'я батьків — саме в такому порядку.',
            style: TextStyle(color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

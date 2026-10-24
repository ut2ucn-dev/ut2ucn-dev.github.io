import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../services/photos.dart';
import '../../util/dates.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Add or edit a student (StudentModal in index.html). Pops with the saved
/// [Student] so the lesson editor can put a new child straight on a roster.
class StudentEditScreen extends StatefulWidget {
  const StudentEditScreen({super.key, this.student, this.prefillName});
  final Student? student;
  final String? prefillName;

  @override
  State<StudentEditScreen> createState() => _StudentEditScreenState();
}

class _StudentEditScreenState extends State<StudentEditScreen> {
  late final Student? s = widget.student;
  late final _name = TextEditingController(text: s?.name ?? widget.prefillName ?? '');
  late final _phone = TextEditingController(text: s?.phone ?? '');
  late String? _birthday = s?.birthday;
  late final _parentLast = TextEditingController(text: s?.parentLastName ?? '');
  late final _parentFirst = TextEditingController(text: s?.parentFirstName ?? '');
  late final _notes = TextEditingController(text: s?.notes ?? '');
  late String? _photo = s?.photo;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _parentLast, _parentFirst, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final store = context.storeRead;
    final bytes = await pickPhoto(context, title: 'Фото дитини');
    if (bytes == null) return;
    setState(() => _uploading = true);
    final key = s?.id ?? 'new_${DateTime.now().millisecondsSinceEpoch}';
    final url = await store.fetch(() => store.api.uploadPhoto('student-photos', '${store.me.id}/$key.jpg', bytes));
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) _photo = url;
    });
  }

  Future<void> _save() async {
    final store = context.storeRead;
    if (_name.text.trim().isEmpty) return setState(() => _error = "Вкажіть ім'я дитини");
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      if (s == null) 'owner_id': store.me.id,
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'birthday': _birthday,
      'parent_last_name': _parentLast.text.trim(),
      'parent_first_name': _parentFirst.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'photo': _photo,
    };
    DbRow? saved;
    final ok = await store.online(() async {
      saved = await store.api.saveStudent(payload, id: s?.id);
    }, done: s == null ? 'Учня додано' : 'Учня оновлено');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, saved == null ? null : Student(saved!));
  }

  Future<void> _delete() async {
    final store = context.storeRead;
    final ok = await confirmDialog(
      context,
      'Видалити учня «${s!.name}»? Це також видалить його роботи та прибере з усіх занять.',
      title: 'Видалити учня',
    );
    if (ok != true || !mounted) return;
    if (await store.online(() => store.api.deleteStudent(s!.id), done: 'Учня видалено')) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Новий учень' : 'Редагувати учня'),
        actions: [
          if (s != null && store.isAdmin)
            IconButton(tooltip: 'Видалити', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Збереження…' : 'Зберегти')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                _error!,
                style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
              ),
            ),
          if (store.isAdmin) ...[
            Row(
              children: [
                _uploading
                    ? const SizedBox.square(dimension: 64, child: Center(child: CircularProgressIndicator()))
                    : Avatar(initial: _name.text.isEmpty ? '?' : _name.text[0].toUpperCase(), url: _photo, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploading ? null : _pickPhoto,
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: Text(_photo == null ? 'Додати фото' : 'Замінити фото'),
                      ),
                      const SizedBox(height: 4),
                      Text('Фото дитини бачить лише адміністратор.', style: TextStyle(color: c.inkSoft, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: "Ім'я дитини", hintText: 'Марійка'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Телефон', hintText: '+380 XX XXX XX XX'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _birthday != null ? parseDate(_birthday!) : DateTime(DateTime.now().year - 9),
                firstDate: DateTime(1990),
                lastDate: DateTime.now(),
                initialDatePickerMode: DatePickerMode.year,
              );
              if (d != null) setState(() => _birthday = isoDate(d));
            },
            icon: const Icon(Icons.cake_rounded),
            label: Text(_birthday == null ? 'День народження' : 'День народження: ${formatDateDMY(_birthday)}'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _parentLast,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Прізвище батьків'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _parentFirst,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: "Ім'я батьків"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Нотатки',
              hintText: 'Будь-що важливе про учня — видно лише в його картці',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

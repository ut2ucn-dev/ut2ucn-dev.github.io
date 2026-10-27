import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../students/student_edit_screen.dart';
import '../theme.dart';
import '../widgets.dart';

/// Create or edit a lesson (admin), as LessonModal in index.html. The
/// teacher's pay and the client price are computed by a database trigger
/// on save — only previewed here.
class LessonEditScreen extends StatefulWidget {
  const LessonEditScreen({super.key, this.lesson, this.presetDate, this.presetOwnerId});
  final Lesson? lesson;
  final String? presetDate;
  final String? presetOwnerId;

  @override
  State<LessonEditScreen> createState() => _LessonEditScreenState();
}

class _LessonEditScreenState extends State<LessonEditScreen> {
  late final Lesson? l = widget.lesson;
  late String? _ownerId = l?.ownerId ?? widget.presetOwnerId;
  late String _date = l?.date ?? widget.presetDate ?? todayStr();
  late String? _time = l?.time;
  late final _duration = TextEditingController(text: '${l?.durationMinutes ?? 60}');
  late String? _room = l?.room;
  late String? _substituteId = l?.substituteOwnerId;
  late final _theme = TextEditingController(text: l?.theme ?? '');
  late String? _course = l?.course;
  late String _format = l?.format ?? 'group';
  late bool _extra = l?.extraService ?? false;
  late bool _printDefault = l?.printDefault ?? false;
  late final List<String> _studentIds = [...?l?.studentIds];
  final _query = TextEditingController();
  bool _repeat = false;
  final _weeks = TextEditingController(text: '4');
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownerId ??= context.storeRead.me.id;
  }

  @override
  void dispose() {
    _duration.dispose();
    _theme.dispose();
    _query.dispose();
    _weeks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.storeRead;
    if (_ownerId == null) return setState(() => _error = 'Оберіть викладача');
    if (_course == null) return setState(() => _error = 'Оберіть напрямок');
    if (_theme.text.trim().isEmpty) return setState(() => _error = 'Вкажіть тему заняття');
    setState(() {
      _saving = true;
      _error = null;
    });
    final duration = int.tryParse(_duration.text) ?? 60;
    final weeks = (int.tryParse(_weeks.text) ?? 1).clamp(1, 52);
    final printDefault = _printDefault && isOnlineFormat(_format);
    DbRow fields(String date) => {
      'owner_id': _ownerId,
      'date': date,
      'time': _time,
      'duration_minutes': duration,
      'room': _room,
      'theme': _theme.text.trim(),
      'course': _course,
      'format': _format,
      'student_ids': _studentIds,
      'extra_service': _extra,
      // Only sent when used, so saving works on a database without 0021 too.
      if (printDefault || (l?.printDefault ?? false)) 'print_default': printDefault,
    };

    final ok = await store.online(() async {
      final lesson = l;
      if (lesson == null) {
        final seriesId = _repeat ? const Uuid().v4() : null;
        await store.api.insertLessons([
          for (var i = 0; i < (_repeat ? weeks : 1); i++) {...fields(addDays(_date, i * 7)), 'series_id': seriesId},
        ]);
        return;
      }
      // Repeating an existing lesson extends its own series (see index.html).
      final seriesId = _repeat ? (lesson.seriesId ?? const Uuid().v4()) : lesson.seriesId;
      await store.api.updateLesson(lesson.id, {
        ...fields(_date),
        'substitute_owner_id': _substituteId,
        'series_id': seriesId,
      });
      if (_ownerId != lesson.ownerId) await store.api.reassignLessonOwner(lesson.id, _ownerId!);
      if (_repeat && weeks > 1) {
        await store.api.insertLessons([
          for (var i = 1; i < weeks; i++) {...fields(addDays(_date, i * 7)), 'series_id': seriesId},
        ]);
      }
    }, done: l == null ? 'Заняття додано' : 'Заняття оновлено');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final teachers = store.data.profiles.where((p) => p.active || p.id == _ownerId || p.id == _substituteId).toList();
    final rc = _course == null ? null : store.data.rateCardByCourse[_course];
    final amounts = computeAmounts(rc, _format, _studentIds.length, _extra);
    final q = _query.text.trim().toLowerCase();
    final roster =
        store.data.students
            .where((s) => _studentIds.contains(s.id) || q.isEmpty || s.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => (_studentIds.contains(b.id) ? 1 : 0) - (_studentIds.contains(a.id) ? 1 : 0));
    final shown = q.isEmpty ? roster.take(60).toList() : roster;

    return Scaffold(
      appBar: AppBar(title: Text(l == null ? 'Нове заняття' : 'Редагувати заняття')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Збереження…' : 'Зберегти')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                _error!,
                style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
              ),
            ),
          const SectionTitle('Викладач'),
          DropdownButtonFormField<String>(
            initialValue: _ownerId,
            isExpanded: true,
            items: [for (final t in teachers) DropdownMenuItem(value: t.id, child: Text(t.fullName))],
            onChanged: (v) => setState(() => _ownerId = v),
          ),
          if (l != null && _ownerId != l!.ownerId)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Заняття, фото робіт і відмітки відвідування перейдуть до нового викладача.',
                style: TextStyle(color: c.inkSoft, fontSize: 12.5),
              ),
            ),
          const SectionTitle('Напрямок'),
          DropdownButtonFormField<String>(
            initialValue: _course,
            isExpanded: true,
            hint: const Text('Оберіть напрямок…'),
            items: [for (final co in courseOptions) DropdownMenuItem(value: co, child: Text(co))],
            onChanged: (v) => setState(() => _course = v),
          ),
          const SectionTitle('Формат'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in formatOptions)
                PickChip(
                  label: Text(f.label),
                  selected: _format == f.value,
                  onSelected: (_) => setState(() => _format = f.value),
                ),
            ],
          ),
          if (isOnlineFormat(_format))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _printDefault,
              onChanged: (v) => setState(() => _printDefault = v ?? false),
              title: const Text('+ друк', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Учням із «П» друк увімкнеться сам (з доплатою за тарифом). Окремій дитині його можна вимкнути в картці заняття.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _extra,
            onChanged: (v) => setState(() => _extra = v ?? false),
            title: const Text('Додаткова послуга', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Сума береться з тарифів.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (rc != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, size: 18, color: c.successText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ЗП за це заняття: ${formatMoney(amounts.zp)}${store.isAdmin ? ' · Ціна: ${formatMoney(amounts.price)}' : ''}',
                      style: TextStyle(color: c.successText, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          const SectionTitle('Тема'),
          TextField(
            controller: _theme,
            decoration: const InputDecoration(hintText: 'Друк брелока'),
          ),
          const SectionTitle('Дата і час'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: parseDate(_date),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = isoDate(d));
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: Text(formatDateDMY(_date)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final m = timeToMinutes(_time) ?? 16 * 60;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                      builder: (ctx, child) =>
                          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
                    );
                    if (t != null) setState(() => _time = minutesToTime(t.hour * 60 + t.minute));
                  },
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(_time ?? 'Час'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Тривалість, хв'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _room,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Кабінет'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Без кабінету')),
                    for (final r in roomOptions) DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => _room = v),
                ),
              ),
            ],
          ),
          if (l != null) ...[
            const SectionTitle('Викладач на заміні'),
            DropdownButtonFormField<String?>(
              initialValue: _substituteId,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('Немає')),
                for (final t in teachers.where((t) => t.id != _ownerId))
                  DropdownMenuItem(value: t.id, child: Text(t.fullName)),
              ],
              onChanged: (v) => setState(() => _substituteId = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Тимчасова заміна на це заняття — основний викладач (і його ЗП) не змінюється.',
                style: TextStyle(color: c.inkSoft, fontSize: 12.5),
              ),
            ),
          ],
          SectionTitle(
            'Учні на занятті (${_studentIds.length})',
            trailing: TextButton.icon(
              onPressed: () async {
                final created = await Navigator.of(
                  context,
                ).push<Student>(MaterialPageRoute(builder: (_) => StudentEditScreen(prefillName: _query.text.trim())));
                if (created != null) {
                  setState(() {
                    _studentIds.add(created.id);
                    _query.clear();
                  });
                }
              },
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Новий'),
            ),
          ),
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Пошук учня за іменем…',
            ),
          ),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Text(
              q.isEmpty ? 'Учнів ще немає.' : 'Нічого не знайдено за «${_query.text.trim()}».',
              style: TextStyle(color: c.inkSoft),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in shown)
                  PickChip(
                    label: Text(s.name),
                    selected: _studentIds.contains(s.id),
                    onSelected: (v) => setState(() => v ? _studentIds.add(s.id) : _studentIds.remove(s.id)),
                  ),
              ],
            ),
          if (q.isEmpty && roster.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ще ${roster.length - shown.length} — скористайтеся пошуком.',
                style: TextStyle(color: c.inkSoft),
              ),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _repeat,
            onChanged: (v) => setState(() => _repeat = v ?? false),
            title: const Text('Повторювати щотижня', style: TextStyle(fontWeight: FontWeight.w600)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_repeat) ...[
            TextField(
              controller: _weeks,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Кількість тижнів'),
            ),
            if (l != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Це заняття залишиться на своєму місці, а ще ${((int.tryParse(_weeks.text) ?? 1) - 1).clamp(0, 51)} з\'являться на наступні тижні з тими самими темою, напрямком і учнями.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

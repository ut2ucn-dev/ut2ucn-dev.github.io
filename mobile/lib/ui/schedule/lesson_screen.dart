import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../data/studio_data.dart';
import '../../services/photos.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../contact.dart';
import '../scope.dart';
import '../students/student_card_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lesson_edit_screen.dart';

/// Everything about one lesson: roster, work photos and print status, and
/// (for admins) attendance with payment. Works offline.
class LessonScreen extends StatelessWidget {
  const LessonScreen({super.key, required this.lessonId});
  final String lessonId;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final data = store.data;
    final lesson = data.lessonById[lessonId];
    if (lesson == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(emoji: '🗓️', title: 'Заняття не знайдено', subtitle: 'Можливо, його видалили.'),
      );
    }
    final roster = data.roster(lesson);
    final c = context.c;
    final accent = c.course(lesson.course);
    final end = lessonEndTime(lesson.time, lesson.durationMinutes);
    final owner = data.profileById[lesson.ownerId];
    final substitute = lesson.substituteOwnerId == null ? null : data.profileById[lesson.substituteOwnerId];
    final printable = data.printable(lesson);
    final printed = data.printedCount(lesson);
    final admin = store.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(lessonCardDateTitle(lesson.date)),
        actions: [
          if (roster.isNotEmpty)
            IconButton(
              tooltip: 'Екстрені контакти',
              onPressed: () => showContactsSheet(context, roster),
              icon: Icon(Icons.contact_phone_rounded, color: c.alertText),
            ),
          if (admin)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonEditScreen(lesson: lesson)));
                } else if (v == 'delete') {
                  final deleted = await deleteLessonFlow(context, lesson);
                  if (deleted && context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Редагувати')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Видалити')),
                ),
              ],
            ),
          const SyncButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          lesson.time == null ? 'Без часу' : '${lesson.time}${end != null ? '–$end' : ''}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${lesson.durationMinutes} хв',
                          style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (admin)
                          PrintedPill(
                            printed: lesson.completed,
                            icon: Icons.radio_button_unchecked_rounded,
                            labelOn: 'Завершено',
                            labelOff: 'Не завершено',
                            onTap: () => store.setLessonCompleted(lesson, !lesson.completed),
                          )
                        else if (lesson.completed)
                          Tag('Завершено', color: c.successText, soft: c.successSoft, icon: Icons.check_rounded),
                      ],
                    ),
                    if (lesson.course != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        lesson.course!,
                        style: TextStyle(color: accent.color, fontWeight: FontWeight.w800),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(lesson.theme, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (owner != null) Tag(owner.fullName, icon: Icons.person_rounded),
                        Tag(
                          lessonFormatLabel(lesson),
                          color: isOnlineFormat(lesson.format) ? c.brandText : null,
                          soft: isOnlineFormat(lesson.format) ? c.brandSoft : null,
                        ),
                        if (lesson.room != null) Tag(lesson.room!, icon: Icons.meeting_room_rounded),
                        if (substitute != null)
                          Tag(
                            'Заміна: ${substitute.fullName}',
                            icon: Icons.swap_horiz_rounded,
                            color: c.alertText,
                            soft: c.alertSoft,
                          ),
                        if (lesson.seriesId != null) const Tag('щотижня', icon: Icons.repeat_rounded),
                        if (printable.isNotEmpty)
                          Tag(
                            '$printed/${printable.length} надруковано',
                            icon: Icons.print_rounded,
                            color: printed == printable.length ? c.successText : c.alertText,
                            soft: printed == printable.length ? c.successSoft : c.alertSoft,
                          ),
                        if (admin && lesson.priceAmount != null) Tag('Ціна: ${formatMoney(lesson.priceAmount)}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SectionTitle('Учні на занятті (${roster.length})'),
            if (roster.isEmpty)
              const EmptyState(emoji: '🧒', title: 'На цьому занятті ще немає учнів')
            else
              for (final s in roster)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RosterCard(lesson: lesson, student: s, data: data, store: store),
                ),
          ],
        ),
      ),
    );
  }
}

/// Delete with the web version's series handling. Returns true if deleted.
Future<bool> deleteLessonFlow(BuildContext context, Lesson lesson) async {
  final store = context.storeRead;
  if (lesson.seriesId != null) {
    final rest = store.data.lessons
        .where((l) => l.seriesId == lesson.seriesId && l.date.compareTo(lesson.date) >= 0)
        .length;
    final choice = await confirmDialog(
      context,
      '«${lesson.theme}» — частина серії занять, що повторюється щотижня. Видалити тільки це заняття чи це і всі наступні в серії?',
      title: 'Видалити заняття',
      confirmLabel: 'Тільки це',
      extraLabel: rest > 1 ? 'Це і наступні ($rest)' : null,
    );
    if (choice == false) return false;
    if (choice == 'extra') {
      return store.online(() => store.api.deleteLessonSeries(lesson.seriesId!, lesson.date), done: 'Заняття видалено');
    }
  } else {
    final ok = await confirmDialog(context, 'Видалити заняття «${lesson.theme}»?', title: 'Видалити заняття');
    if (ok != true) return false;
  }
  return store.online(() => store.api.deleteLesson(lesson.id), done: 'Заняття видалено');
}

class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.lesson, required this.student, required this.data, required this.store});
  final Lesson lesson;
  final Student student;
  final StudioData data;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final att = data.attendance(lesson.id, student.id);
    final work = data.work(lesson.id, student.id);
    final present = att?.isPresent ?? false;
    final printsHere = lessonPrintsFor(lesson, att);
    final canHandlePrint = present && printsHere;
    final printed = work?.printed ?? false;
    final trialEligible = data.lessonsInCourse(student.id, lesson.course) <= 1;
    final admin = store.isAdmin;
    final started = lesson.date.compareTo(todayStr()) <= 0;

    void openStudent() =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentCardScreen(studentId: student.id)));

    Future<void> takePhoto() async {
      final bytes = await pickPhoto(context, title: 'Фото роботи · ${student.name}');
      if (bytes != null) await store.attachWorkPhoto(lesson, student, bytes);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(initial: student.initial, url: admin ? student.photo : null, size: 40, onTap: openStudent),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: openStudent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                        if (!admin) _statusLine(context, att),
                      ],
                    ),
                  ),
                ),
                if (trialEligible || (work?.trial ?? false))
                  _TrialPill(
                    on: work?.trial ?? false,
                    onTap: () => store.setTrial(lesson, student, !(work?.trial ?? false)),
                  ),
              ],
            ),
            if (canHandlePrint) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  WorkPhoto(work: work, size: 56, onCamera: takePhoto),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            PrintedPill(
                              printed: printed,
                              onTap: () async {
                                final completesLesson =
                                    !printed && data.printedCount(lesson) + 1 == data.printable(lesson).length;
                                HapticFeedback.selectionClick();
                                await store.setPrinted(lesson, student, !printed);
                                if (completesLesson) store.say('🎉 Усі роботи цього заняття надруковано!');
                              },
                            ),
                            if (started && work?.photo == null && work?.localPhoto == null && !printed)
                              Tag(
                                'Немає фото',
                                color: c.alertText,
                                soft: c.alertSoft,
                                icon: Icons.photo_camera_rounded,
                                onTap: takePhoto,
                              ),
                          ],
                        ),
                        if (printed && work?.printedByName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              'Статус змінив: ${work!.printedByName}',
                              style: TextStyle(color: c.inkSoft, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (!admin && courseHasPrinting(lesson.course) && started && att == null) ...[
              const SizedBox(height: 8),
              Text(
                'Фото й друк — після відмітки «П» адміністратором.',
                style: TextStyle(color: c.inkSoft, fontSize: 12.5),
              ),
            ],
            if (admin) ...[
              const SizedBox(height: 12),
              AttendanceControls(lesson: lesson, student: student, record: att, data: data, store: store),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusLine(BuildContext context, Attendance? att) {
    final c = context.c;
    if (att == null) return Text('Ще не відмічено', style: TextStyle(color: c.inkSoft, fontSize: 12.5));
    final (fg, label) = switch (att.status) {
      'present' => (c.successText, 'Присутній'),
      'absent' => (c.danger, 'Відсутній'),
      _ => (c.alertText, 'Поважна причина'),
    };
    return Text(
      label,
      style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700),
    );
  }
}

class _TrialPill extends StatelessWidget {
  const _TrialPill({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: on ? c.vr : c.vrSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'Пробне',
            style: TextStyle(color: on ? Colors.white : c.vr, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ),
      ),
    );
  }
}

/// П/Н/ВПП, payment, discount, per-child print — admin only. All the money
/// rules live in mark_attendance()/set_attendance_print() in the database;
/// this only collects the choice (see AttendanceControls in index.html).
class AttendanceControls extends StatefulWidget {
  const AttendanceControls({
    super.key,
    required this.lesson,
    required this.student,
    required this.record,
    required this.data,
    required this.store,
  });
  final Lesson lesson;
  final Student student;
  final Attendance? record;
  final StudioData data;
  final AppStore store;

  @override
  State<AttendanceControls> createState() => _AttendanceControlsState();
}

class _AttendanceControlsState extends State<AttendanceControls> {
  bool _buying = false;
  late String _purchaseDate = widget.lesson.date;
  String? _purchaseMethod;
  final _discount = TextEditingController();
  final _printPrice = TextEditingController();
  final _discountFocus = FocusNode();
  final _printFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncFields();
    _discountFocus.addListener(() {
      if (!_discountFocus.hasFocus) _applyDiscount();
    });
    _printFocus.addListener(() {
      if (!_printFocus.hasFocus) _applyPrintPrice();
    });
  }

  @override
  void didUpdateWidget(AttendanceControls old) {
    super.didUpdateWidget(old);
    if (old.record?.status != widget.record?.status) {
      _buying = false;
      _purchaseDate = widget.lesson.date;
      _purchaseMethod = null;
    }
    if (!_discountFocus.hasFocus && !_printFocus.hasFocus) _syncFields();
  }

  void _syncFields() {
    final d = widget.record?.discountPercent ?? 0;
    _discount.text = d > 0 ? _fmt(d) : '';
    final p = widget.record?.printPrice;
    _printPrice.text = p != null ? _fmt(p) : '';
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _discount.dispose();
    _printPrice.dispose();
    _discountFocus.dispose();
    _printFocus.dispose();
    super.dispose();
  }

  Attendance? get _r => widget.record;

  void _mark(String status, {String? method, double discount = 0, String? purchaseDate, String? purchaseMethod}) {
    HapticFeedback.selectionClick();
    widget.store.markAttendance(
      widget.lesson,
      widget.student,
      status,
      paymentMethod: method,
      discountPercent: discount,
      purchaseDate: purchaseDate,
      purchaseMethod: purchaseMethod,
    );
  }

  void _tapStatus(String status) {
    if (_r?.status == status) {
      HapticFeedback.selectionClick();
      widget.store.unmarkAttendance(widget.lesson, widget.student);
      return;
    }
    final present = status == 'present';
    _mark(status, method: present ? _r?.paymentMethod : null, discount: present ? (_r?.discountPercent ?? 0) : 0);
  }

  void _choosePayment(String method, Subscription? sub) {
    final startsNew = method == 'subscription' && sub == null && _r?.paymentMethod != 'subscription';
    if (startsNew) {
      setState(() => _buying = true);
      return;
    }
    setState(() => _buying = false);
    _mark('present', method: method, discount: _r?.discountPercent ?? 0);
  }

  void _applyDiscount() {
    final r = _r;
    if (r == null || !r.isPresent || r.paymentMethod == null) return;
    final n = (double.tryParse(_discount.text.replaceAll(',', '.')) ?? 0).clamp(0, 100).roundToDouble();
    if (n != r.discountPercent) {
      _mark('present', method: r.paymentMethod, discount: n);
    } else {
      _discount.text = n > 0 ? _fmt(n) : '';
    }
  }

  void _applyPrintPrice() {
    final r = _r;
    if (r == null || !r.printEnabled) return;
    final t = _printPrice.text.trim().replaceAll(',', '.');
    final next = t.isEmpty ? null : (double.tryParse(t) ?? 0).clamp(0, double.infinity).toDouble();
    if (next == r.printPrice) return;
    widget.store.setAttendancePrint(widget.lesson, widget.student, true, next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _r;
    final status = r?.status;
    final present = status == 'present';
    final unpaid = present && r?.paymentMethod == null;
    final sub = widget.data.activeSubscription(widget.student.id, widget.lesson.course);
    final online = isOnlineFormat(widget.lesson.format);
    final printDefault = defaultPrintPrice(widget.data.rateCardByCourse[widget.lesson.course]);
    final discount = r?.discountPercent ?? 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final st in attendanceStatuses) ...[
                Expanded(child: _statusButton(context, st, status == st.value, unpaid)),
                if (st != attendanceStatuses.last) const SizedBox(width: 6),
              ],
              if (r?.pending ?? false) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Очікує синхронізації',
                  child: Icon(Icons.cloud_upload_rounded, size: 18, color: c.alertText),
                ),
              ],
            ],
          ),
          if (present && online) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const _Label('Друк'),
                Switch(
                  value: r!.printEnabled,
                  onChanged: (v) => widget.store.setAttendancePrint(widget.lesson, widget.student, v, null),
                ),
                Text(r.printEnabled ? 'Друкуємо' : 'Без друку', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (r.printEnabled)
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _printPrice,
                      focusNode: _printFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _printFocus.unfocus(),
                      decoration: InputDecoration(prefixText: '+', suffixText: 'грн', hintText: _fmt(printDefault)),
                    ),
                  ),
              ],
            ),
            if (r.printEnabled && r.paymentMethod == 'subscription')
              Text('Друк входить в абонемент', style: TextStyle(color: c.inkSoft, fontSize: 12)),
          ],
          if (present) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const _Label('Оплата'),
                if (unpaid) Tag('Не оплачено', color: c.danger, soft: c.dangerSoft),
                const Spacer(),
                if (r!.paymentMethod != null && !_buying) _amount(context, r, discount),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pm in paymentMethods)
                  ChoiceChip(
                    label: Text(
                      pm.value == 'subscription' && sub != null
                          ? '${pm.label} ${sub.remainingLessons}/${sub.totalLessons}'
                          : pm.label,
                    ),
                    selected: r.paymentMethod == pm.value || (_buying && pm.value == 'subscription'),
                    onSelected: (_) => _choosePayment(pm.value, sub),
                  ),
              ],
            ),
          ],
          if (present && _buying) _purchasePanel(context),
          if (present && r!.paymentMethod != null && !_buying) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const _Label('Знижка'),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _discount,
                    focusNode: _discountFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _discountFocus.unfocus(),
                    decoration: const InputDecoration(hintText: '0', suffixText: '%'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _amount(BuildContext context, Attendance r, double discount) {
    final c = context.c;
    final base = widget.lesson.priceAmount;
    final printExtra = r.printEnabled && r.paymentMethod != 'subscription'
        ? (r.printPrice ?? defaultPrintPrice(widget.data.rateCardByCourse[widget.lesson.course]))
        : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (discount > 0 && base != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              formatMoney(base + printExtra),
              style: TextStyle(color: c.inkSoft, decoration: TextDecoration.lineThrough, fontSize: 12.5),
            ),
          ),
        Text(
          '${r.pending ? '≈ ' : ''}${formatMoney(r.amount)}',
          style: TextStyle(fontWeight: FontWeight.w800, color: c.successText),
        ),
      ],
    );
  }

  Widget _statusButton(BuildContext context, Option st, bool active, bool unpaid) {
    final c = context.c;
    final (Color fg, Color bg) = !active
        ? (c.inkSoft, c.card)
        : switch (st.value) {
            'present' => unpaid ? (Colors.white, c.alert) : (Colors.white, c.success),
            'absent' => (Colors.white, c.danger),
            _ => (Colors.white, c.alertText),
          };
    return Tooltip(
      message: active ? 'Зняти позначку' : attendanceStatusTitles[st.value]!,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: active ? bg : c.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _tapStatus(st.value),
          child: SizedBox(
            height: 42,
            child: Center(
              child: Text(
                st.label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _purchasePanel(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.brand.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Новий абонемент (4 заняття)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              const _Label('Куплено'),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: parseDate(_purchaseDate),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _purchaseDate = isoDate(picked));
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(formatDateDMY(_purchaseDate)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const _Label('Оплата'),
              Wrap(
                spacing: 6,
                children: [
                  for (final pm in subscriptionPaymentMethods)
                    ChoiceChip(
                      label: Text(pm.label),
                      selected: _purchaseMethod == pm.value,
                      onSelected: (_) => setState(() => _purchaseMethod = pm.value),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => _buying = false), child: const Text('Скасувати')),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _purchaseMethod == null
                    ? null
                    : () {
                        setState(() => _buying = false);
                        _mark(
                          'present',
                          method: 'subscription',
                          discount: _r?.discountPercent ?? 0,
                          purchaseDate: _purchaseDate,
                          purchaseMethod: _purchaseMethod,
                        );
                      },
                child: const Text('Оформити'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: Text(
      text,
      style: TextStyle(color: context.c.inkSoft, fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );
}

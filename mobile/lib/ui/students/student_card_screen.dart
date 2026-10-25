import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../desktop/windows.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../admin/parent_accounts_screen.dart';
import '../contact.dart';
import '../schedule/lesson_screen.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'student_edit_screen.dart';

/// A student's portfolio: profile, subscriptions, every lesson across the
/// studio, comments and payments (StudentCardModal in index.html).
class StudentCardScreen extends StatefulWidget {
  const StudentCardScreen({super.key, required this.studentId});
  final String studentId;

  @override
  State<StudentCardScreen> createState() => _StudentCardScreenState();
}

class _StudentCardScreenState extends State<StudentCardScreen> {
  StudentPortfolio? _portfolio;
  List<Subscription>? _subs;
  List<StudentComment>? _comments;

  /// The store's refresh the portfolio was loaded after: a newer one (a
  /// sync here, or a change made in another window) reloads it.
  DateTime? _loadedAfter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_portfolio == null) _load();
  }

  Future<void> _load() async {
    final store = context.storeRead;
    final s = store.data.studentById[widget.studentId];
    if (s == null) return;
    _loadedAfter = store.lastRefresh;
    final results = await Future.wait([
      store.portfolio(s),
      if (store.isAdmin)
        store.fetch(() => store.api.fetchSubscriptions(studentId: s.id), quiet: true)
      else
        Future.value(null),
      store.fetch(() => store.api.fetchComments(s.id), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      _portfolio = results[0] as StudentPortfolio;
      final subs = results[1] as List<Map<String, dynamic>>?;
      _subs =
          subs?.map(Subscription.new).toList() ?? store.data.subscriptions.where((x) => x.studentId == s.id).toList();
      _subs!.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
      final comments = results[2] as List<Map<String, dynamic>>?;
      _comments = comments?.map(StudentComment.new).toList() ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    if (_portfolio != null && store.lastRefresh != null && store.lastRefresh != _loadedAfter) {
      _loadedAfter = store.lastRefresh;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final s = store.data.studentById[widget.studentId];
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(emoji: '🧒', title: 'Учня не знайдено'),
      );
    }
    final admin = store.isAdmin;
    final tabs = [
      const Tab(text: 'Профіль'),
      if (admin) const Tab(text: 'Абонементи'),
      const Tab(text: 'Історія'),
      const Tab(text: 'Коментарі'),
      if (admin) const Tab(text: 'Платежі'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Картка учня'),
          actions: [
            if (AppWindows.main != null)
              IconButton(
                tooltip: 'Відкрити в окремому вікні',
                onPressed: () => AppWindows.main!.openStudent(s),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            IconButton(
              tooltip: 'Редагувати',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentEditScreen(student: s))),
              icon: const Icon(Icons.edit_rounded),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(118),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Avatar(initial: s.initial, url: admin ? s.photo : null, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(s.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(fontFamily: 'Exo2', fontWeight: FontWeight.w700, fontSize: 14),
                  tabs: tabs,
                ),
              ],
            ),
          ),
        ),
        body: _portfolio == null
            ? const LoadingView(text: 'Завантаження портфоліо…')
            : TabBarView(
                children: [
                  _ProfileTab(student: s, portfolio: _portfolio!),
                  if (admin) _SubscriptionsTab(subs: _subs ?? const [], onChanged: _load),
                  _HistoryTab(portfolio: _portfolio!),
                  _CommentsTab(student: s, server: _comments ?? const [], onAdded: _load),
                  if (admin) _PaymentsTab(portfolio: _portfolio!),
                ],
              ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.student, required this.portfolio});
  final Student student;
  final StudentPortfolio portfolio;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final courses = {for (final l in portfolio.lessons) ?l.course}.toList();
    final first = portfolio.lessons.length <= 1;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (portfolio.offline)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tag('Без інтернету: показано лише збережене на телефоні', icon: Icons.cloud_off_rounded),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.event_rounded,
                  value: '${portfolio.lessons.length}',
                  label: 'занять всього',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(icon: Icons.category_rounded, value: '${courses.length}', label: 'напрямків'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  icon: Icons.auto_awesome_rounded,
                  value: first ? 'Так' : 'Ні',
                  label: 'відвідує вперше',
                  color: first ? c.vr : c.inkSoft,
                  soft: first ? c.vrSoft : c.sand,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (student.parentsName.isNotEmpty)
                  InfoRow(
                    label: 'Батьки',
                    child: Text(student.parentsName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                if (student.phone != null)
                  InfoRow(
                    label: 'Телефон (екстрений контакт)',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student.phone!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        ContactButtons(phone: student.phone!),
                      ],
                    ),
                  ),
                if (student.birthday != null)
                  InfoRow(label: 'День народження', child: Text(formatDateDMY(student.birthday))),
                if (courses.isNotEmpty)
                  InfoRow(
                    label: 'Напрямки, які вивчає',
                    child: Wrap(spacing: 6, runSpacing: 6, children: [for (final co in courses) CourseTag(co)]),
                  ),
                if (student.notes != null) InfoRow(label: 'Нотатки', child: Text(student.notes!)),
                if (context.store.isSuperAdmin && !portfolio.offline) StudentParentAccess(student: student),
                if (student.parentsName.isEmpty && student.phone == null && student.birthday == null && courses.isEmpty)
                  Text('Контакти ще не заповнені.', style: TextStyle(color: c.inkSoft)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SubscriptionsTab extends StatelessWidget {
  const _SubscriptionsTab({required this.subs, required this.onChanged});
  final List<Subscription> subs;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final store = context.storeRead;
    final c = context.c;
    if (subs.isEmpty) {
      return ListView(
        children: const [EmptyState(emoji: '💳', title: 'Ще немає жодного абонемента')],
      );
    }

    Future<void> update(Subscription s, Map<String, dynamic> patch) async {
      if (await store.online(() => store.api.updateSubscription(s.id, patch))) onChanged();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final s in subs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Opacity(
              opacity: s.status == 'cancelled' ? 0.55 : 1,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(s.course, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          Text(
                            '${s.remainingLessons}/${s.totalLessons}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: c.brandText),
                          ),
                        ],
                      ),
                      Text(
                        [
                          s.status == 'cancelled'
                              ? 'Скасовано'
                              : (s.status == 'completed' ? 'Використано повністю' : 'Активний'),
                          if (s.totalPrice > 0) formatMoney(s.totalPrice),
                          ?optionLabel(subscriptionPaymentMethods, s.paymentMethod),
                        ].join(' · '),
                        style: TextStyle(color: c.inkSoft),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: s.purchaseDate.length == 10 ? parseDate(s.purchaseDate) : DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) update(s, {'purchased_at': '${isoDate(d)}T00:00:00Z'});
                            },
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text('Куплено ${formatDateDMY(s.purchaseDate)}'),
                          ),
                          for (final pm in subscriptionPaymentMethods)
                            ChoiceChip(
                              label: Text(pm.label),
                              selected: s.paymentMethod == pm.value,
                              onSelected: (_) =>
                                  update(s, {'payment_method': s.paymentMethod == pm.value ? null : pm.value}),
                            ),
                          if (s.paymentMethod == null) Tag('Не вказано оплату', color: c.alertText, soft: c.alertSoft),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Залишок',
                            style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w700),
                          ),
                          IconButton(
                            onPressed: s.remainingLessons <= 0
                                ? null
                                : () => update(s, {'remaining_lessons': s.remainingLessons - 1}),
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                          Text('${s.remainingLessons}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(
                            onPressed: s.remainingLessons >= s.totalLessons
                                ? null
                                : () => update(s, {
                                    'remaining_lessons': s.remainingLessons + 1,
                                    if (s.status == 'completed') 'status': 'active',
                                  }),
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => update(s, {'status': s.status == 'cancelled' ? 'active' : 'cancelled'}),
                            child: Text(s.status == 'cancelled' ? 'Відновити' : 'Скасувати'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Text(
          'Залишок можна виправити вручну, якщо сталася помилка.',
          style: TextStyle(color: c.inkSoft, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.portfolio});
  final StudentPortfolio portfolio;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final lessons = portfolio.lessons.reversed.toList();
    if (lessons.isEmpty) {
      return ListView(
        children: const [EmptyState(emoji: '📭', title: 'Ще немає жодного заняття')],
      );
    }
    final firstId = portfolio.lessons.first.id;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: lessons.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final l = lessons[i];
        final teacher = store.data.profileById[l.ownerId];
        final att = portfolio.attendanceByLesson[l.id];
        final w = portfolio.workByLesson[l.id];
        final printable = lessonPrintsFor(l, att) && (att?.isPresent ?? false);
        final known = store.data.lessonById.containsKey(l.id);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: known
                ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(lessonId: l.id)))
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DateBadge(l.date, time: l.time),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.theme, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (teacher != null) Tag(teacher.fullName, icon: Icons.person_rounded),
                            if (l.course != null) CourseTag(l.course!),
                            Tag(lessonFormatLabel(l, att)),
                            if (l.room != null) Tag(l.room!),
                            if (l.id == firstId) Tag('Перше заняття', color: c.vr, soft: c.vrSoft),
                            if (att != null)
                              Tag(
                                optionLabel(attendanceStatuses, att.status) ?? att.status,
                                color: att.isPresent ? c.successText : c.alertText,
                                soft: att.isPresent ? c.successSoft : c.alertSoft,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (printable) ...[
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        WorkPhoto(work: w, size: 44),
                        const SizedBox(height: 4),
                        Icon(Icons.print_rounded, size: 16, color: (w?.printed ?? false) ? c.successText : c.alertText),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommentsTab extends StatefulWidget {
  const _CommentsTab({required this.student, required this.server, required this.onAdded});
  final Student student;
  final List<StudentComment> server;
  final VoidCallback onAdded;

  @override
  State<_CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends State<_CommentsTab> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final known = widget.server.map((x) => x.id).toSet();
    final comments = [
      ...store.pendingComments(widget.student.id).where((x) => !known.contains(x.id)),
      ...widget.server,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _draft,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Додати коментар про учня…'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _draft.text.trim().isEmpty
                ? null
                : () async {
                    final body = _draft.text.trim();
                    _draft.clear();
                    setState(() {});
                    await store.addComment(widget.student.id, body);
                  },
            child: const Text('Додати'),
          ),
        ),
        const SizedBox(height: 8),
        if (comments.isEmpty)
          const EmptyState(emoji: '💬', title: 'Ще немає коментарів')
        else
          for (final cm in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              store.data.profileById[cm.authorId]?.fullName ?? 'Невідомо',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (cm.pending) Icon(Icons.cloud_upload_rounded, size: 16, color: c.alertText),
                          if (cm.createdAt.length >= 10)
                            Text(
                              formatDateDMY(_localDate(cm.createdAt)),
                              style: TextStyle(color: c.inkSoft, fontSize: 12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(cm.body),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  static String _localDate(String ts) {
    final t = DateTime.tryParse(ts);
    return t == null ? ts.substring(0, 10) : isoDate(t.toLocal());
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.portfolio});
  final StudentPortfolio portfolio;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lessonById = {for (final l in portfolio.lessons) l.id: l};
    final payments = portfolio.attendanceByLesson.values.where((a) => a.paymentMethod != null).toList()
      ..sort((a, b) => (lessonById[b.lessonId]?.sortKey ?? '').compareTo(lessonById[a.lessonId]?.sortKey ?? ''));
    final total = payments.fold<double>(0, (sum, p) => sum + p.amount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatTile(
          icon: Icons.payments_rounded,
          value: formatMoney(total),
          label: 'сплачено всього',
          color: c.successText,
          soft: c.successSoft,
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          const EmptyState(emoji: '💰', title: 'Ще немає жодної оплати')
        else
          for (final p in payments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (lessonById[p.lessonId] != null) ...[
                        DateBadge(lessonById[p.lessonId]!.date),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lessonById[p.lessonId]?.theme ?? 'Заняття видалено',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                Tag(optionLabel(paymentMethods, p.paymentMethod) ?? '${p.paymentMethod}'),
                                if (p.discountPercent > 0) Tag('−${p.discountPercent.round()}%'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(p.amount),
                        style: TextStyle(fontWeight: FontWeight.w800, color: c.successText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

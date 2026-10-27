import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../../util/text.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Parents' portal accounts (superadmin; ParentAccountsTab in index.html,
/// sql/0018). An account is a phone number and a generated password; the
/// children it sees are linked here by hand. Parents sign in on the
/// portal site or in the phone app — never here.
class ParentAccountsScreen extends StatefulWidget {
  const ParentAccountsScreen({super.key});

  @override
  State<ParentAccountsScreen> createState() => ParentAccountsScreenState();
}

class ParentAccountsScreenState extends State<ParentAccountsScreen> {
  final _query = TextEditingController();
  List<ParentAccount> _accounts = [];
  Map<String, List<String>> _links = {};
  bool _loading = true;
  bool _started = false;
  String? _busy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.storeRead;
    final res = await store.fetch(
      () => Future.wait<List<DbRow>>([store.api.fetchParentAccounts(), store.api.fetchParentLinks()]),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) return;
      _accounts = res[0].map(ParentAccount.new).toList();
      _links = {};
      for (final l in res[1]) {
        _links.putIfAbsent(l['parent_id'] as String, () => []).add(l['student_id'] as String);
      }
    });
  }

  /// "Новий кабінет" (also from the menu bar on the Mac).
  Future<void> create() => _edit(null);

  Future<void> _edit(ParentAccount? account) async {
    final result = await showDialog<_Saved>(
      context: context,
      builder: (_) => _AccountDialog(account: account, linked: account == null ? const [] : _links[account.id] ?? []),
    );
    if (!mounted || result == null) return;
    if (result.password != null) await showParentPasswordDialog(context, result.password!);
    _load();
  }

  Future<void> _resetPassword(ParentAccount a) async {
    final store = context.storeRead;
    final ok = await confirmDialog(
      context,
      'Згенерувати новий пароль для ${formatParentPhone(a.phone)}? Старий перестане працювати, а батьків буде '
      'розлогінено на всіх пристроях.',
      title: 'Новий пароль',
      confirmLabel: 'Згенерувати',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = a.id);
    DbRow? res;
    await store.online(() async => res = await store.api.parentRpc('parent_reset_password', {'p_parent_id': a.id}));
    if (!mounted) return;
    setState(() => _busy = null);
    if (res != null) await showParentPasswordDialog(context, res!);
    _load();
  }

  Future<void> _toggleActive(ParentAccount a) async {
    final store = context.storeRead;
    setState(() => _busy = a.id);
    await store.online(
      () => store.api.setParentAccountActive(a.id, !a.active),
      done: a.active ? 'Доступ вимкнено' : 'Доступ увімкнено',
      reload: false,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    _load();
  }

  Future<void> _delete(ParentAccount a) async {
    final store = context.storeRead;
    final ok = await confirmDialog(
      context,
      'Видалити кабінет ${formatParentPhone(a.phone)}? Батьки більше не зможуть увійти. Дані учнів не зміняться.',
      title: 'Видалити кабінет',
    );
    if (ok != true) return;
    await store.online(() => store.api.deleteParentAccount(a.id), done: 'Кабінет видалено', reload: false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final studentById = store.data.studentById;
    final q = _query.text.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    String kidsOf(ParentAccount a) =>
        [for (final id in _links[a.id] ?? const <String>[]) ?studentById[id]?.name].join(', ');
    final list = q.isEmpty
        ? _accounts
        : _accounts
              .where(
                (a) =>
                    (a.name ?? '').toLowerCase().contains(q) ||
                    kidsOf(a).toLowerCase().contains(q) ||
                    (qDigits.length >= 3 && a.phone.contains(qDigits)),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Кабінети батьків'), actions: const [SyncButton()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новий кабінет', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const LoadingView(text: 'Завантаження кабінетів батьків…')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text('Вхід для батьків: ', style: TextStyle(color: c.inkSoft)),
                        Flexible(
                          child: InkWell(
                            onTap: () => launchUrl(Uri.parse(parentPortalUrl), mode: LaunchMode.externalApplication),
                            child: Text(
                              parentPortalUrl.replaceFirst('https://', ''),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.brandText, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_accounts.isEmpty)
                    const EmptyState(
                      emoji: '👨‍👩‍👧',
                      title: 'Ще немає жодного кабінету',
                      subtitle: 'Створіть кабінет тут або натисніть «Згенерувати пароль» у картці учня.',
                    )
                  else ...[
                    TextField(
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Пошук за телефоном, батьками, дитиною…',
                        suffixIcon: q.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => setState(_query.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final a in list) _row(a, kidsOf(a)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _row(ParentAccount a, String kids) {
    final c = context.c;
    final busy = _busy == a.id;
    final meta = a.lastLoginAt != null
        ? 'вхід ${formatDateDMY(a.lastLoginAt!.substring(0, 10))}'
        : (a.passwordSetAt != null ? 'ще не входили' : 'без пароля');
    return Opacity(
      opacity: a.active ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _edit(a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.vrSoft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.favorite_rounded, color: c.vr, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                a.name ?? formatParentPhone(a.phone),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (!a.active) ...[
                              const SizedBox(width: 6),
                              Tag('Вимкнено', color: c.danger, soft: c.dangerSoft),
                            ],
                          ],
                        ),
                        Text(
                          '${formatParentPhone(a.phone)} · ${kids.isEmpty ? 'діти не обрані' : kids}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                        ),
                        Text(meta, style: TextStyle(color: c.inkSoft, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Згенерувати новий пароль',
                    onPressed: busy ? null : () => _resetPassword(a),
                    icon: const Icon(Icons.key_rounded),
                  ),
                  IconButton(
                    tooltip: a.active ? 'Вимкнути доступ' : 'Увімкнути доступ',
                    onPressed: busy ? null : () => _toggleActive(a),
                    icon: Icon(a.active ? Icons.block_rounded : Icons.restart_alt_rounded),
                  ),
                  IconButton(
                    tooltip: 'Видалити кабінет',
                    onPressed: busy ? null : () => _delete(a),
                    icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the account dialog did: [password] is set when one was created.
class _Saved {
  const _Saved(this.password);
  final DbRow? password;
}

/// New account or an existing one's phone, name and children
/// (ParentAccountModal on the web).
class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.account, required this.linked});
  final ParentAccount? account;
  final List<String> linked;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _phone = TextEditingController(text: formatParentPhone(widget.account?.phone));
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  final _query = TextEditingController();
  late final Set<String> _selected = {...widget.linked};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.storeRead;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return setState(() => _error = 'Вкажіть номер телефону');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final a = widget.account;
      if (a == null) {
        final res = await store.api.parentRpc('parent_create_account', {
          'p_phone': _phone.text,
          'p_name': _name.text,
          'p_student_ids': _selected.toList(),
        });
        if (mounted) Navigator.pop(context, _Saved({...res, 'created': true}));
        return;
      }
      await store.api.saveParentAccount(
        a.id,
        phone: _phone.text,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        linkStudents: _selected.where((id) => !widget.linked.contains(id)).toList(),
        unlinkStudents: widget.linked.where((id) => !_selected.contains(id)).toList(),
      );
      store.say('Збережено');
      if (mounted) Navigator.pop(context, const _Saved(null));
    } on ServerRejected catch (e) {
      setState(() {
        _saving = false;
        _error = e.message.contains('duplicate key') ? 'Кабінет з таким номером уже існує' : e.message;
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = "Немає з'єднання з сервером. Ця дія потребує інтернету.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final q = _query.text.trim().toLowerCase();
    final tail = _phone.text.replaceAll(RegExp(r'\D'), '');
    final tail9 = tail.length >= 9 ? tail.substring(tail.length - 9) : '';
    bool samePhone(Student s) => tail9.isNotEmpty && (s.phone ?? '').replaceAll(RegExp(r'\D'), '').endsWith(tail9);
    // Likely siblings (the same phone in their card) come first.
    final matches =
        store.data.students
            .where(
              (s) =>
                  q.isEmpty ||
                  [
                    s.name,
                    s.phone,
                    s.parentLastName,
                    s.parentFirstName,
                  ].whereType<String>().join(' ').toLowerCase().contains(q),
            )
            .toList()
          ..sort((a, b) {
            int rank(Student s) => (_selected.contains(s.id) ? 2 : 0) + (samePhone(s) ? 1 : 0);
            final r = rank(b) - rank(a);
            return r != 0 ? r : ukCompare(a.name, b.name);
          });

    return AlertDialog(
      title: Text(
        widget.account == null ? 'Новий кабінет батьків' : 'Кабінет батьків',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      autofocus: widget.account == null,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Телефон (логін)', hintText: '+380 67 123 45 67'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: "Ім'я батьків", hintText: 'Коваль Ірина'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text('Діти в кабінеті', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text('${_selected.length} обрано', style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Пошук учня…'),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in matches.take(40))
                        PickChip(
                          label: Text(s.name),
                          avatar: CircleAvatar(
                            backgroundColor: _selected.contains(s.id) ? Colors.white24 : c.brandSoft,
                            child: Text(
                              s.initial,
                              style: TextStyle(
                                fontSize: 11,
                                color: _selected.contains(s.id) ? Colors.white : c.brandText,
                              ),
                            ),
                          ),
                          tooltip: s.phone,
                          selected: _selected.contains(s.id),
                          onSelected: (on) => setState(() => on ? _selected.add(s.id) : _selected.remove(s.id)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Першими показано учнів з цим самим телефоном у картці. Батьки бачать лише позначених тут дітей.',
                style: TextStyle(color: c.inkSoft, fontSize: 12.5),
              ),
              if (widget.account == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "Після створення з'явиться пароль — його треба одразу передати батькам.",
                    style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Збереження…'
                : widget.account == null
                ? 'Створити й отримати пароль'
                : 'Зберегти',
          ),
        ),
      ],
    );
  }
}

/// The new password and a ready message for the parents (ParentPasswordModal).
/// [result] is what parent_create_account / parent_reset_password /
/// parent_password_for_student returned.
Future<void> showParentPasswordDialog(BuildContext context, DbRow result) {
  final phone = result['phone'] as String? ?? '';
  final password = result['password'] as String? ?? '';
  final created = result['created'] == true;
  final message = parentPasswordMessage(phone, password);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final c = ctx.c;
      void copy(String text, String what) {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$what скопійовано'), width: 360));
      }

      return AlertDialog(
        title: Text(
          created ? 'Кабінет батьків створено' : 'Новий пароль батьків',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Логін — номер ${formatParentPhone(phone)}. '
                '${created ? 'Старого пароля не було.' : 'Старий пароль більше не діє, а всі входи на інших пристроях скинуто.'}',
                style: TextStyle(color: c.inkSoft),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: c.sand, borderRadius: BorderRadius.circular(14)),
                      child: SelectableText(
                        password,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Скопіювати пароль',
                    onPressed: () => copy(password, 'Пароль'),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Повідомлення для батьків', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: c.lineStrong),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(message),
              ),
              const SizedBox(height: 8),
              Text(
                'Пароль ніде не зберігається у відкритому вигляді — передайте його зараз (Viber, Telegram, SMS). '
                'Увійти можна на сайті або в застосунку Stemik → «Батьки».',
                style: TextStyle(color: c.inkSoft, fontSize: 12.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => copy(message, 'Повідомлення'),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Скопіювати повідомлення'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
        ],
      );
    },
  );
}

/// In a student's card, superadmin only: which parent accounts see this
/// child, and "Згенерувати пароль" (creates the account for the phone in
/// the card if there is none; StudentParentAccess on the web).
class StudentParentAccess extends StatefulWidget {
  const StudentParentAccess({super.key, required this.student});
  final Student student;

  @override
  State<StudentParentAccess> createState() => _StudentParentAccessState();
}

class _StudentParentAccessState extends State<StudentParentAccess> {
  List<ParentAccount>? _accounts;
  bool _busy = false;
  bool _started = false;

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
    final res = await store.fetch(
      () => Future.wait<List<DbRow>>([store.api.fetchParentAccounts(), store.api.fetchParentLinks()]),
      quiet: true,
    );
    if (!mounted || res == null) return;
    final mine = {
      for (final l in res[1])
        if (l['student_id'] == widget.student.id) l['parent_id'],
    };
    setState(() => _accounts = res[0].map(ParentAccount.new).where((a) => mine.contains(a.id)).toList());
  }

  Future<void> _generate(ParentAccount? account) async {
    final store = context.storeRead;
    final target = formatParentPhone(account?.phone ?? widget.student.phone);
    final ok = await confirmDialog(
      context,
      account != null || _accounts!.isNotEmpty
          ? 'Згенерувати новий пароль для $target? Старий перестане працювати.'
          : 'Створити кабінет батьків для $target і згенерувати пароль?',
      title: 'Кабінет батьків',
      confirmLabel: 'Згенерувати',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    DbRow? res;
    await store.online(
      () async => res = account != null
          ? await store.api.parentRpc('parent_reset_password', {'p_parent_id': account.id})
          : await store.api.parentRpc('parent_password_for_student', {'p_student_id': widget.student.id}),
      reload: false,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) await showParentPasswordDialog(context, res!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    if (accounts == null) return const SizedBox.shrink();
    final c = context.c;
    final digits = (widget.student.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final tail = digits.length >= 9 ? digits.substring(digits.length - 9) : '';
    final ownPhone = accounts.any((a) => tail.isNotEmpty && a.phone.endsWith(tail));
    return InfoRow(
      label: 'Кабінет батьків',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.favorite_rounded, size: 14, color: c.vr),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [formatParentPhone(a.phone), ?a.name, if (!a.active) 'вимкнено'].join(' · '),
                      style: TextStyle(color: c.inkSoft),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _generate(a),
                    icon: const Icon(Icons.key_rounded, size: 16),
                    label: const Text('Новий пароль'),
                  ),
                ],
              ),
            ),
          if (!ownPhone) ...[
            OutlinedButton.icon(
              onPressed: _busy || tail.isEmpty ? null : () => _generate(null),
              icon: const Icon(Icons.key_rounded, size: 16),
              label: Text('Згенерувати пароль${tail.isEmpty ? '' : ' для ${formatParentPhone(widget.student.phone)}'}'),
            ),
            const SizedBox(height: 4),
            Text(
              tail.isEmpty
                  ? 'Додайте в картку телефон батьків — він стане логіном.'
                  : 'Логін — телефон з картки. Якщо кабінету ще немає, його буде створено; братів і сестер додайте '
                        'в розділі «Кабінети батьків».',
              style: TextStyle(color: c.inkSoft, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

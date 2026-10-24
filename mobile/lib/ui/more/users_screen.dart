import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile_screen.dart';

/// Teachers and admins (AdminUserList in index.html).
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key, required this.onOpenSchedule});
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final users = store.data.profiles.where((p) => p.id != store.me.id).toList()
      ..sort((a, b) {
        const order = {'superadmin': 0, 'admin': 1, 'teacher': 2};
        final r = (order[a.role] ?? 3) - (order[b.role] ?? 3);
        return r != 0 ? r : a.fullName.compareTo(b.fullName);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Викладачі')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createTeacher(context),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Новий викладач', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: users.isEmpty
            ? ListView(
                children: const [EmptyState(emoji: '👩‍🏫', title: 'Більше нікого немає')],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: users.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = users[i];
                  final lessons = store.data.lessons.where((l) => l.ownerId == t.id);
                  final pending = store.data.queue(lessons, includePrinted: false).length;
                  return Opacity(
                    opacity: t.active ? 1 : 0.55,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _actions(context, t),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Avatar(initial: t.initials, url: t.photo, size: 44),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.fullName,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                    ),
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _roleTag(context, t.role),
                                        if (!t.active) Tag('Неактивний', color: c.danger, soft: c.dangerSoft),
                                        Tag('${lessons.length} занять · $pending в черзі'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.more_vert_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _roleTag(BuildContext context, String role) {
    final c = context.c;
    return Tag(
      roleLabels[role] ?? 'Викладач',
      color: role == 'superadmin' ? c.vr : (role == 'admin' ? c.brandText : c.successText),
      soft: role == 'superadmin' ? c.vrSoft : (role == 'admin' ? c.brandSoft : c.successSoft),
    );
  }

  void _actions(BuildContext context, Profile t) {
    final store = context.storeRead;
    final locked = t.role == 'superadmin' && !store.isSuperAdmin;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Avatar(initial: t.initials, url: t.photo, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(t.email ?? '', style: TextStyle(color: ctx.c.inkSoft)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Розклад, черга й зарплата викладача'),
              onTap: () {
                Navigator.pop(ctx);
                store.teacherFilter = t.id;
                Navigator.of(context).popUntil((r) => r.isFirst);
                onOpenSchedule();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Редагувати профіль'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(target: t)));
              },
            ),
            if (!locked) ...[
              ListTile(
                leading: const Icon(Icons.badge_rounded),
                title: const Text('Змінити роль'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeRole(context, t);
                },
              ),
              if (t.active)
                ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('Скинути пароль'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _resetPassword(context, t);
                  },
                ),
              ListTile(
                leading: Icon(t.active ? Icons.person_off_rounded : Icons.person_rounded),
                title: Text(t.active ? 'Деактивувати (звільнити)' : 'Активувати'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleActive(context, t);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, Profile t) async {
    final store = context.storeRead;
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Роль', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (final r in ['teacher', 'admin', if (store.isSuperAdmin) 'superadmin'])
            ListTile(
              leading: Icon(r == t.role ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
              title: Text(roleLabels[r]!),
              onTap: () => Navigator.pop(ctx, r),
            ),
        ],
      ),
    );
    if (role == null || role == t.role || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      'Призначити ${t.fullName} роль «${roleLabels[role]}»?',
      title: 'Змінити роль',
      confirmLabel: 'Так, змінити',
      destructive: false,
    );
    if (ok != true) return;
    await store.online(() => store.api.updateProfile(t.id, {'role': role}), done: 'Тепер роль: ${roleLabels[role]}');
  }

  Future<void> _toggleActive(BuildContext context, Profile t) async {
    final store = context.storeRead;
    final ok = await confirmDialog(
      context,
      t.active
          ? 'Деактивувати ${t.fullName}? Викладач більше не зможе увійти, але вся історія занять, учнів і зарплати збережеться.'
          : 'Відновити доступ для ${t.fullName}?',
      title: t.active ? 'Деактивувати викладача' : 'Активувати викладача',
      confirmLabel: t.active ? 'Деактивувати' : 'Активувати',
      destructive: t.active,
    );
    if (ok != true) return;
    await store.online(
      () => store.api.updateProfile(t.id, {'active': !t.active}),
      done: t.active ? 'Обліковий запис деактивовано' : 'Обліковий запис активовано',
    );
  }

  Future<void> _resetPassword(BuildContext context, Profile t) async {
    final store = context.storeRead;
    final ok = await confirmDialog(
      context,
      'Згенерувати новий пароль для ${t.fullName}? Старий пароль перестане працювати одразу.',
      title: 'Скинути пароль',
      confirmLabel: 'Скинути',
    );
    if (ok != true) return;
    final res = await store.fetch(() => store.api.callFunction('reset-password', {'user_id': t.id}));
    final password = res?['password'] as String?;
    if (password == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новий пароль створено', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Для ${t.fullName} (${t.email}) згенеровано новий пароль. Старий більше не діє.'),
            const SizedBox(height: 14),
            SelectableText(
              password,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Передайте пароль особисто — він більше ніде не зберігається.',
              style: TextStyle(color: ctx.c.inkSoft, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: password));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопійовано')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Копіювати'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
        ],
      ),
    );
  }

  Future<void> _createTeacher(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _CreateTeacherScreen()));
  }
}

class _CreateTeacherScreen extends StatefulWidget {
  const _CreateTeacherScreen();

  @override
  State<_CreateTeacherScreen> createState() => _CreateTeacherScreenState();
}

class _CreateTeacherScreenState extends State<_CreateTeacherScreen> {
  final _last = TextEditingController();
  final _first = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_last, _first, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.storeRead;
    if (_last.text.trim().isEmpty || _first.text.trim().isEmpty) {
      return setState(() => _error = "Вкажіть прізвище та ім'я");
    }
    if (_email.text.trim().isEmpty) return setState(() => _error = 'Вкажіть email');
    if (_password.text.length < 6) return setState(() => _error = 'Пароль має містити щонайменше 6 символів');
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await store.online(
      () => store.api.callFunction('create-teacher', {
        'email': _email.text.trim(),
        'password': _password.text,
        'last_name': _last.text.trim(),
        'first_name': _first.text.trim(),
      }),
      done: 'Акаунт викладача створено',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: const Text('Новий викладач')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Створення…' : 'Створити')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
              ),
            ),
          TextField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Прізвище'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: "Ім'я"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'Тимчасовий пароль',
              helperText: 'Передайте його викладачу — змінити можна в «Мій профіль».',
            ),
          ),
        ],
      ),
    );
  }
}

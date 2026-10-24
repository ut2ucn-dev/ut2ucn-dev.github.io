import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/photos.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Own profile (with password change), or — for an admin — a teacher's.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.target});
  final Profile target;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _last = TextEditingController(text: widget.target.lastName);
  late final _first = TextEditingController(text: widget.target.firstName);
  late String? _photo = widget.target.photo;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _uploading = false;
  bool _saving = false;
  bool _savingPw = false;
  String? _pwError;

  @override
  void dispose() {
    for (final c in [_last, _first, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isMe => widget.target.id == context.storeRead.me.id;

  Future<void> _pickPhoto() async {
    final store = context.storeRead;
    final bytes = await pickPhoto(context, title: 'Фото профілю');
    if (bytes == null) return;
    setState(() => _uploading = true);
    final url = await store.fetch(
      () => store.api.uploadPhoto('teacher-photos', '${widget.target.id}/avatar.jpg', bytes),
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) _photo = url;
    });
  }

  Future<void> _save() async {
    final store = context.storeRead;
    final patch = {'last_name': _last.text.trim(), 'first_name': _first.text.trim(), 'photo': _photo};
    setState(() => _saving = true);
    final ok = await store.online(() => store.api.updateProfile(widget.target.id, patch), done: 'Профіль збережено');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      if (_isMe) store.updateMe(store.me.copyWith(patch));
      Navigator.pop(context);
    }
  }

  Future<void> _changePassword() async {
    final store = context.storeRead;
    setState(() => _pwError = null);
    if (_pw.text.length < 6) return setState(() => _pwError = 'Пароль має містити щонайменше 6 символів');
    if (_pw.text != _pw2.text) return setState(() => _pwError = 'Паролі не збігаються');
    setState(() => _savingPw = true);
    final ok = await store.online(() => store.api.updatePassword(_pw.text), done: 'Пароль оновлено', reload: false);
    if (!mounted) return;
    setState(() => _savingPw = false);
    if (ok) {
      _pw.clear();
      _pw2.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = widget.target;
    return Scaffold(
      appBar: AppBar(title: Text(_isMe ? 'Мій профіль' : 'Профіль викладача')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _uploading
                  ? const SizedBox.square(dimension: 72, child: Center(child: CircularProgressIndicator()))
                  : Avatar(initial: t.initials, url: _photo, size: 72),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickPhoto,
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(_photo == null ? 'Додати фото' : 'Замінити фото'),
              ),
            ],
          ),
          const SizedBox(height: 18),
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
            controller: TextEditingController(text: t.email ?? ''),
            enabled: false,
            decoration: const InputDecoration(labelText: 'Email', helperText: 'Email не можна змінити тут.'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Збереження…' : 'Зберегти')),
          if (_isMe) ...[
            const SectionTitle('Змінити пароль'),
            if (_pwError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _pwError!,
                  style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
                ),
              ),
            TextField(
              controller: _pw,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Новий пароль', hintText: 'Щонайменше 6 символів'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pw2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Повторіть пароль'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _savingPw ? null : _changePassword,
              child: Text(_savingPw ? 'Зберігаємо…' : 'Оновити пароль'),
            ),
          ],
        ],
      ),
    );
  }
}

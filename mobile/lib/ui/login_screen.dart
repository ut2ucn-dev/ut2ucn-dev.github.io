import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart' show ServerRejected, StemikApi;
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});
  final StemikApi api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _forgot = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email.text.isEmpty) _email.text = SettingsScope.read(context).lastEmail ?? '';
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });
    if (email.isEmpty || (!_forgot && _password.text.isEmpty)) {
      setState(() => _error = _forgot ? 'Вкажіть email' : 'Заповніть email і пароль');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_forgot) {
        await widget.api.sendPasswordReset(email);
        setState(
          () => _info = 'Якщо такий email зареєстровано, на нього надіслано лист із посиланням для скидання пароля.',
        );
      } else {
        await widget.api.signIn(email, _password.text);
        if (mounted) SettingsScope.read(context).lastEmail = email;
      }
    } on ServerRejected catch (e) {
      setState(() => _error = e.message.contains('Invalid login') ? 'Невірний email або пароль' : e.message);
    } catch (_) {
      setState(() => _error = "Немає з'єднання з інтернетом");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: StemikMark(size: 72)),
                    const SizedBox(height: 16),
                    const Text(
                      'Stemik',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Освітня студія VR · AI · 3D',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) _banner(_error!, c.danger, c.dangerSoft, Icons.error_outline_rounded),
                    if (_info != null)
                      _banner(_info!, c.successText, c.successSoft, Icons.check_circle_outline_rounded),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      textInputAction: _forgot ? TextInputAction.done : TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      onSubmitted: (_) => _forgot ? _submit() : null,
                    ),
                    if (!_forgot) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                            icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Зачекайте…'
                            : _forgot
                            ? 'Надіслати посилання для скидання'
                            : 'Увійти',
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => setState(() {
                        _forgot = !_forgot;
                        _error = null;
                        _info = null;
                      }),
                      child: Text(_forgot ? '← Повернутися до входу' : 'Забули пароль?'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Акаунт викладача створює адміністратор студії.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.inkSoft, fontSize: 13),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () =>
                              launchUrl(Uri.parse('https://stemik.studio'), mode: LaunchMode.externalApplication),
                          child: const Text('stemik.studio'),
                        ),
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse('https://www.instagram.com/stemik.studio/'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Instagram'),
                        ),
                      ],
                    ),
                    Text(
                      'м. Київ, вул. Михайла Максимовича, 3Г',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.inkSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color fg, Color bg, IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

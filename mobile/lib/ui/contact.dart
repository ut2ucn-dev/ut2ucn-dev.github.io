import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../util/text.dart';
import 'theme.dart';

/// Call / Viber / Telegram buttons for a parent's phone number.
class ContactButtons extends StatelessWidget {
  const ContactButtons({super.key, required this.phone, this.compact = false, this.only});
  final String phone;
  final bool compact;

  /// Subset of 'call', 'viber', 'telegram' to show (all when null).
  final List<String>? only;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Немає застосунку, щоб відкрити це')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final digits = phoneDigits(phone);
    final intl = digits.startsWith('+') ? digits : (digits.startsWith('0') ? '+38$digits' : '+$digits');
    final buttons = [
      ('call', Icons.call_rounded, 'Дзвінок', c.successText, c.successSoft, Uri(scheme: 'tel', path: digits)),
      (
        'viber',
        Icons.chat_rounded,
        'Viber',
        c.vr,
        c.vrSoft,
        Uri.parse('viber://chat?number=${Uri.encodeComponent(intl)}'),
      ),
      ('telegram', Icons.send_rounded, 'Telegram', c.brandText, c.brandSoft, Uri.parse('https://t.me/$intl')),
    ].where((b) => only == null || only!.contains(b.$1));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (_, icon, label, fg, bg, uri) in buttons)
          Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _open(context, uri),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 7 : 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: fg),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void showContactsSheet(BuildContext context, List<Student> students) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final c = ctx.c;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              const Text('Екстрені контакти', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final s in students)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      Text(
                        s.parentsName.isEmpty ? 'Без батьків у картці' : s.parentsName,
                        style: TextStyle(color: c.inkSoft),
                      ),
                      const SizedBox(height: 6),
                      if (s.phone != null) ...[
                        Text(s.phone!, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ContactButtons(phone: s.phone!),
                      ] else
                        Text('Немає телефону', style: TextStyle(color: c.inkSoft)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

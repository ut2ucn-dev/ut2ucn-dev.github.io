import 'package:flutter/material.dart';

import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final store = context.store;
    final reminders = RemindersScope.of(context);
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: const Text('Нагадування і тема')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('Нагадування про заняття'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.remindersEnabled,
                  onChanged: (v) async {
                    settings.remindersEnabled = v;
                    if (v) await reminders.requestPermission();
                  },
                  title: const Text('Нагадувати перед заняттям', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Працює без інтернету — за розкладом на телефоні'),
                ),
                if (settings.remindersEnabled) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('За скільки хвилин', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final m in const [5, 10, 15, 30, 60])
                              ChoiceChip(
                                label: Text(m == 60 ? '1 год' : '$m хв'),
                                selected: settings.reminderLead == m,
                                onSelected: (_) => settings.reminderLead = m,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    value: settings.dailyDigest,
                    onChanged: (v) => settings.dailyDigest = v,
                    title: const Text('План на день зранку', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('О 8:00 — скільки занять сьогодні і о котрій'),
                  ),
                  if (store.isAdmin) ...[
                    const Divider(),
                    SwitchListTile(
                      value: settings.remindAllStudio,
                      onChanged: (v) => settings.remindAllStudio = v,
                      title: const Text('Про всі заняття студії', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Інакше — лише про ваші власні'),
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.notifications_rounded, color: c.brandText),
                    title: const Text('Надіслати тестове сповіщення', style: TextStyle(fontWeight: FontWeight.w600)),
                    onTap: reminders.showTest,
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('Тема'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Як у системі')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Світла')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Темна')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.themeMode = s.first,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

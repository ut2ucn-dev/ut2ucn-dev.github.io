import 'package:flutter/material.dart';

import '../../services/updates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile_screen.dart';
import 'rates_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'users_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.onSignOut, required this.onOpenSchedule});
  final Future<void> Function() onSignOut;

  /// Switch to the schedule tab (after picking a teacher in the list).
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final me = store.me;

    Widget tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Color? color}) => ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (color ?? c.brandText).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: color ?? c.brandText, size: 21),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );

    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(title: const Text('Ще'), actions: const [SyncButton()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => push(ProfileScreen(target: me)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Avatar(initial: me.initials, url: me.photo, size: 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me.fullName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Tag(
                            roleLabels[me.role] ?? 'Викладач',
                            color: me.isSuperAdmin ? c.vr : (me.isAdmin ? c.brandText : c.successText),
                            soft: me.isSuperAdmin ? c.vrSoft : (me.isAdmin ? c.brandSoft : c.successSoft),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
          if (store.isAdmin) ...[
            const SectionTitle('Адміністрування'),
            Card(
              child: Column(
                children: [
                  tile(
                    Icons.groups_rounded,
                    'Викладачі',
                    subtitle: 'Ролі, доступ, паролі, розклад викладача',
                    onTap: () => push(UsersScreen(onOpenSchedule: onOpenSchedule)),
                  ),
                  if (store.isSuperAdmin) ...[
                    const Divider(indent: 70),
                    tile(
                      Icons.price_change_rounded,
                      'Тарифи',
                      subtitle: 'ЗП, ціни, абонементи',
                      onTap: () => push(const RatesScreen()),
                    ),
                    const Divider(indent: 70),
                    tile(
                      Icons.insights_rounded,
                      'Звіт студії',
                      subtitle: 'Оплачено, борги, невикористане',
                      onTap: () => push(const ReportScreen()),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SectionTitle('Застосунок'),
          Card(
            child: Column(
              children: [
                tile(
                  Icons.notifications_active_rounded,
                  'Нагадування і тема',
                  onTap: () => push(const SettingsScreen()),
                ),
                const Divider(indent: 70),
                tile(
                  Icons.sync_rounded,
                  'Синхронізація',
                  subtitle: store.pendingCount > 0
                      ? 'Очікують надсилання: ${store.pendingCount}'
                      : 'Усі зміни надіслано',
                  onTap: () => showSyncSheet(context),
                ),
                const Divider(indent: 70),
                tile(
                  Icons.system_update_rounded,
                  'Перевірити оновлення',
                  onTap: () => checkForUpdate(context, manual: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: c.danger),
            onPressed: () async {
              if (store.pendingCount > 0) {
                final ok = await confirmDialog(
                  context,
                  'Є ${store.pendingCount} змін, які ще не надіслано на сервер. Якщо вийти зараз, вони пропадуть.',
                  title: 'Вийти з акаунта?',
                  confirmLabel: 'Вийти',
                );
                if (ok != true) return;
              }
              await onSignOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Вийти'),
          ),
          const SizedBox(height: 16),
          FutureBuilder(
            future: appVersion(),
            builder: (context, snap) => Text(
              'Stemik ${snap.data ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

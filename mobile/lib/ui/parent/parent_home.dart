import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/parent_portal.dart';
import '../../util/dates.dart';
import '../../util/domain.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// The parents' portal: the same screens as client/index.html on the web.
/// Opens from the last saved copy, then refreshes from the server.
class ParentHome extends StatefulWidget {
  const ParentHome({super.key, required this.api});
  final ParentApi api;

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  ParentPortal? _portal;
  bool _offline = false;
  String? _error;
  int _tab = 0;
  String? _childId;

  @override
  void initState() {
    super.initState();
    final settings = SettingsScope.read(context);
    final cached = settings.cachedParentPortal;
    if (cached != null) _portal = ParentPortal(cached);
    _childId = settings.parentChildId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final settings = SettingsScope.read(context);
    final token = settings.parentToken;
    if (token == null) return;
    try {
      final portal = await widget.api.fetchPortal(token);
      settings.saveParentPortal(portal.raw);
      if (mounted) {
        setState(() {
          _portal = portal;
          _offline = false;
          _error = null;
        });
      }
    } on ParentSessionExpired catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      settings.setParentToken(null);
    } catch (e) {
      if (mounted) setState(() => _offline = true);
    }
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      'Вийти з кабінету батьків на цьому телефоні?',
      title: 'Вихід',
      confirmLabel: 'Вийти',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final settings = SettingsScope.read(context);
    final token = settings.parentToken;
    settings.setParentToken(null);
    if (token != null) widget.api.logout(token).catchError((_) {});
  }

  void _toggleTheme() {
    final settings = SettingsScope.read(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    settings.themeMode = dark ? ThemeMode.light : ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    final portal = _portal;
    if (portal == null) {
      return Scaffold(
        body: _offline
            ? EmptyState(
                emoji: '📡',
                title: "Немає з'єднання",
                subtitle: _error ?? 'Перевірте інтернет і потягніть, щоб оновити.',
              )
            : const LoadingView(),
        floatingActionButton: _offline
            ? FloatingActionButton.extended(
                onPressed: () {
                  setState(() => _offline = false);
                  _load();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Спробувати ще'),
              )
            : null,
      );
    }
    final students = portal.students;
    final student = students.where((s) => s.id == _childId).firstOrNull ?? students.firstOrNull;
    final summary = student == null ? null : PortalSummary(student, portal.today);

    final pages = summary == null
        ? null
        : [
            _OverviewPage(summary: summary, portal: portal, onGo: (i) => setState(() => _tab = i)),
            _ModelsPage(summary: summary),
            _PaymentsPage(summary: summary, portal: portal),
            _LessonsPage(summary: summary, today: portal.today),
          ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const StemikMark(size: 34),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stemik', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text('КАБІНЕТ БАТЬКІВ', style: TextStyle(fontSize: 9.5, letterSpacing: 0.6, color: context.c.inkSoft)),
              ],
            ),
          ],
        ),
        actions: [
          if (_offline)
            IconButton(
              tooltip: 'Немає зв\'язку — показано збережені дані',
              onPressed: _load,
              icon: Icon(Icons.cloud_off_rounded, color: context.c.alertText),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) {
              if (v == 'theme') _toggleTheme();
              if (v == 'site') launchUrl(Uri.parse('https://stemik.studio'), mode: LaunchMode.externalApplication);
              if (v == 'logout') _signOut();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  [portal.parentName, _formatPhone(portal.parentPhone)].whereType<String>().join('\n'),
                  style: TextStyle(color: ctx.c.ink, fontWeight: FontWeight.w700),
                ),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: ListTile(leading: Icon(Icons.brightness_6_rounded), title: Text('Світла / темна тема')),
              ),
              const PopupMenuItem(
                value: 'site',
                child: ListTile(leading: Icon(Icons.public_rounded), title: Text('stemik.studio')),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Вийти')),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (students.length > 1)
              SliverToBoxAdapter(
                child: _KidSwitcher(
                  students: students,
                  selectedId: student?.id,
                  onSelect: (id) {
                    SettingsScope.read(context).parentChildId = id;
                    setState(() => _childId = id);
                  },
                ),
              ),
            if (summary == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  emoji: '👋',
                  title: 'Дітей ще не додано',
                  subtitle: 'Зверніться до адміністратора студії, щоб додати дитину до кабінету.',
                ),
              )
            else ...[
              if (_tab == 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _Hero(summary: summary, parentName: portal.parentName),
                  ),
                ),
              pages![_tab],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: summary == null
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'Огляд',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: summary.models.isNotEmpty,
                    label: Text('${summary.models.length}'),
                    child: const Icon(Icons.view_in_ar_outlined),
                  ),
                  selectedIcon: const Icon(Icons.view_in_ar_rounded),
                  label: 'Моделі',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: summary.unpaid.isNotEmpty,
                    label: Text('${summary.unpaid.length}'),
                    child: const Icon(Icons.account_balance_wallet_outlined),
                  ),
                  selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
                  label: 'Оплати',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note_rounded),
                  label: 'Заняття',
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

const _violet = Color(0xFF8B5CF6);
const _heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF5CA7C9), Color(0xFF5B4FE0)],
);

String _formatPhone(String phone) {
  final m = RegExp(r'^380(\d{2})(\d{3})(\d{2})(\d{2})$').firstMatch(phone);
  return m == null ? phone : '+380 ${m[1]} ${m[2]} ${m[3]} ${m[4]}';
}

String _plural(int n, String one, String few, String many) {
  final a = n.abs() % 100, b = a % 10;
  if (a > 10 && a < 20) return many;
  if (b > 1 && b < 5) return few;
  if (b == 1) return one;
  return many;
}

String _shortDate(String d) {
  final dt = parseDate(d);
  return '${dt.day} ${months[dt.month - 1]}';
}

String _fullDate(String d) {
  final dt = parseDate(d);
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

String _courseEmoji(String? course) {
  switch (courseTrack(course)) {
    case CourseTrack.threeD:
      return '🧊';
    case CourseTrack.vr:
      return '🥽';
    case CourseTrack.robo:
      return '🤖';
    case CourseTrack.other:
      return '✨';
  }
}

const _paymentLabels = {
  'card': 'Оплачено карткою',
  'cash': 'Оплачено готівкою',
  'subscription': 'За абонементом',
  'certificate': 'Сертифікат',
};

({String label, Color fg, Color bg}) _stateLook(BuildContext context, PortalLesson l, String today) {
  final c = context.c;
  switch (l.state(today)) {
    case LessonState.upcoming:
      return (label: 'Заплановано', fg: c.brandText, bg: c.brandSoft);
    case LessonState.unmarked:
      return (label: 'Очікує відмітки', fg: c.inkSoft, bg: c.sand);
    case LessonState.absent:
      return (label: 'Пропуск', fg: c.inkSoft, bg: c.sand);
    case LessonState.excused:
      return (label: 'Пропуск (поважна)', fg: c.inkSoft, bg: c.sand);
    case LessonState.paid:
      final cert = l.paymentMethod == 'certificate';
      return (
        label: _paymentLabels[l.paymentMethod] ?? 'Оплачено',
        fg: cert ? c.alertText : c.successText,
        bg: cert ? c.alertSoft : c.successSoft,
      );
    case LessonState.unpaid:
      return (label: 'Не сплачено', fg: c.danger, bg: c.dangerSoft);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.fg, required this.bg});
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.emoji, required this.title, required this.children, this.trailing});
  final String emoji;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 19)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

SliverPadding _list(List<Widget> children) => SliverPadding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  sliver: SliverList.separated(
    itemCount: children.length,
    itemBuilder: (_, i) => children[i],
    separatorBuilder: (_, _) => const SizedBox(height: 12),
  ),
);

// ---------------------------------------------------------------------------
// Header: child switcher and the gradient hero card
// ---------------------------------------------------------------------------

class _KidSwitcher extends StatelessWidget {
  const _KidSwitcher({required this.students, required this.selectedId, required this.onSelect});
  final List<PortalStudent> students;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        itemCount: students.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = students[i];
          final active = s.id == selectedId;
          return Tooltip(
            message: s.name,
            child: Material(
              color: active ? c.brand : c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: active ? c.brand : c.line, width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(s.id),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(5, 5, active ? 12 : 5, 5),
                  child: Row(
                    children: [
                      _KidPhoto(student: s, size: 34, onBrand: active),
                      // Only the selected child is named, to keep the row short.
                      if (active) ...[
                        const SizedBox(width: 8),
                        Text(
                          s.name.split(' ').first,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KidPhoto extends StatelessWidget {
  const _KidPhoto({required this.student, required this.size, this.onBrand = false});
  final PortalStudent student;
  final double size;
  final bool onBrand;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.32),
      gradient: onBrand ? null : _heroGradient,
      color: onBrand ? Colors.white.withValues(alpha: 0.22) : null,
    ),
    child: student.photo != null
        ? CachedNetworkImage(imageUrl: student.photo!, fit: BoxFit.cover, width: size, height: size)
        : Text(
            student.initial,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42),
          ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.summary, required this.parentName});
  final PortalSummary summary;
  final String? parentName;

  static const _gold = Color(0xFFFFD36E);

  @override
  Widget build(BuildContext context) {
    final s = summary.student;
    final level = summary.level;
    final greeting = parentName == null ? 'Вітаємо!' : 'Привіт, ${parentName!.split(' ').last}!';
    final attended = summary.attended.length;
    final models = summary.models.length;
    final left = summary.lessonsLeftInSubscriptions;
    Widget num(int v, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$v',
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 3,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05263F), Color(0xFF0B3558)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF05263F).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -80, top: -90, child: _glow(const Color(0xFF2B5C86), 240)),
          Positioned(left: -90, bottom: -110, child: _glow(const Color(0xFF5B4FE0), 240)),
          const Positioned(right: 4, top: 4, child: WavingRobot(width: 84, onDark: true)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 80),
                  child: Row(
                    children: [
                      _KidPhoto(student: s, size: 46),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              greeting,
                              style: const TextStyle(
                                color: Color(0xFFBFE3F3),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 80),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              gradient: const LinearGradient(colors: [_gold, Color(0xFFF5A524)]),
                            ),
                            child: Text(
                              '${level.number}',
                              style: const TextStyle(
                                color: Color(0xFF05263F),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Рівень ${level.number} · ${level.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            '${attended * 10} XP',
                            style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: SizedBox(
                          height: 7,
                          child: Stack(
                            children: [
                              Container(color: Colors.white.withValues(alpha: 0.12)),
                              FractionallySizedBox(
                                widthFactor: level.progress.clamp(0.04, 1.0),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [Color(0xFF5CA7C9), Color(0xFF8B80FF), _gold]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      num(attended, _plural(attended, 'заняття відвідано', 'заняття відвідано', 'занять відвідано')),
                      const SizedBox(width: 8),
                      num(models, _plural(models, 'модель створено', 'моделі створено', 'моделей створено')),
                      const SizedBox(width: 8),
                      num(left, 'залишок занять в абонементах'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _glow(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)]),
    ),
  );
}

String _daysUntil(String date, String today) {
  final n = parseDate(date).difference(parseDate(today)).inDays;
  if (n <= 0) return 'сьогодні';
  if (n == 1) return 'завтра';
  return 'через $n ${_plural(n, 'день', 'дні', 'днів')}';
}

class _AchievementsCard extends StatefulWidget {
  const _AchievementsCard({required this.summary});
  final PortalSummary summary;

  @override
  State<_AchievementsCard> createState() => _AchievementsCardState();
}

class _AchievementsCardState extends State<_AchievementsCard> {
  bool _all = false;

  Widget _medal(BuildContext context, Achievement a, {required bool wide}) {
    final c = context.c;
    return Container(
      width: wide ? null : 108,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Stack(
        children: [
          if (a.unlocked)
            Positioned(right: 0, top: 0, child: Icon(Icons.check_circle_rounded, size: 17, color: c.success)),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Opacity(
                  opacity: a.unlocked ? 1 : 0.45,
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: a.unlocked ? null : c.line,
                      gradient: a.unlocked
                          ? const RadialGradient(
                              center: Alignment(-0.4, -0.4),
                              colors: [Colors.white, Color(0xFFFFE7A8), Color(0xFFF5A524)],
                            )
                          : null,
                      boxShadow: a.unlocked
                          ? [BoxShadow(color: const Color(0xFFF5A524).withValues(alpha: 0.35), blurRadius: 10)]
                          : null,
                    ),
                    child: Text(a.emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                a.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: a.unlocked ? c.ink : c.inkSoft),
              ),
              if (wide)
                Text(
                  a.description,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.inkSoft, fontSize: 11, height: 1.25),
                ),
              if (!a.unlocked && a.need > 1) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: a.have / a.need,
                    minHeight: 4,
                    backgroundColor: c.line,
                    color: c.brand,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${a.have} / ${a.need}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkSoft, fontSize: 10.5),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.summary.achievements;
    final got = list.where((a) => a.unlocked).length;
    // Unlocked first in the strip, so the row opens on what the child has.
    final strip = [...list.where((a) => a.unlocked), ...list.where((a) => !a.unlocked)];
    return _SectionCard(
      emoji: '🏆',
      title: 'Досягнення · $got з ${list.length}',
      trailing: TextButton(
        onPressed: () => setState(() => _all = !_all),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        child: Text(_all ? 'Згорнути' : 'Усі'),
      ),
      children: [
        if (_all)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
            children: [for (final a in list) _medal(context, a, wide: true)],
          )
        else
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: strip.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _medal(context, strip[i], wide: false),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.summary, required this.portal, required this.onGo});
  final PortalSummary summary;
  final ParentPortal portal;

  /// Switches the bottom-bar tab (2 = payments, 3 = lessons).
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final next = summary.upcoming.firstOrNull;
    final more = summary.upcoming.length - 1;
    final subs = summary.activeSubscriptions;
    return _list([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: next == null
              ? Text('📅 Нових занять поки не заплановано', style: TextStyle(color: c.inkSoft))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.course(next.course).soft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(_courseEmoji(next.course), style: const TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: 'НАСТУПНЕ ЗАНЯТТЯ · ',
                                  children: [
                                    TextSpan(
                                      text: _daysUntil(next.date, summary.today).toUpperCase(),
                                      style: TextStyle(color: c.brandText),
                                    ),
                                  ],
                                ),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.inkSoft,
                                ),
                              ),
                              Text(
                                '${weekdayName(parseDate(next.date))}, ${_shortDate(next.date)}'
                                '${next.time != null ? ' о ${next.time}' : ''}',
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                [next.course, next.theme].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: c.inkSoft),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (more > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton(
                          onPressed: () => onGo(3),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size.zero,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Ще $more ${_plural(more, 'заплановане', 'заплановані', 'запланованих')}'),
                              const Icon(Icons.chevron_right_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      if (summary.due > 0)
        _BalanceCard(summary: summary, portal: portal)
      else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: c.success,
                child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'Усе сплачено — дякуємо!',
                style: TextStyle(color: c.successText, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      if (subs.isNotEmpty)
        _SectionCard(
          emoji: '🎟️',
          title: 'Абонементи',
          trailing: TextButton(
            onPressed: () => onGo(2),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Деталі'),
          ),
          children: [
            for (final sub in subs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sub.course.ifEmpty('Абонемент'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: sub.totalLessons == 0 ? 0 : sub.remainingLessons / sub.totalLessons,
                          minHeight: 6,
                          backgroundColor: c.line,
                          color: c.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${sub.remainingLessons} з ${sub.totalLessons}',
                      style: TextStyle(color: c.brandText, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      _AchievementsCard(summary: summary),
    ]);
  }
}

Widget _muted(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: context.c.inkSoft),
  ),
);

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary, required this.portal});
  final PortalSummary summary;
  final ParentPortal portal;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final owes = summary.due > 0;
    final n = summary.unpaid.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [owes ? c.alertSoft : c.successSoft, c.card],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            owes ? 'До сплати' : 'Заборгованості немає',
            style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          const SizedBox(height: 2),
          Text(
            owes ? formatMoney(summary.due) : '✓ 0 грн',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: owes ? c.alertText : c.successText),
          ),
          Text(
            owes
                ? '$n ${_plural(n, 'заняття', 'заняття', 'занять')} ще не сплачено'
                : 'Усі відвідані заняття сплачені. Дякуємо!',
            style: TextStyle(color: c.inkSoft, fontSize: 13),
          ),
          const SizedBox(height: 14),
          _PayButton(enabled: portal.paymentsEnabled),
        ],
      ),
    );
  }
}

/// Online payment: in place, but off until a payment provider is chosen
/// (parent_portal() reports payments_enabled = false until then).
class _PayButton extends StatelessWidget {
  const _PayButton({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        onPressed: enabled ? () {} : null,
        icon: const Icon(Icons.credit_card_rounded, size: 18),
        label: const Text('Оплатити онлайн'),
      ),
      if (!enabled) _Pill('В РОЗРОБЦІ', fg: _violet, bg: _violet.withValues(alpha: 0.13)),
    ],
  );
}

class _CoursesCard extends StatelessWidget {
  const _CoursesCard({required this.summary});
  final PortalSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _SectionCard(
      emoji: '🚀',
      title: 'Курси',
      children: summary.courses.isEmpty
          ? [_muted(context, 'Ще немає занять')]
          : [
              for (final p in summary.courses)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.course(p.course).soft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(_courseEmoji(p.course), style: const TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.course, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                            Text(
                              '${p.attended} з ${p.total} ${_plural(p.total, 'заняття', 'занять', 'занять')}'
                              ' · з ${_shortDate(p.first)}',
                              style: TextStyle(color: c.inkSoft, fontSize: 12),
                            ),
                            const SizedBox(height: 7),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: p.total == 0 ? 0 : p.attended / p.total,
                                minHeight: 6,
                                backgroundColor: c.line,
                                color: c.brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (p.next != null) ...[
                        const SizedBox(width: 10),
                        _Pill(_shortDate(p.next!.date), fg: c.brandText, bg: c.brandSoft),
                      ],
                    ],
                  ),
                ),
            ],
    );
  }
}

Widget? _specialsCard(BuildContext context, PortalSummary summary) {
  if (summary.certificates.isEmpty && summary.trials.isEmpty) return null;
  final c = context.c;
  Widget badge(String emoji, String title, String sub, Color tint) => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(colors: [tint.withValues(alpha: 0.18), tint.withValues(alpha: 0.04)]),
    ),
    child: Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(sub, style: TextStyle(color: c.inkSoft, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
  final certs = summary.certificates.length;
  return _SectionCard(
    emoji: '🎁',
    title: 'Сертифікати та пробні заняття',
    children: [
      if (summary.trials.isNotEmpty)
        badge(
          '🌟',
          'Пробне заняття',
          summary.trials.map((l) => '${_fullDate(l.date)}${l.course != null ? ' · ${l.course}' : ''}').join(', '),
          _violet,
        ),
      if (certs > 0)
        badge(
          '🎁',
          'Сертифікат · $certs ${_plural(certs, 'заняття', 'заняття', 'занять')}',
          summary.certificates.map((l) => _shortDate(l.date)).join(', '),
          c.alert,
        ),
    ],
  );
}

/// Course, theme, date and state; format, room and teacher show on tap.
class _LessonRow extends StatefulWidget {
  const _LessonRow({required this.lesson, required this.today});
  final PortalLesson lesson;
  final String today;

  @override
  State<_LessonRow> createState() => _LessonRowState();
}

class _LessonRowState extends State<_LessonRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = widget.lesson;
    final look = _stateLook(context, l, widget.today);
    final st = l.state(widget.today);
    final money = st == LessonState.unpaid
        ? l.due
        : st == LessonState.paid && l.paymentMethod != 'subscription'
        ? l.amount
        : null;
    final details = [
      formatLabel(l.format),
      l.room,
      if (l.teacher != null) 'викладач ${l.teacher}',
    ].whereType<String>().join(' · ');
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DateBadge(l.date, time: l.time),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [l.course, l.theme].whereType<String>().join(' · ').ifEmpty('Заняття'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  if (_open) ...[
                    const SizedBox(height: 2),
                    Text(details, style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Pill(look.label, fg: look.fg, bg: look.bg),
                      if (l.trial) _Pill('Пробне', fg: _violet, bg: _violet.withValues(alpha: 0.13)),
                      if (money != null && money > 0)
                        Text(
                          formatMoney(money),
                          style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: c.inkSoft),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _ModelsPage extends StatelessWidget {
  const _ModelsPage({required this.summary});
  final PortalSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.models.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          emoji: '🧊',
          title: 'Моделей ще немає',
          subtitle: "Моделі з'являться тут після занять, на яких діти створюють і друкують свої роботи.",
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: summary.models.length,
        itemBuilder: (context, i) => _ModelCard(work: summary.models[i]),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.work});
  final PortalWork work;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = work;
    final placeholder = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(colors: [c.brandSoft, _violet.withValues(alpha: 0.13)])),
      child: Text(_courseEmoji(w.course), style: const TextStyle(fontSize: 40)),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: w.photo == null ? null : () => showPhoto(context, CachedNetworkImageProvider(w.photo!)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  w.photo == null
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: w.photo!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => placeholder,
                          placeholder: (_, _) => placeholder,
                        ),
                  if (w.trial)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _Pill('Пробне', fg: Colors.white, bg: _violet.withValues(alpha: 0.85)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.theme ?? 'Модель',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  Text(_fullDate(w.date), style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
                  const SizedBox(height: 6),
                  if (w.prints)
                    w.printed
                        ? _Pill('🖨️ Надруковано', fg: c.successText, bg: c.successSoft)
                        : _Pill('⏳ Чекає на друк', fg: c.alertText, bg: c.alertSoft)
                  else
                    _Pill(w.course ?? 'Робота', fg: c.inkSoft, bg: c.sand),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

class _PaymentsPage extends StatelessWidget {
  const _PaymentsPage({required this.summary, required this.portal});
  final PortalSummary summary;
  final ParentPortal portal;

  @override
  Widget build(BuildContext context) {
    final subs = summary.student.subscriptions;
    return _list([
      _BalanceCard(summary: summary, portal: portal),
      _SectionCard(
        emoji: '🎟️',
        title: 'Абонементи',
        children: subs.isEmpty
            ? [_muted(context, 'Абонементів ще не було. Абонемент на 4 заняття вигідніший за разову оплату.')]
            : [for (final s in subs) _SubscriptionRow(sub: s)],
      ),
      ?_specialsCard(context, summary),
      if (summary.unpaid.isNotEmpty)
        _SectionCard(
          emoji: '🧾',
          title: 'Не сплачені заняття',
          children: [for (final l in summary.unpaid) _LessonRow(lesson: l, today: portal.today)],
        ),
    ]);
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.sub});
  final PortalSubscription sub;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = sub;
    final used = s.totalLessons - s.remainingLessons;
    final state = s.status == 'cancelled'
        ? _Pill('Скасовано', fg: c.inkSoft, bg: c.sand)
        : s.remainingLessons > 0
        ? _Pill('Активний', fg: c.successText, bg: c.successSoft)
        : _Pill('Використано', fg: c.inkSoft, bg: c.sand);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          _Ring(value: s.remainingLessons, total: s.totalLessons),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.course.ifEmpty('Абонемент'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text(
                  'Придбано ${_fullDate(s.purchaseDate)}${s.totalPrice > 0 ? ' · ${formatMoney(s.totalPrice)}' : ''}',
                  style: TextStyle(color: c.inkSoft, fontSize: 12),
                ),
                Text(
                  'Використано $used з ${s.totalLessons} · залишилось ${s.remainingLessons}',
                  style: TextStyle(color: c.inkSoft, fontSize: 12),
                ),
                const SizedBox(height: 6),
                state,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lessons left in a subscription, as a ring.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.total});
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox.square(
      dimension: 58,
      child: CustomPaint(
        painter: _RingPainter(total > 0 ? (value / total).clamp(0.0, 1.0) : 0, c.line),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1)),
              Text(
                'з $total',
                style: TextStyle(fontSize: 9.5, color: c.inkSoft, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.track);
  final double fraction;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(5);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = track;
    canvas.drawArc(inner, 0, math.pi * 2, false, base);
    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(colors: [Color(0xFF5B4FE0), Color(0xFFA855F7)]).createShader(rect);
    canvas.drawArc(inner, -math.pi / 2, math.pi * 2 * fraction, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.track != track;
}

// ---------------------------------------------------------------------------
// Lessons
// ---------------------------------------------------------------------------

class _LessonsPage extends StatefulWidget {
  const _LessonsPage({required this.summary, required this.today});
  final PortalSummary summary;
  final String today;

  @override
  State<_LessonsPage> createState() => _LessonsPageState();
}

class _LessonsPageState extends State<_LessonsPage> {
  String _filter = 'all';

  static const _filters = [
    ('all', 'Усі'),
    ('unpaid', 'Не сплачені'),
    ('paid', 'Сплачені'),
    ('upcoming', 'Майбутні'),
    ('absent', 'Пропуски'),
  ];

  bool _matches(PortalLesson l) {
    final s = l.state(widget.today);
    switch (_filter) {
      case 'unpaid':
        return s == LessonState.unpaid;
      case 'paid':
        return s == LessonState.paid;
      case 'upcoming':
        return s == LessonState.upcoming;
      case 'absent':
        return s == LessonState.absent || s == LessonState.excused;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.summary.lessons.where(_matches).toList();
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(child: _CoursesCard(summary: widget.summary)),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              children: [
                for (final (key, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: PickChip(
                      label: Text(label),
                      selected: _filter == key,
                      onSelected: (_) => setState(() => _filter = key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(emoji: '🗓️', title: 'Тут поки порожньо'),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(),
                        _LessonRow(lesson: list[i], today: widget.today),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

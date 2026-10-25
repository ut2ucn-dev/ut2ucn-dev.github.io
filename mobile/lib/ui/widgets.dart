import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../util/dates.dart';
import 'scope.dart';
import 'theme.dart';

/// The studio's robot logo (assets/brand), in the artwork for the current
/// theme. [onDark] always uses the light-on-dark artwork.
class StemikMark extends StatelessWidget {
  const StemikMark({super.key, this.size = 40, this.onDark = false});
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      'assets/brand/robot-${dark ? 'dark' : 'light'}.png',
      width: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Stemik',
    );
  }
}

/// The logo robot waving hello: body and arm are separate images and the
/// arm swings from the shoulder, as on the web (`.waver` in client/).
class WavingRobot extends StatefulWidget {
  const WavingRobot({super.key, this.width = 150, this.onDark = false});
  final double width;
  final bool onDark;

  @override
  State<WavingRobot> createState() => _WavingRobotState();
}

class _WavingRobotState extends State<WavingRobot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Stands still when the system asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  // (time, degrees) — the same keyframes as @keyframes wave on the web.
  static const _keys = [
    (0.0, 0.0),
    (0.08, -9.0),
    (0.16, 8.0),
    (0.24, -9.0),
    (0.32, 7.0),
    (0.40, -5.0),
    (0.48, 2.0),
    (0.58, 0.0),
    (1.0, 0.0),
  ];

  static double _angle(double t) {
    for (var i = 1; i < _keys.length; i++) {
      final (t1, a1) = _keys[i];
      if (t <= t1) {
        final (t0, a0) = _keys[i - 1];
        final f = Curves.easeInOut.transform((t - t0) / (t1 - t0));
        return (a0 + (a1 - a0) * f) * math.pi / 180;
      }
    }
    return 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.onDark || Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
    return Semantics(
      label: 'Робот Stemik махає рукою',
      child: SizedBox(
        width: widget.width,
        child: Stack(
          children: [
            Image.asset('assets/brand/wave-$t-base.png', width: widget.width, filterQuality: FilterQuality.medium),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => Transform.rotate(
                  angle: _angle(_c.value),
                  alignment: const FractionalOffset(0.34, 0.75),
                  child: child,
                ),
                child: Image.asset('assets/brand/wave-$t-hand.png', filterQuality: FilterQuality.medium),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initial, this.url, this.size = 40, this.onTap});
  final String initial;
  final String? url;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final child = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(size * 0.34)),
      alignment: Alignment.center,
      child: url != null
          ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, width: size, height: size)
          : Text(
              initial,
              style: TextStyle(color: c.brandText, fontWeight: FontWeight.w800, fontSize: size * 0.4),
            ),
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

/// Small rounded label, as .tag / .course-tag / .format-tag on the web.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.soft, this.icon, this.onTap});
  final String text;
  final Color? color;
  final Color? soft;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = color ?? c.sandText;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: soft ?? c.sand, borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
            ),
          ),
        ],
      ),
    );
    return onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(9), onTap: onTap, child: body);
  }
}

class CourseTag extends StatelessWidget {
  const CourseTag(this.course, {super.key});
  final String course;
  @override
  Widget build(BuildContext context) {
    final a = context.c.course(course);
    return Tag(course, color: a.color, soft: a.soft);
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.soft,
    this.onTap,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final Color? soft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = color ?? c.brandText;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: soft ?? c.brandSoft, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.inkSoft, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, this.subtitle});
  final String emoji;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// The calendar-page date badge (.datecard).
class DateBadge extends StatelessWidget {
  const DateBadge(this.date, {super.key, this.time});
  final String date;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = parseDate(date);
    return Container(
      width: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: c.brand,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              months[d.month - 1].substring(0, 3),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              children: [
                Text('${d.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.1)),
                Text(
                  weekdayShort(d),
                  style: TextStyle(fontSize: 10, color: c.inkSoft, fontWeight: FontWeight.w700),
                ),
                if (time != null)
                  Text(
                    time!,
                    style: TextStyle(fontSize: 10, color: c.brandText, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Надруковано / Не надруковано" toggle (.printed-pill).
class PrintedPill extends StatelessWidget {
  const PrintedPill({
    super.key,
    required this.printed,
    this.onTap,
    this.labelOn = 'Надруковано',
    this.labelOff = 'Не надруковано',
    this.icon = Icons.print_rounded,
  });
  final bool printed;
  final VoidCallback? onTap;
  final String labelOn;
  final String labelOff;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = printed ? c.successText : c.alertText;
    return Material(
      color: printed ? c.successSoft : c.alertSoft,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(printed ? Icons.check_rounded : icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(
                printed ? labelOn : labelOff,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A work's photo: the uploaded one, or the one waiting to upload, or a
/// camera button. Tap a photo to see it full screen.
class WorkPhoto extends StatelessWidget {
  const WorkPhoto({super.key, required this.work, this.size = 52, this.onCamera});
  final Work? work;
  final double size;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.storeRead;
    final local = store.localPhoto(work);
    final url = work?.photo;
    final ImageProvider? image = local ?? (url != null ? CachedNetworkImageProvider(url) : null);
    final radius = BorderRadius.circular(size * 0.26);

    if (image == null) {
      return Material(
        color: c.brandSoft,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onCamera,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              Icons.add_a_photo_rounded,
              size: size * 0.42,
              color: onCamera == null ? c.inkSoft : c.brandText,
            ),
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => showPhoto(context, image),
              child: ClipRRect(
                borderRadius: radius,
                child: Image(image: image, fit: BoxFit.cover),
              ),
            ),
          ),
          if (local != null)
            Positioned(
              left: 3,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
                child: Icon(Icons.cloud_upload_rounded, size: 12, color: c.alertText),
              ),
            ),
          if (onCamera != null)
            Positioned(
              right: -5,
              bottom: -5,
              child: Material(
                color: c.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onCamera,
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.photo_camera_rounded, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void showPhoto(BuildContext context, ImageProvider image) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (ctx, _, _) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(maxScale: 5, child: Image(image: image)),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.white24),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Cloud icon in the app bar: synced / changes waiting / offline.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final pending = store.pendingCount;
    final offline = store.connection == Connection.offline;
    final IconData icon;
    final Color color;
    if (store.refreshing) {
      icon = Icons.sync_rounded;
      color = c.brandText;
    } else if (offline) {
      icon = Icons.cloud_off_rounded;
      color = c.alertText;
    } else if (pending > 0) {
      icon = Icons.cloud_upload_rounded;
      color = c.alertText;
    } else {
      icon = Icons.cloud_done_rounded;
      color = c.successText;
    }
    return IconButton(
      tooltip: 'Синхронізація',
      onPressed: () => showSyncSheet(context),
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text('$pending'),
        backgroundColor: c.alert,
        child: store.refreshing
            ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: color))
            : Icon(icon, color: color),
      ),
    );
  }
}

void showSyncSheet(BuildContext context) {
  showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => const _SyncSheet());
}

class _SyncSheet extends StatelessWidget {
  const _SyncSheet();

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final offline = store.connection == Connection.offline;
    final ops = store.pendingOps;
    String when(DateTime? t) {
      if (t == null) return 'ще не оновлювалось';
      final m = DateTime.now().difference(t).inMinutes;
      if (m < 1) return 'щойно';
      if (m < 60) return '$m хв тому';
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}, ${t.day}.${t.month.toString().padLeft(2, '0')}';
    }

    final cached = store.cachedAt == null ? null : DateTime.tryParse(store.cachedAt!);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Text('Синхронізація', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _line(
              context,
              offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
              offline ? 'Немає з\'єднання — працюємо з даними на телефоні' : 'Підключено до сервера',
              offline ? c.alertText : c.successText,
            ),
            _line(context, Icons.update_rounded, 'Дані оновлено: ${when(store.lastRefresh ?? cached)}', c.inkSoft),
            if (store.live)
              _line(
                context,
                Icons.bolt_rounded,
                "Наживо: зміни інших (сайт, телефони, інші адміни) з'являються самі",
                c.successText,
              ),
            _line(
              context,
              ops.isEmpty ? Icons.check_circle_rounded : Icons.schedule_send_rounded,
              ops.isEmpty ? 'Усі зміни надіслано' : 'Очікують надсилання: ${ops.length}',
              ops.isEmpty ? c.successText : c.alertText,
            ),
            if (ops.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final op in ops.take(20))
                Padding(
                  padding: const EdgeInsets.only(left: 34, bottom: 4),
                  child: Text('• ${op.describe()}', style: TextStyle(color: c.inkSoft)),
                ),
              if (ops.length > 20)
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: Text('…і ще ${ops.length - 20}', style: TextStyle(color: c.inkSoft)),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 4),
                child: Text(
                  'Надішлються самі, щойно з\'явиться інтернет.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                ),
              ),
            ],
            if (store.rejected.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Сервер відхилив',
                style: TextStyle(fontWeight: FontWeight.w800, color: c.danger),
              ),
              const SizedBox(height: 4),
              for (final r in store.rejected.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $r', style: TextStyle(color: c.inkSoft)),
                ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: store.refreshing ? null : () => store.sync(),
              icon: const Icon(Icons.sync_rounded),
              label: Text(store.refreshing ? 'Синхронізація…' : 'Синхронізувати зараз'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// Yes/no (or yes/extra/no) dialog, as confirmDialog() in index.html.
/// Returns true, false, or 'extra'.
Future<Object> confirmDialog(
  BuildContext context,
  String message, {
  String title = 'Підтвердження',
  String confirmLabel = 'Видалити',
  String? extraLabel,
  bool destructive = true,
}) async {
  final c = context.c;
  final res = await showDialog<Object>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(message),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
        if (extraLabel != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.pop(ctx, 'extra'),
            child: Text(extraLabel),
          ),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: c.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w800, color: context.c.inkSoft),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Label/value row used on detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.c.inkSoft, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        child,
      ],
    ),
  );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.text = 'Завантаження…'});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 14),
        Text(text, style: TextStyle(color: context.c.inkSoft)),
      ],
    ),
  );
}

/// [text] with the parts that match [tokens] in [hi].
TextSpan highlight(String text, List<String> tokens, TextStyle base, TextStyle hi) {
  final lower = text.toLowerCase();
  final marks = List.filled(text.length, false);
  for (final t in tokens) {
    if (t.isEmpty) continue;
    final i = lower.indexOf(t);
    if (i < 0) continue;
    for (var j = i; j < i + t.length && j < marks.length; j++) {
      marks[j] = true;
    }
  }
  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || marks[i] != marks[start]) {
      spans.add(TextSpan(text: text.substring(start, i), style: marks[start] ? hi : base));
      start = i;
    }
  }
  return TextSpan(children: spans, style: base);
}

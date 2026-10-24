import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The launch intro: the robot from the native splash screen (same size,
/// same place, same navy — see android/.../launch_background.xml and
/// ios/Runner/Base.lproj/LaunchScreen.storyboard) hops, switches its visor
/// to a pair of eyes, winks, waves, and the app fades in underneath.
///
/// The app builds and loads behind the intro the whole time, so it adds no
/// waiting of its own. A tap skips to the fade-out; under the system's
/// "reduce motion" setting the intro is not shown at all.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.child});
  final Widget child;

  static const navy = Color(0xFF05263F);

  /// Width of the robot artwork; the native splash draws it at 150dp.
  static const robotWidth = 150.0;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

// Timeline, in milliseconds.
const _total = 2600.0;
const _exitAt = 2150.0;

class _LaunchIntroState extends State<LaunchIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
  bool _done = false;
  bool _started = false;

  static const _images = [
    'assets/brand/intro-base.png',
    'assets/brand/intro-brain.png',
    'assets/brand/wave-dark-hand.png',
    'assets/brand/wordmark-dark.png',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _done = true;
      return;
    }
    // Keep the native splash up until the artwork is decoded, so the robot
    // never blinks out between the splash and the first frame — but never
    // for longer than a moment.
    final binding = WidgetsBinding.instance..deferFirstFrame();
    Future.any([
      Future.wait([for (final a in _images) precacheImage(AssetImage(a), context)]),
      Future<void>.delayed(const Duration(milliseconds: 600)),
    ]).whenComplete(() {
      binding.allowFirstFrame();
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value * _total < _exitAt) _c.forward(from: _exitAt / _total);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _IntroFrame(ms: _c.value * _total),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// 0 → 1 over [from, from + length] milliseconds.
double _phase(double ms, double from, double length) => _clamp01((ms - from) / length);

/// Arm swing in degrees for wave progress [t] (0..1): four swings that die
/// down, like the web's @keyframes wave but quicker.
double _waveDegrees(double t) {
  const keys = [(0.0, 0.0), (0.12, -14.0), (0.3, 12.0), (0.48, -14.0), (0.66, 10.0), (0.84, -6.0), (1.0, 0.0)];
  for (var i = 1; i < keys.length; i++) {
    final (t1, a1) = keys[i];
    if (t <= t1) {
      final (t0, a0) = keys[i - 1];
      final f = Curves.easeInOut.transform((t - t0) / (t1 - t0));
      return a0 + (a1 - a0) * f;
    }
  }
  return 0;
}

class _IntroFrame extends StatelessWidget {
  const _IntroFrame({required this.ms});
  final double ms;

  @override
  Widget build(BuildContext context) {
    const w = LaunchIntro.robotWidth;
    const h = w * 455 / 420; // intro-base.png is 420 × 455

    final exit = Curves.easeIn.transform(_phase(ms, _exitAt, _total - _exitAt));
    // A little hop as the robot "wakes up".
    final hop = math.sin(math.pi * _phase(ms, 0, 500)) * 0.07;
    final scale = 1 + hop + exit * 0.14;
    final glow = _phase(ms, 100, 500);
    final word = Curves.easeOut.transform(_phase(ms, 250, 400));

    // Visor: the brain gives way to two eyes, which give the brain back at the end.
    final eyesIn = _phase(ms, 350, 220);
    final eyesOut = _phase(ms, 1900, 180);
    final eyes = eyesIn * (1 - eyesOut);
    final eyesScale = Curves.easeOutBack.transform(eyesIn);
    // The wink: the right eye (as you look at it) closes, holds, opens.
    final wink = ms < 1120
        ? Curves.easeIn.transform(_phase(ms, 1000, 120))
        : 1 - Curves.easeOut.transform(_phase(ms, 1260, 120));
    final sparkle = _phase(ms, 1060, 400);

    final arm = _waveDegrees(_phase(ms, 400, 1400)) * math.pi / 180;

    return Opacity(
      opacity: 1 - exit,
      child: ColoredBox(
        color: LaunchIntro.navy,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: glow,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [const Color(0xFF2B5C86).withValues(alpha: 0.55), const Color(0x002B5C86)],
                  ),
                ),
              ),
            ),
            Transform.scale(
              scale: scale,
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  children: [
                    Image.asset('assets/brand/intro-base.png', width: w, height: h),
                    Opacity(
                      opacity: 1 - eyes,
                      child: Image.asset('assets/brand/intro-brain.png', width: w, height: h),
                    ),
                    Transform.rotate(
                      angle: arm,
                      alignment: const FractionalOffset(0.34, 0.75),
                      child: Image.asset('assets/brand/wave-dark-hand.png', width: w, height: h),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _EyesPainter(on: eyes, scale: eyesScale, wink: wink, sparkle: sparkle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, h / 2 + 40 + (1 - word) * 12),
              child: Opacity(
                opacity: word * (1 - exit),
                child: Image.asset('assets/brand/wordmark-dark.png', width: 118),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two glowing eyes on the visor "screen". Positions are fractions of the
/// robot artwork (measured on the dark logo: the visor's centre is at
/// 65.3% × 36.0%).
class _EyesPainter extends CustomPainter {
  _EyesPainter({required this.on, required this.scale, required this.wink, required this.sparkle});
  final double on;
  final double scale;
  final double wink;
  final double sparkle;

  static const _eye = Color(0xFFCFEAF6);
  static const _glow = Color(0xFF5CA7C9);

  @override
  void paint(Canvas canvas, Size size) {
    if (on <= 0) return;
    final cy = size.height * 0.360;
    final ew = size.width * 0.052;
    final eh = size.height * 0.095 * scale;
    final left = Offset(size.width * 0.548, cy);
    final right = Offset(size.width * 0.758, cy);
    final glow = Paint()
      ..color = _glow.withValues(alpha: 0.75 * on)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final core = Paint()..color = _eye.withValues(alpha: on);

    void openEye(Offset c, double height) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: ew, height: math.max(height, ew * 0.4)),
        Radius.circular(ew / 2),
      );
      canvas.drawRRect(r.inflate(1.5), glow);
      canvas.drawRRect(r, core);
    }

    openEye(left, eh);

    if (wink < 0.75) {
      openEye(right, eh * (1 - wink));
    } else {
      // Closed: a happy "^" arc.
      final arc = Path()
        ..moveTo(right.dx - ew * 0.9, right.dy + ew * 0.35)
        ..quadraticBezierTo(right.dx, right.dy - ew * 0.75, right.dx + ew * 0.9, right.dy + ew * 0.35);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ew * 0.55;
      canvas.drawPath(arc, stroke..color = _glow.withValues(alpha: 0.75 * on));
      canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ew * 0.42
          ..color = _eye.withValues(alpha: on),
      );
    }

    // A twinkle next to the winking eye.
    if (sparkle > 0 && sparkle < 1) {
      final s = math.sin(math.pi * sparkle) * size.width * 0.07;
      final c = Offset(right.dx + size.width * 0.13, cy - size.height * 0.105);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(sparkle * math.pi / 2);
      final star = Path()
        ..moveTo(0, -s)
        ..quadraticBezierTo(0, 0, s, 0)
        ..quadraticBezierTo(0, 0, 0, s)
        ..quadraticBezierTo(0, 0, -s, 0)
        ..quadraticBezierTo(0, 0, 0, -s)
        ..close();
      canvas.drawPath(star, Paint()..color = const Color(0xFFFFD36E));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_EyesPainter old) =>
      old.on != on || old.scale != scale || old.wink != wink || old.sparkle != sparkle;
}

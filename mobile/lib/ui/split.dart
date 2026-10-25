import 'package:flutter/material.dart';

/// Marks the list side of a desktop list–detail pair (see
/// desktop/split_view.dart) and knows the navigator of the detail side.
class DetailHost extends InheritedWidget {
  const DetailHost({super.key, required this.detail, required super.child});
  final GlobalKey<NavigatorState> detail;

  @override
  bool updateShouldNotify(DetailHost old) => old.detail != detail;
}

/// Opens [page] from a list. On the phone it is a new screen on top; in
/// the macOS app, called from the list side of a split view, it replaces
/// whatever the detail side showed, and the list stays where it was.
Future<T?> openPage<T>(BuildContext context, Widget page) {
  final detail = context.getInheritedWidgetOfExactType<DetailHost>()?.detail.currentState;
  if (detail == null) return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
  return detail.pushAndRemoveUntil<T>(DetailRoute(page), (r) => r.isFirst);
}

/// A page swapped into the detail side: a quick fade and settle instead of
/// a slide, since it doesn't go "deeper" than the list next to it.
class DetailRoute<T> extends PageRouteBuilder<T> {
  DetailRoute(Widget page)
    : super(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) {
          final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.985, end: 1.0).animate(a), child: child),
          );
        },
      );
}

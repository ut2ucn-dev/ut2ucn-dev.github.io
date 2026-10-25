import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/split.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'platform.dart';

/// A list on the left and whatever was picked in it on the right, as in
/// Mail or Finder. The phone screens are reused as they are: a tap that
/// would push a new screen ([openPage]) fills the right side instead, and
/// screens opened from there (a student from a lesson, an edit form) stack
/// on the right with a back arrow. The divider can be dragged.
class SplitView extends StatefulWidget {
  const SplitView({
    super.key,
    required this.list,
    required this.emptyIcon,
    required this.emptyText,
    this.listWidth = 420,
  });

  final Widget list;
  final IconData emptyIcon;
  final String emptyText;
  final double listWidth;

  @override
  State<SplitView> createState() => SplitViewState();
}

class SplitViewState extends State<SplitView> {
  static const _minList = 320.0;
  static const _minDetail = 420.0;

  final _detail = GlobalKey<NavigatorState>();
  late double _width = widget.listWidth;

  /// Shows [page] on the right (menu commands such as "New lesson").
  Future<T?> open<T>(Widget page) => _detail.currentState!.pushAndRemoveUntil<T>(DetailRoute(page), (r) => r.isFirst);

  /// Back to the empty right side.
  void closeDetail() => _detail.currentState?.popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        final maxList = (box.maxWidth - _minDetail).clamp(_minList, double.infinity);
        final width = _width.clamp(_minList, maxList);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: width,
              child: DetailHost(
                detail: _detail,
                child: HeroControllerScope.none(
                  child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => widget.list)),
                ),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => setState(() => _width = (width + d.delta.dx).clamp(_minList, maxList)),
                child: SizedBox(
                  width: 7,
                  child: Center(child: Container(width: 1, color: c.line)),
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: HeroControllerScope.none(
                  child: Navigator(
                    key: _detail,
                    onGenerateRoute: (_) => PageRouteBuilder(
                      pageBuilder: (_, _, _) => _EmptyDetail(icon: widget.emptyIcon, text: widget.emptyText),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: 0.55, child: StemikMark(size: 84)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: c.inkSoft),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a full-width admin page (teachers, rates, report) at a readable
/// width in a big window.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = 980});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.c.paper,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

/// ⌘ on the Mac; Ctrl on Windows (and when previewed elsewhere).
SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, meta: hasNativeMenuBar, control: !hasNativeMenuBar, shift: shift);

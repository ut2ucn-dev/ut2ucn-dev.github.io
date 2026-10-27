import 'package:flutter/material.dart';

import '../util/domain.dart';

/// The web version's CSS variables (:root and :root.theme-dark).
@immutable
class StemikColors extends ThemeExtension<StemikColors> {
  final Color ink, inkSoft, paper, card, line, lineStrong;
  final Color brand, brandSoft, brandText;
  final Color sand, sandText;
  final Color alert, alertSoft, alertText;
  final Color success, successSoft, successText;
  final Color danger, dangerSoft;
  final Color vr, vrSoft;

  const StemikColors({
    required this.ink,
    required this.inkSoft,
    required this.paper,
    required this.card,
    required this.line,
    required this.lineStrong,
    required this.brand,
    required this.brandSoft,
    required this.brandText,
    required this.sand,
    required this.sandText,
    required this.alert,
    required this.alertSoft,
    required this.alertText,
    required this.success,
    required this.successSoft,
    required this.successText,
    required this.danger,
    required this.dangerSoft,
    required this.vr,
    required this.vrSoft,
  });

  static const light = StemikColors(
    ink: Color(0xFF171923),
    inkSoft: Color(0xFF6B7080),
    paper: Color(0xFFF6F6FB),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE7E8F1),
    lineStrong: Color(0xFFD7D9E8),
    brand: Color(0xFF5B4FE0),
    brandSoft: Color(0xFFEFEDFC),
    brandText: Color(0xFF4B3FCB),
    sand: Color(0xFFEDEEF5),
    sandText: Color(0xFF6B6D84),
    alert: Color(0xFFF5A524),
    alertSoft: Color(0xFFFDF1DC),
    alertText: Color(0xFF95610A),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFE7F8ED),
    successText: Color(0xFF0F7A38),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFDECEC),
    vr: Color(0xFF8B5CF6),
    vrSoft: Color(0x248B5CF6),
  );

  static const dark = StemikColors(
    ink: Color(0xFFF1F2F8),
    inkSoft: Color(0xFF9497AC),
    paper: Color(0xFF0F0F16),
    card: Color(0xFF181924),
    line: Color(0xFF262837),
    lineStrong: Color(0xFF34364A),
    brand: Color(0xFF8B80FF),
    brandSoft: Color(0x2E8B80FF),
    brandText: Color(0xFFB4AAFF),
    sand: Color(0xFF242534),
    sandText: Color(0xFFA7A9C0),
    alert: Color(0xFFFFB84D),
    alertSoft: Color(0x29FFB84D),
    alertText: Color(0xFFFFC777),
    success: Color(0xFF4ADE80),
    successSoft: Color(0x294ADE80),
    successText: Color(0xFF6EE7A0),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x29F87171),
    vr: Color(0xFFA78BFA),
    vrSoft: Color(0x29A78BFA),
  );

  /// Accent for a course, by track (3D / VR / Robotics), as courseAccent().
  ({Color color, Color soft}) course(String? course) {
    switch (courseTrack(course)) {
      case CourseTrack.vr:
        return (color: vr, soft: vrSoft);
      case CourseTrack.threeD:
        return (color: brandText, soft: brandSoft);
      case CourseTrack.robo:
        return (color: successText, soft: successSoft);
      case CourseTrack.other:
        return (color: sandText, soft: sand);
    }
  }

  @override
  StemikColors copyWith() => this;

  @override
  StemikColors lerp(ThemeExtension<StemikColors>? other, double t) => t < 0.5 ? this : (other as StemikColors? ?? this);
}

extension StemikTheme on BuildContext {
  StemikColors get c => Theme.of(this).extension<StemikColors>()!;
}

const navy = Color(0xFF1C1642);

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? StemikColors.dark : StemikColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF5B4FE0), brightness: brightness).copyWith(
    primary: c.brand,
    onPrimary: Colors.white,
    surface: c.card,
    onSurface: c.ink,
    onSurfaceVariant: c.inkSoft,
    outline: c.lineStrong,
    outlineVariant: c.line,
    error: c.danger,
    surfaceContainerLowest: c.card,
    surfaceContainerLow: c.card,
    surfaceContainer: c.paper,
    surfaceContainerHigh: c.card,
    surfaceContainerHighest: c.sand,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Exo2',
    scaffoldBackgroundColor: c.paper,
    extensions: [c],
  );
  final radius = BorderRadius.circular(14);
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Exo2', fontSize: 21, fontWeight: FontWeight.w800, color: c.ink),
    ),
    cardTheme: CardThemeData(
      color: c.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.brandSoft,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Exo2',
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? c.brandText : c.inkSoft,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.brandText : c.inkSoft),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.brand, width: 1.6),
      ),
      labelStyle: TextStyle(color: c.inkSoft),
      hintStyle: TextStyle(color: c.inkSoft.withValues(alpha: 0.7)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Exo2', fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(0, 44),
        side: BorderSide(color: c.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Exo2', fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brandText,
        textStyle: const TextStyle(fontFamily: 'Exo2', fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.brand,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : c.card),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? c.brand : c.lineStrong),
      ),
      // Plain style: Android doesn't resolve a state-dependent one here, so
      // selected/unselected label colours are set by PickChip instead.
      labelStyle: TextStyle(fontFamily: 'Exo2', color: c.ink, fontWeight: FontWeight.w600, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Exo2', fontWeight: FontWeight.w700, fontSize: 13),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : c.card),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : c.ink,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.lineStrong)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark ? c.sand : navy,
      contentTextStyle: const TextStyle(fontFamily: 'Exo2', color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.inkSoft),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : null),
    ),
  );
}

// CupertinoPageTransitionsBuilder lives in the cupertino library and is no
// longer re-exported by material.dart, so it is pulled in explicitly.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ---------------------------------------------------------------------------
/// DailyHub design system — "Clean & calm".
///
/// Soft neutral surfaces, one accent colour the user picks, generous spacing,
/// and a single friendly typeface. Every screen reads its colours from here
/// (via `context.tokens` / `Theme.of(context).colorScheme`) so light mode,
/// dark mode and all 8 accents stay consistent automatically.
/// ---------------------------------------------------------------------------

class AccentOption {
  final String id;
  final String nameKey;
  final Color light; // used on light backgrounds
  final Color dark; // lighter tone used on dark backgrounds
  const AccentOption(this.id, this.nameKey, this.light, this.dark);
}

class Accents {
  static const List<AccentOption> all = [
    AccentOption('indigo', 'accent_indigo', Color(0xFF4F46E5), Color(0xFF8B8FF9)),
    AccentOption('blue', 'accent_blue', Color(0xFF2563EB), Color(0xFF60A5FA)),
    AccentOption('teal', 'accent_teal', Color(0xFF0F8F84), Color(0xFF2DD4BF)),
    AccentOption('green', 'accent_green', Color(0xFF15803D), Color(0xFF4ADE80)),
    AccentOption('orange', 'accent_orange', Color(0xFFD9480F), Color(0xFFFB923C)),
    AccentOption('rose', 'accent_rose', Color(0xFFE11D48), Color(0xFFFB7185)),
    AccentOption('violet', 'accent_violet', Color(0xFF7C3AED), Color(0xFFA78BFA)),
    AccentOption('graphite', 'accent_graphite', Color(0xFF334155), Color(0xFFCBD5E1)),
  ];

  static AccentOption byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);
}

/// Legacy + semantic colours. The static brand values are kept so older
/// screens still compile; new code uses the theme instead.
class AppColors {
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryDark = Color(0xFF7C3AED);
  static const Color accent = Color(0xFFF59E0B);

  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color info = Color(0xFF2563EB);

  static const Color income = Color(0xFF12A150);
  static const Color expense = Color(0xFFE5484D);
  static const Color transfer = Color(0xFF3B82F6);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primary, primaryDark],
  );

  // Module identity colours — used for icon badges everywhere.
  static const Color mTasks = Color(0xFF4F7DF3);
  static const Color mReminders = Color(0xFFF59E0B);
  static const Color mCalendar = Color(0xFF8B5CF6);
  static const Color mNotes = Color(0xFFE2A400);
  static const Color mHabits = Color(0xFFF97316);
  static const Color mMoney = Color(0xFF10B981);
  static const Color mGoals = Color(0xFF06B6D4);
  static const Color mJournal = Color(0xFFEC4899);
  static const Color mTrips = Color(0xFF0EA5E9);
  static const Color mStudy = Color(0xFF6366F1);
  static const Color mWork = Color(0xFF64748B);
  static const Color mShopping = Color(0xFFF43F5E);
  static const Color mVault = Color(0xFF475569);
  static const Color mEmergency = Color(0xFFDC2626);
  static const Color mTools = Color(0xFF14B8A6);
  static const Color mPlaces = Color(0xFF22C55E);
  static const Color mPackages = Color(0xFFB45309);
  static const Color mBookmarks = Color(0xFF8B5CF6);
  static const Color mCountdown = Color(0xFFEAB308);
  static const Color mInsights = Color(0xFF3B82F6);
  static const Color mTracker = Color(0xFF9333EA);
  static const Color mPrayer = Color(0xFF0D9488);

  /// Palette for user-coloured things (lists, habits, accounts, categories).
  static const List<Color> swatches = [
    Color(0xFF4F7DF3),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFF43F5E),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFF97316),
    Color(0xFF64748B),
    Color(0xFFEC4899),
    Color(0xFF84CC16),
  ];

  static Color swatch(int i) => swatches[i.abs() % swatches.length];
}

/// Extra design tokens that don't fit in ColorScheme.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Color bg;
  final Color card;
  final Color border;
  final Color subtle; // input / chip fill
  final Color subtleStrong;
  final Color textMuted;
  final Color textFaint;
  final Color success;
  final Color warning;
  final Color danger;
  final Color income;
  final Color expense;
  final Color transfer;
  final bool dark;

  const AppTokens({
    required this.bg,
    required this.card,
    required this.border,
    required this.subtle,
    required this.subtleStrong,
    required this.textMuted,
    required this.textFaint,
    required this.success,
    required this.warning,
    required this.danger,
    required this.income,
    required this.expense,
    required this.transfer,
    required this.dark,
  });

  /// Soft background tint for icon badges and chips.
  Color tint(Color c) => c.withValues(alpha: dark ? 0.20 : 0.12);

  @override
  AppTokens copyWith({Color? bg, Color? card}) => AppTokens(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        border: border,
        subtle: subtle,
        subtleStrong: subtleStrong,
        textMuted: textMuted,
        textFaint: textFaint,
        success: success,
        warning: warning,
        danger: danger,
        income: income,
        expense: expense,
        transfer: transfer,
        dark: dark,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppTokens(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      border: l(border, other.border),
      subtle: l(subtle, other.subtle),
      subtleStrong: l(subtleStrong, other.subtleStrong),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      income: l(income, other.income),
      expense: l(expense, other.expense),
      transfer: l(transfer, other.transfer),
      dark: t < 0.5 ? dark : other.dark,
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class Space {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 20, xxl = 24, xxxl = 32;
}

class Radii {
  static const double s = 10, m = 14, l = 20, xl = 28;
  static BorderRadius get card => BorderRadius.circular(l);
  static BorderRadius get input => BorderRadius.circular(m);
}

class AppTheme {
  static const String fontFamily = 'Plus Jakarta Sans';

  static ThemeData build({
    required Brightness brightness,
    required AccentOption accent,
  }) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? accent.dark : accent.light;
    final onPrimary = dark ? const Color(0xFF0E1014) : Colors.white;

    final tokens = dark
        ? const AppTokens(
            bg: Color(0xFF0E1014),
            card: Color(0xFF16191F),
            border: Color(0xFF262A33),
            subtle: Color(0xFF1E222A),
            subtleStrong: Color(0xFF272C35),
            textMuted: Color(0xFFA3ABB8),
            textFaint: Color(0xFF6B7280),
            success: Color(0xFF34D399),
            warning: Color(0xFFFBBF24),
            danger: Color(0xFFF87171),
            income: Color(0xFF34D399),
            expense: Color(0xFFFB7185),
            transfer: Color(0xFF60A5FA),
            dark: true,
          )
        : const AppTokens(
            bg: Color(0xFFF5F6F8),
            card: Color(0xFFFFFFFF),
            border: Color(0xFFE6E8EC),
            subtle: Color(0xFFEFF1F4),
            subtleStrong: Color(0xFFE4E7EC),
            textMuted: Color(0xFF5B6472),
            textFaint: Color(0xFF8B93A1),
            success: Color(0xFF16A34A),
            warning: Color(0xFFD97706),
            danger: Color(0xFFDC2626),
            income: Color(0xFF12A150),
            expense: Color(0xFFE5484D),
            transfer: Color(0xFF2563EB),
            dark: false,
          );

    final onSurface = dark ? const Color(0xFFF2F4F7) : const Color(0xFF111827);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent.light,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primary.withValues(alpha: dark ? 0.22 : 0.12),
      onPrimaryContainer: primary,
      secondary: primary,
      onSecondary: onPrimary,
      error: tokens.danger,
      onError: Colors.white,
      surface: tokens.card,
      onSurface: onSurface,
      onSurfaceVariant: tokens.textMuted,
      surfaceContainerLowest: tokens.card,
      surfaceContainerLow: tokens.card,
      surfaceContainer: tokens.subtle,
      surfaceContainerHigh: tokens.subtleStrong,
      surfaceContainerHighest: tokens.subtleStrong,
      outline: tokens.border,
      outlineVariant: tokens.border,
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
      inverseSurface: dark ? const Color(0xFFF2F4F7) : const Color(0xFF1B1F27),
      onInverseSurface: dark ? const Color(0xFF111827) : Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    TextTheme text = GoogleFonts.getTextTheme(fontFamily, base.textTheme);
    text = text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
          fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: text.titleLarge?.copyWith(
          fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(
          fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      titleSmall: text.titleSmall?.copyWith(
          fontSize: 14, fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14.5, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(
          fontSize: 12.5, height: 1.35, color: tokens.textMuted),
      labelLarge: text.labelLarge?.copyWith(
          fontSize: 14.5, fontWeight: FontWeight.w700),
      labelMedium: text.labelMedium?.copyWith(
          fontSize: 12.5, fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4),
    );
    text = text.apply(bodyColor: onSurface, displayColor: onSurface);

    final inputBorder = OutlineInputBorder(
      borderRadius: Radii.input,
      borderSide: BorderSide.none,
    );

    return base.copyWith(
      scaffoldBackgroundColor: tokens.bg,
      canvasColor: tokens.bg,
      textTheme: text,
      primaryTextTheme: text,
      extensions: <ThemeExtension<dynamic>>[tokens],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 20),
        iconTheme: IconThemeData(color: onSurface, size: 24),
      ),
      cardTheme: CardThemeData(
        color: tokens.card,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(color: tokens.border, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: tokens.textMuted,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
        minVerticalPadding: 10,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.subtle,
        hintStyle: text.bodyMedium?.copyWith(color: tokens.textFaint),
        labelStyle: text.bodyMedium?.copyWith(color: tokens.textMuted),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: primary),
        prefixIconColor: tokens.textMuted,
        suffixIconColor: tokens.textMuted,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.input,
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.input,
          borderSide: BorderSide(color: tokens.danger, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.s)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: tokens.subtle,
        selectedColor: primary.withValues(alpha: dark ? 0.28 : 0.14),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium?.copyWith(color: onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: tokens.card,
        showDragHandle: true,
        dragHandleColor: tokens.subtleStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF2A2F38) : const Color(0xFF1B1F27),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: dark ? accent.dark : const Color(0xFFA5B4FC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? onPrimary : tokens.textFaint),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : tokens.subtleStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: tokens.textFaint, width: 1.6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: tokens.subtle,
          selectedBackgroundColor: tokens.card,
          selectedForegroundColor: onSurface,
          foregroundColor: tokens.textMuted,
          side: BorderSide(color: tokens.border),
          textStyle: text.labelMedium,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: tokens.subtle,
        circularTrackColor: tokens.subtle,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: tokens.textMuted,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.card,
        indicatorColor: primary.withValues(alpha: dark ? 0.24 : 0.12),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.all(text.labelSmall),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.card,
        indicatorColor: primary.withValues(alpha: dark ? 0.24 : 0.12),
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: tokens.textMuted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: primary),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: tokens.textMuted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tokens.border),
        ),
        textStyle: text.bodyMedium,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: tokens.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: primary,
        headerForegroundColor: onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: tokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: tokens.subtleStrong,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2F38) : const Color(0xFF1B1F27),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.labelMedium?.copyWith(color: Colors.white),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

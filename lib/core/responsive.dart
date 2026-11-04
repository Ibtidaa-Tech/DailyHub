import 'package:flutter/material.dart';

/// Screen-size buckets. The web build previously rendered phone-width columns
/// stretched across a desktop monitor; these breakpoints fix that by letting
/// each screen pick a layout appropriate to the viewport.
enum ScreenSize { phone, tablet, desktop }

class Responsive {
  static const double tabletBreakpoint = 700;
  static const double desktopBreakpoint = 1100;

  /// Maximum content width on very wide screens, so text lines don't run
  /// the full width of a 27" monitor.
  static const double maxContentWidth = 1200;

  static ScreenSize of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return ScreenSize.desktop;
    if (w >= tabletBreakpoint) return ScreenSize.tablet;
    return ScreenSize.phone;
  }

  static bool isPhone(BuildContext context) =>
      of(context) == ScreenSize.phone;
  static bool isTablet(BuildContext context) =>
      of(context) == ScreenSize.tablet;
  static bool isDesktop(BuildContext context) =>
      of(context) == ScreenSize.desktop;

  /// True when there's room for a persistent side navigation instead of a
  /// bottom bar.
  static bool hasSideNav(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  /// Sensible column count for card/tile grids at the current width.
  static int gridColumns(BuildContext context,
      {int phone = 2, int tablet = 3, int desktop = 4}) {
    return switch (of(context)) {
      ScreenSize.phone => phone,
      ScreenSize.tablet => tablet,
      ScreenSize.desktop => desktop,
    };
  }
}

/// Centers content and caps its width on large screens. Wrap page bodies in
/// this so desktop doesn't get absurdly long line lengths.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Builds different widgets per screen size without repeating MediaQuery
/// logic in every screen.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenSize size) builder;
  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => builder(context, Responsive.of(context));
}

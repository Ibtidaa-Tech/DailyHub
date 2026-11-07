import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization.dart';
import '../core/theme.dart';

/// ---------------------------------------------------------------------------
/// DailyHub UI kit — small, consistent building blocks used by every screen.
/// ---------------------------------------------------------------------------

const double kMaxContent = 760;

/// Horizontal padding that keeps content centred at [maxWidth] on big screens.
double sidePad(BuildContext context, {double maxWidth = kMaxContent, double min = 16}) {
  final w = MediaQuery.sizeOf(context).width;
  return math.max(min, (w - maxWidth) / 2);
}

/// Standard page: collapsing large title, actions, slivers, optional FAB.
class AppPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final List<Widget> slivers;
  final Widget? fab;
  final Widget? leading;
  final bool showBack;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  final Widget? header;
  final ScrollController? controller;
  final Widget? bottomBar;

  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    required this.slivers,
    this.fab,
    this.leading,
    this.showBack = true,
    this.maxWidth = kMaxContent,
    this.onRefresh,
    this.header,
    this.controller,
    this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    final pad = sidePad(context, maxWidth: maxWidth);
    final canPop = Navigator.of(context).canPop();
    final tokens = context.tokens;
    Widget scroll = CustomScrollView(
      controller: controller,
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: subtitle == null ? 108 : 126,
          backgroundColor: tokens.bg,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: showBack && canPop,
          leading: leading,
          actions: [...?actions, SizedBox(width: pad > 16 ? pad - 8 : 8)],
          flexibleSpace: _CollapsingTitle(
            title: title,
            subtitle: subtitle,
            pad: pad,
            hasLeading: leading != null || (showBack && canPop),
          ),
        ),
        if (header != null)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverToBoxAdapter(child: header),
          ),
        for (final s in slivers)
          SliverPadding(padding: EdgeInsets.symmetric(horizontal: pad), sliver: s),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: onRefresh!, child: scroll);
    }
    return Scaffold(
      floatingActionButton: fab,
      bottomNavigationBar: bottomBar,
      body: scroll,
    );
  }
}

class _CollapsingTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double pad;
  final bool hasLeading;
  const _CollapsingTitle({
    required this.title,
    required this.subtitle,
    required this.pad,
    required this.hasLeading,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final top = MediaQuery.paddingOf(context).top;
      final min = kToolbarHeight + top;
      final max = (subtitle == null ? 108 : 126) + top;
      final t = ((c.maxHeight - min) / (max - min)).clamp(0.0, 1.0);
      final size = 19 + 9 * t;
      final left = hasLeading ? (56 * (1 - t)) + pad * t + (t == 0 ? 0 : 0) : pad;
      return Stack(children: [
        Positioned(
          left: hasLeading ? math.max(left, pad) : pad,
          right: 96,
          bottom: 12 + 2 * t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.headlineMedium?.copyWith(fontSize: size)),
              if (subtitle != null && t > 0.5)
                Opacity(
                  opacity: ((t - 0.5) * 2).clamp(0.0, 1.0),
                  child: Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodyMedium?.copyWith(color: context.tokens.textMuted)),
                ),
            ],
          ),
        ),
      ]);
    });
  }
}

/// Simple top bar for pushed screens that need a normal app bar.
PreferredSizeWidget simpleBar(BuildContext context, String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) {
  return AppBar(title: Text(title), actions: actions, bottom: bottom);
}

/// Surface card with the app's border and radius.
class DhCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;
  final double radius;
  const DhCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.radius = Radii.l,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? tk.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor ?? tk.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Section label with an optional action on the right.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(this.title,
      {super.key, this.action, this.onAction, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 18, 0, 6)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: context.tt.labelSmall?.copyWith(color: context.tokens.textMuted, letterSpacing: 0.8)),
          ),
          if (trailing != null) trailing!,
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Rounded-square icon (or emoji) with a soft tinted background.
class IconBadge extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final Color color;
  final double size;
  final double radius;
  const IconBadge({super.key, this.icon, this.emoji, required this.color, this.size = 40, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tokens.tint(color),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: emoji != null
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.5, height: 1.1))
          : Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// Friendly empty state with an optional call to action.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;
  final bool compact;
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.cs.primary;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 18 : 44, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: icon, color: c, size: compact ? 48 : 64, radius: compact ? 16 : 22),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: context.tt.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                textAlign: TextAlign.center,
                style: context.tt.bodyMedium?.copyWith(color: context.tokens.textMuted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small coloured label.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  const Pill(this.text, {super.key, required this.color, this.icon, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : context.tokens.tint(color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: filled ? Colors.white : color),
          const SizedBox(width: 4),
        ],
        Text(text,
            style: context.tt.labelSmall?.copyWith(
                color: filled ? Colors.white : color, letterSpacing: 0.1, fontSize: 11.5)),
      ]),
    );
  }
}

/// Inline meta text with icon, used under list titles.
class MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const MetaChip(this.icon, this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.tokens.textMuted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: c),
      const SizedBox(width: 3),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tt.bodySmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Rounded progress bar.
class ProgressBar extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;
  final Color? track;
  const ProgressBar({super.key, required this.value, this.color, this.height = 8, this.track});

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Container(color: track ?? context.tokens.subtle),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                color: color ?? context.cs.primary,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Circular progress ring with optional centre widget.
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Color? track;
  final Widget? child;
  const ProgressRing({super.key, required this.value, this.size = 44, this.stroke = 5, this.color, this.track, this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
          stroke: stroke,
          color: color ?? context.cs.primary,
          track: track ?? context.tokens.subtle,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value, stroke;
  final Color color, track;
  _RingPainter({required this.value, required this.stroke, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    if (value > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * value, false,
          p..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.value != value || o.color != color || o.track != track || o.stroke != stroke;
}

/// Donut chart of [values] with matching [colors].
class Donut extends StatelessWidget {
  final List<double> values;
  final List<Color> colors;
  final double size;
  final double stroke;
  final Widget? center;
  const Donut({super.key, required this.values, required this.colors, this.size = 140, this.stroke = 16, this.center});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(values, colors, stroke, context.tokens.subtle, context.tokens.card),
        child: Center(child: center),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double stroke;
  final Color track;
  final Color gap;
  _DonutPainter(this.values, this.colors, this.stroke, this.track, this.gap);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = values.fold(0.0, (s, v) => s + v);
    if (total <= 0) {
      canvas.drawCircle(c, r, p..color = track);
      return;
    }
    var start = -math.pi / 2;
    const gapRad = 0.035;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      if (sweep <= 0) continue;
      final s = values.length > 1 ? math.max(0.0, sweep - gapRad) : sweep;
      canvas.drawArc(rect, start, s, false, p..color = colors[i % colors.length]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.values != values || o.colors != colors;
}

/// Minimal bar chart. [highlight] marks one bar (e.g. today).
class MiniBars extends StatelessWidget {
  final List<double> values;
  final List<double>? values2; // optional second series drawn beside
  final Color color;
  final Color? color2;
  final int? highlight;
  final double height;
  final List<String>? labels;
  const MiniBars({
    super.key,
    required this.values,
    this.values2,
    required this.color,
    this.color2,
    this.highlight,
    this.height = 120,
    this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = [...values, ...?values2].fold(0.0, (m, v) => math.max(m, v));
    final tk = context.tokens;
    return SizedBox(
      height: height + (labels == null ? 0 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          double h(double v) => maxV <= 0 ? 3 : math.max(3, (v / maxV) * height);
          final isHi = highlight == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: values.length > 20 ? 1 : 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          height: h(values[i]),
                          decoration: BoxDecoration(
                            color: values[i] <= 0
                                ? tk.subtle
                                : (isHi || highlight == null ? color : color.withValues(alpha: 0.45)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      if (values2 != null) ...[
                        const SizedBox(width: 2),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            height: h(values2![i]),
                            decoration: BoxDecoration(
                              color: values2![i] <= 0 ? tk.subtle : (color2 ?? color),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (labels != null) ...[
                    const SizedBox(height: 4),
                    Text(labels![i],
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: context.tt.labelSmall?.copyWith(
                            color: isHi ? context.cs.onSurface : tk.textFaint, fontSize: 10)),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// GitHub-style heatmap: [weeks] columns × 7 rows ending today.
class Heatmap extends StatelessWidget {
  final int weeks;
  final double Function(DateTime day) valueOf; // 0..1
  final bool Function(DateTime day)? scheduled;
  final Color color;
  final int weekStart;
  const Heatmap({
    super.key,
    required this.valueOf,
    required this.color,
    this.weeks = 18,
    this.scheduled,
    this.weekStart = DateTime.monday,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final offset = (t0.weekday - weekStart + 7) % 7;
    final lastColStart = DateTime(t0.year, t0.month, t0.day - offset);
    final firstColStart = DateTime(lastColStart.year, lastColStart.month, lastColStart.day - 7 * (weeks - 1));
    return LayoutBuilder(builder: (context, c) {
      final cell = math.min(18.0, (c.maxWidth - (weeks - 1) * 3) / weeks);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(weeks, (w) {
          return Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : 3),
            child: Column(
              children: List.generate(7, (d) {
                final day = DateTime(firstColStart.year, firstColStart.month, firstColStart.day + w * 7 + d);
                final future = day.isAfter(t0);
                final v = future ? 0.0 : valueOf(day).clamp(0.0, 1.0);
                final sched = scheduled?.call(day) ?? true;
                Color fill;
                if (future) {
                  fill = Colors.transparent;
                } else if (v <= 0) {
                  fill = sched ? tk.subtle : tk.subtle.withValues(alpha: 0.4);
                } else {
                  fill = color.withValues(alpha: 0.25 + 0.75 * v);
                }
                return Container(
                  width: cell,
                  height: cell,
                  margin: const EdgeInsets.only(bottom: 3),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(cell * 0.28),
                    border: sameDate(day, t0) ? Border.all(color: color, width: 1.5) : null,
                  ),
                );
              }),
            ),
          );
        }),
      );
    });
  }

  static bool sameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Pill-style segmented control.
class PillTabs<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;
  const PillTabs({super.key, required this.items, required this.value, required this.onChanged, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final children = items.map((it) {
      final sel = it.$1 == value;
      final chip = GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(it.$1);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: sel ? tk.card : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: sel
                ? [BoxShadow(color: Colors.black.withValues(alpha: tk.dark ? 0.3 : 0.06), blurRadius: 6, offset: const Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(it.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.labelMedium?.copyWith(
                  color: sel ? context.cs.onSurface : tk.textMuted,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w600)),
        ),
      );
      return expand ? Expanded(child: chip) : chip;
    }).toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: tk.subtle, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: children),
    );
  }
}

/// Horizontally scrolling chips with single selection.
class ChipRow<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T? value;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;
  final Widget? leading;
  const ChipRow({super.key, required this.items, required this.value, required this.onSelected, this.padding = EdgeInsets.zero, this.leading});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(it.$2),
              selected: it.$1 == value,
              onSelected: (_) => onSelected(it.$1),
              labelStyle: context.tt.labelMedium?.copyWith(
                color: it.$1 == value ? context.cs.primary : context.cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ]),
    );
  }
}

/// Round checkbox used for tasks and reminders.
class CheckDot extends StatelessWidget {
  final bool checked;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  const CheckDot({super.key, required this.checked, required this.color, this.onTap, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      radius: size,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: checked ? color : context.tokens.tint(color).withValues(alpha: 0.08),
            border: Border.all(color: color, width: 2),
          ),
          child: checked
              ? Icon(Icons.check_rounded, size: size * 0.7, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// Colour swatch picker.
class ColorDots extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final List<Color> colors;
  const ColorDots({super.key, required this.value, required this.onChanged, this.colors = AppColors.swatches});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(colors.length, (i) {
        final sel = i == value;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors[i],
              shape: BoxShape.circle,
              border: Border.all(color: sel ? context.cs.onSurface : Colors.transparent, width: 2.5),
            ),
            child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
          ),
        );
      }),
    );
  }
}

/// Curated emoji grid.
class EmojiGrid extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> emojis;
  const EmojiGrid({super.key, required this.value, required this.onChanged, this.emojis = kEmojis});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: emojis.map((e) {
        final sel = e == value;
        return GestureDetector(
          onTap: () => onChanged(e),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? context.cs.primaryContainer : context.tokens.subtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? context.cs.primary : Colors.transparent, width: 1.5),
            ),
            child: Text(e, style: const TextStyle(fontSize: 21)),
          ),
        );
      }).toList(),
    );
  }
}

const List<String> kEmojis = [
  '✅', '💪', '🏃', '🧘', '📚', '💧', '🥗', '😴', '🦷', '💊', '🚭', '📵',
  '✍️', '🎯', '💰', '🙏', '🧹', '🎸', '🌱', '☀️', '🍎', '🚶', '🧠', '❤️',
  '🏠', '💼', '🎓', '✈️', '🛒', '🎁', '📦', '📱', '💳', '🏦', '💵', '🚗',
  '🍔', '☕', '🎬', '🎮', '👶', '🐶', '⚽', '🎉', '📝', '⭐', '🔥', '🌙',
];

/// Standard modal bottom sheet with keyboard-safe padding.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool expand = false,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) {
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      final child = Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: builder(ctx),
      );
      if (expand) {
        return SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.92, child: child);
      }
      // A sheet sized to its content still has to cope with small screens, big
      // system fonts and the keyboard. Scrolling here means every sheet in the
      // app degrades gracefully instead of throwing a bottom overflow.
      return SingleChildScrollView(child: child);
    },
  );
}

/// Title row at the top of a sheet.
/// Labelled tappable field used across the editors (date, account, repeat...).
class FormFieldButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget? leading;
  const FormFieldButton({super.key, required this.icon, required this.label, required this.value, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Material(
      color: tk.subtle,
      borderRadius: BorderRadius.circular(Radii.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            leading ?? Icon(icon, size: 20, color: tk.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: context.tt.bodySmall?.copyWith(fontSize: 11)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
              ]),
            ),
            Icon(Icons.expand_more_rounded, color: tk.textFaint),
          ]),
        ),
      ),
    );
  }
}

class SheetHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final String? subtitle;
  const SheetHeader(this.title, {super.key, this.actions, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.tt.titleLarge),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: context.tt.bodySmall),
              ),
          ]),
        ),
        ...?actions,
      ]),
    );
  }
}

/// A tappable option row inside sheets (icon, title, subtitle, trailing).
class OptionTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  const OptionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = destructive ? context.tokens.danger : (color ?? context.cs.onSurface);
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: destructive ? c : (color ?? context.tokens.textMuted)),
      title: Text(title, style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: c)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

/// Settings-style grouped container.
class GroupCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  const GroupCard({super.key, required this.children, this.margin = const EdgeInsets.symmetric(vertical: 6)});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(Divider(height: 1, indent: 56, color: tk.border));
      }
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: tk.card,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: tk.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: Column(children: items)),
    );
  }
}

// ------------------------------------------------------------ feedback

void showToast(BuildContext context, String message, {IconData? icon}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  // clearSnackBars, not hideCurrentSnackBar: hiding removes only the one on
  // screen and leaves the queue, so a burst of toasts plays one after another
  // and looks like a bar that will not go away.
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 10)],
      Expanded(child: Text(message)),
    ]),
    duration: const Duration(seconds: 2),
    dismissDirection: DismissDirection.horizontal,
  ));
}

void showUndo(BuildContext context, String message, VoidCallback onUndo) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 5),
    // Three ways out, because an undo bar that overstays is worse than one
    // that goes early: it times out, it swipes away sideways, and it has an
    // X for anyone who would rather just be rid of it.
    dismissDirection: DismissDirection.horizontal,
    showCloseIcon: true,
    closeIconColor: Colors.white70,
    action: SnackBarAction(label: context.t('undo'), onPressed: onUndo),
  ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirm,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.tokens.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm ?? ctx.t('ok')),
        ),
      ],
    ),
  );
  return r == true;
}

/// Asks for a single line of text.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  TextInputType? keyboard,
}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: keyboard,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.t('save'))),
      ],
    ),
  );
  // Dispose after the dialog's exit animation, not while it still uses the controller.
  WidgetsBinding.instance.addPostFrameCallback((_) => Future<void>.delayed(const Duration(milliseconds: 400), c.dispose));
  return r;
}

/// Swipe actions: right = primary (e.g. complete), left = secondary.
class SwipeTile extends StatelessWidget {
  final Key swipeKey;
  final Widget child;
  final IconData? rightIcon;
  final Color? rightColor;
  final String? rightLabel;
  final Future<bool> Function()? onSwipeRight;
  final IconData? leftIcon;
  final Color? leftColor;
  final String? leftLabel;
  final Future<bool> Function()? onSwipeLeft;
  const SwipeTile({
    super.key,
    required this.swipeKey,
    required this.child,
    this.rightIcon,
    this.rightColor,
    this.rightLabel,
    this.onSwipeRight,
    this.leftIcon,
    this.leftColor,
    this.leftLabel,
    this.onSwipeLeft,
  });

  @override
  Widget build(BuildContext context) {
    DismissDirection dir;
    if (onSwipeRight != null && onSwipeLeft != null) {
      dir = DismissDirection.horizontal;
    } else if (onSwipeRight != null) {
      dir = DismissDirection.startToEnd;
    } else if (onSwipeLeft != null) {
      dir = DismissDirection.endToStart;
    } else {
      return child;
    }
    Widget bg(IconData? icon, Color? color, String? label, bool left) => Container(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: (color ?? context.cs.primary),
            borderRadius: BorderRadius.circular(Radii.l),
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!left && label != null)
                Text(label, style: context.tt.labelLarge?.copyWith(color: Colors.white)),
              if (!left && label != null) const SizedBox(width: 8),
              Icon(icon, color: Colors.white),
              if (left && label != null) const SizedBox(width: 8),
              if (left && label != null)
                Text(label, style: context.tt.labelLarge?.copyWith(color: Colors.white)),
            ],
          ),
        );
    return Dismissible(
      key: swipeKey,
      direction: dir,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      background: bg(rightIcon, rightColor, rightLabel, true),
      secondaryBackground: bg(leftIcon, leftColor, leftLabel, false),
      confirmDismiss: (d) async {
        HapticFeedback.mediumImpact();
        if (d == DismissDirection.startToEnd) return await onSwipeRight?.call() ?? false;
        return await onSwipeLeft?.call() ?? false;
      },
      child: child,
    );
  }
}

/// Avatar with initials.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const InitialsAvatar(this.name, {super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1 ? parts.first.characters.first : parts.first.characters.first + parts.last.characters.first)
            .toUpperCase();
    final c = color ?? AppColors.swatch(name.hashCode);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.tokens.tint(c), shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: size * 0.38)),
    );
  }
}

/// Large number with a caption, used in summary cards.
class StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  final CrossAxisAlignment align;
  const StatBlock({super.key, required this.label, required this.value, this.color, this.icon, this.align = CrossAxisAlignment.start});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color ?? context.tokens.textMuted), const SizedBox(width: 4)],
          Text(label, style: context.tt.bodySmall),
        ]),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: context.tt.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

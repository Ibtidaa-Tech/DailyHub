import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/tracker_models.dart';
import '../../ui/kit.dart';

/// Shared look of the tracker: one place that decides what each status looks
/// like, so the today list, the sheet and the dashboard never drift apart.

Color tickColor(BuildContext context, TickStatus s, Color itemColor) {
  final tk = context.tokens;
  return switch (s) {
    TickStatus.onTime => itemColor,
    TickStatus.overdue => tk.warning,
    TickStatus.backfilled => tk.transfer,
    TickStatus.missed => tk.danger,
    TickStatus.pending => tk.textFaint,
  };
}

/// "12 min late" / "2h 5m late" — minutes alone stop being readable quickly.
String lateLabel(BuildContext context, int minutes) {
  if (minutes < 60) return context.tr('tr_late_by', {'n': minutes});
  return context.tr('tr_late_by_h', {'h': minutes ~/ 60, 'm': minutes % 60});
}

/// Status as a small coloured label.
class TickPill extends StatelessWidget {
  final TickStatus status;
  final Color itemColor;
  final int lateBy;
  const TickPill(this.status, {super.key, required this.itemColor, this.lateBy = 0});

  @override
  Widget build(BuildContext context) {
    final c = tickColor(context, status, itemColor);
    final text = status == TickStatus.overdue && lateBy > 0
        ? lateLabel(context, lateBy)
        : context.t(tickStatusKey(status));
    return Pill(text, color: c, icon: tickIcon(status));
  }
}

/// A single box in the sheet. Deliberately plain — 11 columns of these are on
/// screen at once, so anything heavier costs a frame.
class TickBox extends StatelessWidget {
  final TickStatus status;
  final Color color;
  final bool enabled;

  /// Item had not started yet on this day, so there is nothing to tick.
  final bool outOfRange;
  final VoidCallback? onTap;
  final double size;

  const TickBox({
    super.key,
    required this.status,
    required this.color,
    this.enabled = true,
    this.outOfRange = false,
    this.onTap,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    if (outOfRange) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Container(width: 9, height: 2, color: tk.border),
        ),
      );
    }
    final c = tickColor(context, status, color);
    final filled = status == TickStatus.onTime ||
        status == TickStatus.overdue ||
        status == TickStatus.backfilled;
    return Semantics(
      button: enabled,
      label: context.t(tickStatusKey(status)),
      child: InkResponse(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap?.call();
              }
            : null,
        radius: size * 0.8,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: filled ? c : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: filled
                  ? c
                  : (status == TickStatus.missed ? c.withValues(alpha: 0.5) : color.withValues(alpha: 0.55)),
              width: 1.6,
            ),
          ),
          child: filled
              ? Icon(tickIcon(status), size: size * 0.64, color: Colors.white)
              : (status == TickStatus.missed
                  ? Icon(Icons.close_rounded, size: size * 0.58, color: c.withValues(alpha: 0.75))
                  : null),
        ),
      ),
    );
  }
}

/// The colour key under the sheet.
class TickLegend extends StatelessWidget {
  const TickLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const statuses = [
      TickStatus.onTime,
      TickStatus.overdue,
      TickStatus.backfilled,
      TickStatus.missed,
      TickStatus.pending,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final s in statuses)
          Row(mainAxisSize: MainAxisSize.min, children: [
            TickBox(status: s, color: context.cs.primary, enabled: false, size: 18),
            const SizedBox(width: 6),
            Text(context.t(tickStatusKey(s)),
                style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted)),
          ]),
      ],
    );
  }
}

/// One line describing when an item is expected: its window, or that it can
/// be done any time.
String windowText(BuildContext context, TrackerItem item) {
  if (!item.hasWindow) return context.t('tr_anytime');
  return item.windowLabel((hm) => context.timeOfHm(hm));
}

/// How long is left before an item's window closes today, as a short phrase.
/// Null when it has no window or the window has already shut.
String? closesInText(BuildContext context, TrackerItem item, DateTime day) {
  final deadline = item.deadlineOn(day);
  if (deadline == null) return null;
  final left = deadline.difference(DateTime.now());
  if (left.isNegative) return context.t('tr_closed');
  if (left.inMinutes < 60) {
    return context.tr('tr_closes_in', {'x': context.tr('dur_min', {'n': left.inMinutes})});
  }
  if (left.inHours < 24) {
    return context.tr('tr_closes_in', {'x': context.tr('dur_hour', {'n': left.inHours})});
  }
  return null;
}

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/tracker_models.dart';
import '../../ui/kit.dart';
import 'tracker_ui.dart';

/// What the caller should do after the sheet closes.
enum TickAction { changeTime, clear }

/// Opened by tapping a box that is already ticked.
///
/// Tapping used to clear the tick outright, which made a stray thumb enough
/// to lose a record. Now it opens this: everything known about that entry,
/// with changing it or clearing it as deliberate choices.
///
/// [readOnly] is for a mentor looking at a student — same detail, no buttons,
/// because the record is the student's to change.
Future<TickAction?> showTickDetail(
  BuildContext context, {
  required TrackerItem item,
  required DateTime day,
  required TrackerLog log,
  int? dayNumber,
  bool readOnly = false,
}) {
  return showAppSheet<TickAction>(
    context,
    builder: (_) => _TickDetailSheet(
      item: item,
      day: day,
      log: log,
      dayNumber: dayNumber,
      readOnly: readOnly,
    ),
  );
}

class _TickDetailSheet extends StatelessWidget {
  final TrackerItem item;
  final DateTime day;
  final TrackerLog log;
  final int? dayNumber;
  final bool readOnly;

  const _TickDetailSheet({
    required this.item,
    required this.day,
    required this.log,
    this.dayNumber,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = AppColors.swatch(item.color);
    final done = log.completedAt;
    final entered = log.recordedAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(item.name, subtitle: context.dayLabel(day)),
        const SizedBox(height: 6),

        Row(children: [
          IconBadge(emoji: item.emoji, color: color, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              TickPill(log.tickStatus, itemColor: color, lateBy: log.lateBy),
              if (dayNumber != null)
                Pill(context.tr('tr_day_n', {'n': dayNumber}), color: tk.textMuted),
              if (item.isAvoid)
                Pill(context.t('tr_kind_avoid'), color: tk.transfer, icon: Icons.block_rounded),
              if (log.recordedLater)
                Pill(context.t('tr_recorded_later'), color: tk.transfer, icon: Icons.history_rounded),
            ]),
          ),
        ]),

        const SizedBox(height: 16),
        _Row(
          icon: Icons.check_circle_outline_rounded,
          label: context.t('tr_done_at'),
          value: done == null ? '—' : '${context.dayLabel(done)} · ${context.timeOf(done)}',
          strong: true,
        ),
        _Row(
          icon: Icons.edit_calendar_outlined,
          label: context.t('tr_entered_on'),
          value: entered == null ? '—' : '${context.dayLabel(entered)} · ${context.timeOf(entered)}',
          // The pair is the point: it is what separates ticking as you go
          // from writing the week up on Friday.
          hint: log.recordedLater ? context.t('tr_recorded_later') : context.t('tr_recorded_live'),
        ),
        _Row(
          icon: Icons.schedule_rounded,
          label: context.t('tr_window'),
          value: windowText(context, item),
          hint: item.grace > 0 ? context.tr('tr_grace_n', {'n': item.grace}) : null,
        ),
        if (log.lateBy > 0)
          _Row(
            icon: Icons.running_with_errors_rounded,
            label: context.t('tr_late'),
            value: lateLabel(context, log.lateBy),
          ),

        if (!readOnly) ...[
          const SizedBox(height: 18),
          Row(children: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context, TickAction.clear),
              icon: Icon(Icons.undo_rounded, size: 18, color: tk.danger),
              label: Text(context.t('tr_clear_tick'), style: TextStyle(color: tk.danger)),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, TickAction.changeTime),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(context.t('tr_change_time')),
            ),
          ]),
        ] else ...[
          const SizedBox(height: 14),
          Text(context.t('tr_view_only'),
              style: context.tt.bodySmall?.copyWith(color: tk.textFaint)),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final bool strong;
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: tk.textFaint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
            Text(
              value,
              style: strong
                  ? context.tt.titleSmall
                  : context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (hint != null)
              Text(hint!, style: context.tt.bodySmall?.copyWith(fontSize: 11, color: tk.textFaint)),
          ]),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_models.dart';
import '../../ui/kit.dart';
import 'tracker_ui.dart';

/// Asks when a habit was actually done, before the box is ticked.
///
/// The whole point: tapping the box at 8pm for a Fajr you prayed at 5:30
/// should record 5:30. So the time is always asked for rather than assumed,
/// and the suggestion is chosen to make the common case a single tap — now
/// while the window is open, the window's own start once it has closed.
///
/// Returns the chosen moment, or null if dismissed.
Future<DateTime?> askDoneTime(
  BuildContext context, {
  required TrackerItem item,
  required DateTime day,
  DateTime? initial,
}) {
  return showAppSheet<DateTime>(
    context,
    builder: (_) => _DoneTimeSheet(
      item: item,
      day: day,
      initial: initial ?? item.suggestedTimeFor(day),
    ),
  );
}

class _DoneTimeSheet extends StatefulWidget {
  final TrackerItem item;
  final DateTime day;
  final DateTime initial;
  const _DoneTimeSheet({required this.item, required this.day, required this.initial});

  @override
  State<_DoneTimeSheet> createState() => _DoneTimeSheetState();
}

class _DoneTimeSheetState extends State<_DoneTimeSheet> {
  late DateTime _when = widget.initial;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: addDays(todayDate(), -365),
      // You cannot have done something you have not done yet.
      lastDate: todayDate(),
    );
    if (picked == null || !mounted) return;
    setState(() => _when = DateTime(picked.year, picked.month, picked.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _when.hour, minute: _when.minute),
    );
    if (picked == null || !mounted) return;
    setState(() => _when = DateTime(_when.year, _when.month, _when.day, picked.hour, picked.minute));
  }

  void _set(DateTime d) => setState(() => _when = d);

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final item = widget.item;
    final color = AppColors.swatch(item.color);
    final now = DateTime.now();

    // What this choice will be recorded as, shown live so the verdict is
    // never a surprise after the fact.
    final verdict = item.evaluate(_when);
    final isFuture = _when.isAfter(now);
    final lag = now.difference(_when).inMinutes;

    final opens = item.opensOn(widget.day);
    final closes = item.deadlineOn(widget.day);
    final sameDayAsNow = sameDay(_when, now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(
          context.t('tr_when_done'),
          subtitle: '${item.emoji} ${item.name}',
        ),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(
            child: FormFieldButton(
              icon: Icons.event_rounded,
              label: context.t('date'),
              value: context.dayLabel(_when),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FormFieldButton(
              icon: Icons.schedule_rounded,
              label: context.t('tr_time'),
              value: context.timeOf(_when),
              onTap: _pickTime,
            ),
          ),
        ]),

        const SizedBox(height: 10),
        // Shortcuts for the times people actually mean.
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (sameDayAsNow)
            ActionChip(
              avatar: const Icon(Icons.bolt_rounded, size: 16),
              label: Text(context.t('tr_just_now')),
              onPressed: () => _set(now),
            ),
          if (opens != null)
            ActionChip(
              avatar: Icon(Icons.login_rounded, size: 16, color: color),
              label: Text(context.timeOf(opens)),
              onPressed: () => _set(opens),
            ),
          if (closes != null)
            ActionChip(
              avatar: Icon(Icons.logout_rounded, size: 16, color: tk.warning),
              label: Text(context.timeOf(closes)),
              onPressed: () => _set(closes),
            ),
        ]),

        const SizedBox(height: 14),
        // Live verdict.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tk.tint(isFuture
                ? tk.danger
                : tickColor(context, verdict.status, color)),
            borderRadius: BorderRadius.circular(Radii.m),
          ),
          child: Row(children: [
            Icon(
              isFuture ? Icons.block_rounded : tickIcon(verdict.status),
              size: 18,
              color: isFuture ? tk.danger : tickColor(context, verdict.status, color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  isFuture
                      ? context.t('tr_not_yet')
                      : (verdict.status == TickStatus.overdue
                          ? lateLabel(context, verdict.lateBy)
                          : context.t('tr_on_time')),
                  style: context.tt.labelLarge?.copyWith(
                    color: isFuture ? tk.danger : tickColor(context, verdict.status, color),
                  ),
                ),
                if (!isFuture && lag > 20)
                  Text(
                    context.tr('tr_will_note_entry', {'x': context.relative(now)}),
                    style: context.tt.bodySmall?.copyWith(color: tk.textMuted),
                  ),
              ]),
            ),
          ]),
        ),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isFuture ? null : () => Navigator.pop(context, _when),
            icon: const Icon(Icons.check_rounded),
            label: Text(context.t('tr_mark_done')),
          ),
        ),
      ]),
    );
  }
}

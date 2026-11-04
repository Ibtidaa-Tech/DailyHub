import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';

/// Result wrapper so "cleared" can be told apart from "cancelled".
class Pick<T> {
  final T? value;
  const Pick(this.value);
}

class _QuickOption<T> {
  final IconData icon;
  final String label;
  final String? hint;
  final T value;
  final Color? color;
  const _QuickOption(this.icon, this.label, this.value, {this.hint, this.color});
}

Widget _optionGrid<T>(BuildContext context, List<_QuickOption<T>> options, T? current, ValueChanged<T> onPick) {
  return LayoutBuilder(builder: (context, c) {
    final cols = c.maxWidth > 460 ? 3 : 2;
    final w = (c.maxWidth - (cols - 1) * 10) / cols;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final sel = o.value == current;
        return SizedBox(
          width: w,
          child: Material(
            color: sel ? context.cs.primaryContainer : context.tokens.subtle,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPick(o.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(children: [
                  Icon(o.icon, size: 20, color: o.color ?? (sel ? context.cs.primary : context.tokens.textMuted)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
                      if (o.hint != null)
                        Text(o.hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  });
}

/// Quick day picker: Today, Tomorrow, Weekend, Next week, No date, calendar.
Future<Pick<DateTime>?> pickDay(BuildContext context, {DateTime? initial, bool allowNone = true, String? title}) {
  final now = DateTime.now();
  final t0 = DateTime(now.year, now.month, now.day);
  final sat = addDays(t0, (6 - now.weekday + 7) % 7);
  final nextMon = addDays(t0, 8 - now.weekday);
  final opts = <_QuickOption<DateTime?>>[
    _QuickOption(Icons.today_rounded, context.t('today'), t0, hint: context.fmtDate(t0, 'EEE'), color: AppColors.success),
    _QuickOption(Icons.wb_sunny_outlined, context.t('tomorrow'), addDays(t0, 1),
        hint: context.fmtDate(addDays(t0, 1), 'EEE'), color: AppColors.warning),
    _QuickOption(Icons.weekend_outlined, context.t('this_weekend'), sat, hint: context.fmtDate(sat, 'EEE, d MMM'), color: AppColors.mCalendar),
    _QuickOption(Icons.next_week_outlined, context.t('next_week'), nextMon,
        hint: context.fmtDate(nextMon, 'EEE, d MMM'), color: AppColors.mTasks),
    if (allowNone) _QuickOption(Icons.block_rounded, context.t('no_date'), null),
  ];
  return showAppSheet<Pick<DateTime>>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(title ?? ctx.t('pick_date')),
          _optionGrid<DateTime?>(ctx, opts, initial == null ? null : dateOnly(initial), (v) => Navigator.pop(ctx, Pick<DateTime>(v))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(ctx.t('pick_from_calendar')),
            onPressed: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: initial ?? t0,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null && ctx.mounted) Navigator.pop(ctx, Pick<DateTime>(d));
            },
          ),
        ]),
      ),
    );
  });
}

/// Quick time picker with presets.
Future<Pick<TimeOfDay>?> pickTime(BuildContext context, {TimeOfDay? initial, bool allowNone = true}) {
  final opts = <_QuickOption<String?>>[
    _QuickOption(Icons.wb_twilight_rounded, context.t('morning'), '09:00', hint: context.timeOfHm('09:00')),
    _QuickOption(Icons.light_mode_outlined, context.t('noon'), '12:00', hint: context.timeOfHm('12:00')),
    _QuickOption(Icons.wb_sunny_outlined, context.t('afternoon'), '15:00', hint: context.timeOfHm('15:00')),
    _QuickOption(Icons.wb_cloudy_outlined, context.t('evening'), '18:00', hint: context.timeOfHm('18:00')),
    _QuickOption(Icons.nightlight_outlined, context.t('night'), '21:00', hint: context.timeOfHm('21:00')),
    if (allowNone) _QuickOption(Icons.block_rounded, context.t('no_time'), null),
  ];
  final cur = initial == null ? null : hmKey(initial.hour, initial.minute);
  return showAppSheet<Pick<TimeOfDay>>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('pick_time')),
          _optionGrid<String?>(ctx, opts, cur, (v) => Navigator.pop(ctx, Pick<TimeOfDay>(parseHm(v)))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule_rounded),
            label: Text(ctx.t('custom_time')),
            onPressed: () async {
              final t = await showTimePicker(
                context: ctx,
                initialTime: initial ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
              );
              if (t != null && ctx.mounted) Navigator.pop(ctx, Pick<TimeOfDay>(t));
            },
          ),
        ]),
      ),
    );
  });
}

/// Picks a full date + time in two quick steps (used by reminders).
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final inOneHour = now.add(const Duration(hours: 1));
  final options = <(String, DateTime)>[
    (context.t('in_1_hour'), inOneHour),
    (context.t('in_3_hours'), now.add(const Duration(hours: 3))),
    (context.t('tonight'), DateTime(now.year, now.month, now.day, 21)),
    (context.t('tomorrow_morning'), DateTime(now.year, now.month, now.day + 1, 9)),
    (context.t('tomorrow_evening'), DateTime(now.year, now.month, now.day + 1, 18)),
    (context.t('next_week'), DateTime(now.year, now.month, now.day + (8 - now.weekday), 9)),
  ].where((o) => o.$2.isAfter(now)).toList();
  final r = await showAppSheet<Object>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('when')),
          _optionGrid<DateTime>(
            ctx,
            options
                .map((o) => _QuickOption<DateTime>(Icons.schedule_rounded, o.$1, o.$2,
                    hint: ctx.dayTimeLabel(o.$2)))
                .toList(),
            null,
            (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_calendar_rounded),
            label: Text(ctx.t('pick_date_time')),
            onPressed: () => Navigator.pop(ctx, 'custom'),
          ),
        ]),
      ),
    );
  });
  if (r is DateTime) return r;
  if (r != 'custom' || !context.mounted) return null;
  final base = initial ?? inOneHour;
  final minDate = DateTime(now.year - 1);
  final d = await showDatePicker(
    context: context,
    initialDate: base,
    // showDatePicker asserts initialDate >= firstDate; old reminders may predate the window.
    firstDate: base.isBefore(minDate) ? base : minDate,
    lastDate: DateTime(2100),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// Repeat rule.
Future<String?> pickRepeat(BuildContext context, String current, {bool once = false}) {
  final opts = <_QuickOption<String>>[
    _QuickOption(Icons.block_rounded, context.t(once ? 'rep_once' : 'rep_none'), once ? 'once' : 'none'),
    _QuickOption(Icons.today_rounded, context.t('rep_daily'), 'daily'),
    _QuickOption(Icons.work_outline_rounded, context.t('rep_weekdays'), 'weekdays'),
    _QuickOption(Icons.view_week_outlined, context.t('rep_weekly'), 'weekly'),
    _QuickOption(Icons.calendar_view_month_rounded, context.t('rep_monthly'), 'monthly'),
    _QuickOption(Icons.cake_outlined, context.t('rep_yearly'), 'yearly'),
  ];
  return showAppSheet<String>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('repeat')),
          _optionGrid<String>(ctx, opts, current, (v) => Navigator.pop(ctx, v)),
        ]),
      ),
    );
  });
}

String repeatLabel(BuildContext context, String r) => switch (r) {
      'daily' => context.t('rep_daily'),
      'weekdays' => context.t('rep_weekdays'),
      'weekly' => context.t('rep_weekly'),
      'monthly' => context.t('rep_monthly'),
      'quarterly' => context.t('rep_quarterly'),
      'yearly' => context.t('rep_yearly'),
      'once' => context.t('rep_once'),
      _ => context.t('rep_none'),
    };

/// Reminder offset before a task's due time.
Future<int?> pickRemind(BuildContext context, int current) {
  final opts = <_QuickOption<int>>[
    _QuickOption(Icons.notifications_active_outlined, context.t('remind_at_time'), 0),
    _QuickOption(Icons.timer_outlined, context.tr('remind_min_before', {'n': 10}), 10),
    _QuickOption(Icons.timer_outlined, context.tr('remind_min_before', {'n': 30}), 30),
    _QuickOption(Icons.hourglass_top_rounded, context.t('remind_1h_before'), 60),
    _QuickOption(Icons.event_rounded, context.t('remind_1d_before'), 1440),
    _QuickOption(Icons.notifications_off_outlined, context.t('remind_off'), -1),
  ];
  return showAppSheet<int>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('reminder')),
          _optionGrid<int>(ctx, opts, current, (v) => Navigator.pop(ctx, v)),
        ]),
      ),
    );
  });
}

String remindLabel(BuildContext context, int m) {
  if (m < 0) return context.t('remind_off');
  if (m == 0) return context.t('remind_at_time');
  if (m == 60) return context.t('remind_1h_before');
  if (m == 1440) return context.t('remind_1d_before');
  return context.tr('remind_min_before', {'n': m});
}

/// Priority flag.
Future<String?> pickPriority(BuildContext context, String current) {
  final opts = <_QuickOption<String>>[
    _QuickOption(Icons.flag_rounded, context.t('prio_high'), Prio.high, color: Prio.color(Prio.high)),
    _QuickOption(Icons.flag_rounded, context.t('prio_medium'), Prio.medium, color: Prio.color(Prio.medium)),
    _QuickOption(Icons.flag_rounded, context.t('prio_low'), Prio.low, color: Prio.color(Prio.low)),
    _QuickOption(Icons.outlined_flag_rounded, context.t('prio_none'), Prio.none),
  ];
  return showAppSheet<String>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('priority')),
          _optionGrid<String>(ctx, opts, current, (v) => Navigator.pop(ctx, v)),
        ]),
      ),
    );
  });
}

String prioLabel(BuildContext context, String p) => switch (p) {
      Prio.high => context.t('prio_high'),
      Prio.medium => context.t('prio_medium'),
      Prio.low => context.t('prio_low'),
      _ => context.t('prio_none'),
    };

/// List picker (with "new list").
Future<Pick<String>?> pickList(BuildContext context, String current) {
  final store = context.read<PlanStore>();
  return showAppSheet<Pick<String>>(context, builder: (ctx) {
    return SafeArea(
      // Scrollable: the number of lists is unbounded.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(ctx.t('move_to_list')),
          ListTile(
            leading: const Icon(Icons.inbox_rounded),
            title: Text(ctx.t('inbox')),
            trailing: current.isEmpty ? Icon(Icons.check_rounded, color: ctx.cs.primary) : null,
            onTap: () => Navigator.pop(ctx, const Pick<String>('')),
          ),
          for (final l in store.lists)
            ListTile(
              leading: Text(l.emoji, style: const TextStyle(fontSize: 20)),
              title: Text(l.name),
              trailing: current == l.id ? Icon(Icons.check_rounded, color: ctx.cs.primary) : null,
              onTap: () => Navigator.pop(ctx, Pick<String>(l.id)),
            ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: ctx.cs.primary),
            title: Text(ctx.t('new_list'), style: TextStyle(color: ctx.cs.primary, fontWeight: FontWeight.w700)),
            onTap: () async {
              final name = await promptText(ctx, title: ctx.t('new_list'), hint: ctx.t('list_name_hint'));
              if (name == null || name.trim().isEmpty) return;
              final id = store.saveList(TaskList(name: name.trim(), color: store.lists.length));
              if (ctx.mounted) Navigator.pop(ctx, Pick<String>(id));
            },
          ),
        ]),
      ),
    );
  });
}

/// Tag picker: toggle existing tags, add new ones.
Future<List<String>?> pickTags(BuildContext context, List<String> current) {
  final store = context.read<PlanStore>();
  final selected = {...current};
  final all = {...store.tags, ...current}.toList()..sort();
  final c = TextEditingController();
  return showAppSheet<List<String>>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      void add() {
        final v = c.text.trim().replaceAll('#', '').replaceAll(' ', '_');
        if (v.isEmpty) return;
        set(() {
          if (!all.contains(v)) all.add(v);
          selected.add(v);
          c.clear();
        });
      }

      return SafeArea(
        // Scrollable: many tags (plus the keyboard) can exceed the sheet height.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(ctx.t('tags'), actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, selected.toList()), child: Text(ctx.t('done'))),
            ]),
            TextField(
              controller: c,
              decoration: InputDecoration(
                hintText: ctx.t('add_tag_hint'),
                prefixIcon: const Icon(Icons.tag_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: add),
              ),
              onSubmitted: (_) => add(),
            ),
            const SizedBox(height: 12),
            if (all.isEmpty)
              Text(ctx.t('no_tags_yet'), style: ctx.tt.bodySmall)
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in all)
                  FilterChip(
                    label: Text('#$t'),
                    selected: selected.contains(t),
                    onSelected: (v) => set(() => v ? selected.add(t) : selected.remove(t)),
                  ),
              ]),
          ]),
        ),
      );
    });
  });
}

/// Reschedule / delete quick actions (used by swipe-left).
Future<String?> taskQuickActions(BuildContext context) {
  return showAppSheet<String>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(ctx.t('reschedule')),
          OptionTile(icon: Icons.today_rounded, color: AppColors.success, title: ctx.t('today'), onTap: () => Navigator.pop(ctx, 'today')),
          OptionTile(icon: Icons.wb_sunny_outlined, color: AppColors.warning, title: ctx.t('tomorrow'), onTap: () => Navigator.pop(ctx, 'tomorrow')),
          OptionTile(icon: Icons.next_week_outlined, color: AppColors.mTasks, title: ctx.t('next_week'), onTap: () => Navigator.pop(ctx, 'nextweek')),
          OptionTile(icon: Icons.calendar_month_rounded, title: ctx.t('pick_date'), onTap: () => Navigator.pop(ctx, 'pick')),
          const Divider(),
          OptionTile(icon: Icons.delete_outline_rounded, title: ctx.t('delete'), destructive: true, onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
  });
}

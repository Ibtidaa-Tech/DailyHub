import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/agenda.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import 'pickers.dart';
import 'reminder_editor.dart';
import 'task_editor.dart';

/// Completes a task with haptic + undo toast.
void completeTaskWithUndo(BuildContext context, Task t) {
  final store = context.read<PlanStore>();
  final before = store.toggleTask(t);
  if (t.isDone) return;
  final msg = t.repeat != 'none' && t.dueDate != null ? context.t('task_done_next') : context.t('task_done');
  showUndo(context, msg, () => store.restoreTask(t.id, before));
}

/// Swipe-left menu for a task.
Future<void> taskSwipeMenu(BuildContext context, Task t) async {
  final store = context.read<PlanStore>();
  final a = await taskQuickActions(context);
  if (a == null || !context.mounted) return;
  final t0 = todayDate();
  switch (a) {
    case 'today':
      store.reschedule(t, t0);
      break;
    case 'tomorrow':
      store.reschedule(t, addDays(t0, 1));
      break;
    case 'nextweek':
      store.reschedule(t, addDays(t0, 8 - t0.weekday));
      break;
    case 'pick':
      final r = await pickDay(context, initial: t.dueDate);
      if (r != null) store.reschedule(t, r.value);
      break;
    case 'delete':
      final data = store.deleteTask(t);
      if (context.mounted) {
        showUndo(context, context.t('task_deleted'), () => store.restoreTask(t.id, data));
      }
      break;
  }
}

/// A task row: check circle, title, meta chips. Swipe right to complete,
/// swipe left for reschedule/delete. Tap to edit.
class TaskTile extends StatelessWidget {
  final Task task;
  final bool showDate;
  final bool dense;
  const TaskTile({super.key, required this.task, this.showDate = true, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>();
    final store = context.read<PlanStore>();
    final tk = context.tokens;
    final t = task;
    final overdue = t.isOverdue();
    final list = t.list.isEmpty ? null : store.listById(t.list);
    final meta = <Widget>[
      if (showDate && t.dueDate != null)
        MetaChip(
          overdue ? Icons.error_outline_rounded : Icons.event_rounded,
          t.hasTime ? context.dayTimeLabel(t.due!) : context.dayLabel(t.dueDate!),
          color: overdue ? tk.danger : null,
        )
      else if (t.hasTime)
        MetaChip(Icons.schedule_rounded, context.timeOfHm(t.time), color: overdue ? tk.danger : null),
      if (t.repeat != 'none') MetaChip(Icons.repeat_rounded, repeatLabel(context, t.repeat)),
      if (t.subtasks.isNotEmpty) MetaChip(Icons.checklist_rounded, '${t.subDone}/${t.subtasks.length}'),
      if (list != null) MetaChip(Icons.folder_outlined, '${list.emoji} ${list.name}'),
      for (final tag in t.tags.take(3)) MetaChip(Icons.tag_rounded, tag),
      if (t.desc.isNotEmpty) Icon(Icons.notes_rounded, size: 14, color: tk.textFaint),
    ];

    final tile = Material(
      color: tk.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        side: BorderSide(color: tk.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openTaskEditor(context, task: t),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, dense ? 4 : 8, 14, dense ? 4 : 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            CheckDot(
              checked: t.isDone,
              color: Prio.color(t.priority),
              onTap: ws.canAdd ? () => completeTaskWithUndo(context, t) : null,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: t.isDone ? TextDecoration.lineThrough : null,
                    color: t.isDone ? tk.textFaint : null,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
                ],
              ]),
            ),
            if (t.priority == Prio.high && !t.isDone)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.flag_rounded, size: 16, color: Prio.color(Prio.high)),
              ),
          ]),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: !ws.canAdd
          ? tile
          : SwipeTile(
              swipeKey: ValueKey('task_${t.id}_${t.status}_${t.date}'),
              rightIcon: t.isDone ? Icons.undo_rounded : Icons.check_rounded,
              rightColor: tk.success,
              rightLabel: context.t(t.isDone ? 'reopen' : 'done'),
              onSwipeRight: () async {
                completeTaskWithUndo(context, t);
                return false;
              },
              leftIcon: Icons.event_repeat_rounded,
              leftColor: AppColors.mCalendar,
              leftLabel: context.t('reschedule'),
              onSwipeLeft: () async {
                await taskSwipeMenu(context, t);
                return false;
              },
              child: tile,
            ),
    );
  }
}

/// A reminder row.
class ReminderTile extends StatelessWidget {
  final Reminder reminder;
  final bool showDate;
  final DateTime? occurrence;
  const ReminderTile({super.key, required this.reminder, this.showDate = true, this.occurrence});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final r = reminder;
    final store = context.read<PlanStore>();
    final when = occurrence ?? r.when;
    final overdue = r.isOverdue() && !r.repeats;
    final tile = DhCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: () => openReminderEditor(context, reminder: r),
      child: Row(children: [
        IconBadge(
          icon: r.done ? Icons.notifications_off_outlined : Icons.notifications_active_rounded,
          color: r.done ? tk.textFaint : AppColors.mReminders,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: r.done ? TextDecoration.lineThrough : null,
                  color: r.done ? tk.textFaint : null,
                )),
            const SizedBox(height: 3),
            Wrap(spacing: 10, children: [
              if (when != null)
                MetaChip(
                  Icons.schedule_rounded,
                  showDate ? context.dayTimeLabel(when) : context.timeOf(when),
                  color: overdue ? tk.danger : null,
                ),
              if (r.repeats) MetaChip(Icons.repeat_rounded, repeatLabel(context, r.repeat)),
            ]),
          ]),
        ),
        IconButton(
          tooltip: context.t(r.repeats ? 'done_for_now' : 'done'),
          icon: Icon(r.done ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
              color: r.done ? tk.success : tk.textMuted),
          onPressed: () {
            final before = store.completeReminder(r);
            showUndo(context, context.t(r.repeats ? 'reminder_next' : 'reminder_done'),
                () => store.restoreReminder(r.id, before));
          },
        ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SwipeTile(
        swipeKey: ValueKey('rem_${r.id}_${r.when?.toIso8601String()}_${r.done}'),
        rightIcon: Icons.check_rounded,
        rightColor: tk.success,
        rightLabel: context.t('done'),
        onSwipeRight: () async {
          final before = store.completeReminder(r);
          showUndo(context, context.t(r.repeats ? 'reminder_next' : 'reminder_done'),
              () => store.restoreReminder(r.id, before));
          return false;
        },
        leftIcon: Icons.snooze_rounded,
        leftColor: AppColors.mReminders,
        leftLabel: context.t('snooze'),
        onSwipeLeft: () async {
          final choice = await showAppSheet<Duration>(context, builder: (ctx) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SheetHeader(ctx.t('snooze')),
                  for (final d in const [Duration(minutes: 10), Duration(hours: 1), Duration(hours: 3), Duration(days: 1)])
                    OptionTile(
                      icon: Icons.snooze_rounded,
                      title: ctx.tr('in_x', {'x': d.inDays >= 1 ? ctx.tr('dur_day', {'n': d.inDays}) : d.inHours >= 1 ? ctx.tr('dur_hour', {'n': d.inHours}) : ctx.tr('dur_min', {'n': d.inMinutes})}),
                      onTap: () => Navigator.pop(ctx, d),
                    ),
                ]),
              ),
            );
          });
          if (choice != null) {
            store.snoozeReminder(r, choice);
            if (context.mounted) showToast(context, context.t('snoozed'), icon: Icons.snooze_rounded);
          }
          return false;
        },
        child: tile,
      ),
    );
  }
}

/// Non-task agenda rows (meeting, class, trip, bill…).
class EventTile extends StatelessWidget {
  final AgendaItem item;
  final VoidCallback? onTap;
  const EventTile({super.key, required this.item, this.onTap});

  String _kindLabel(BuildContext context) => switch (item.kind) {
        AgendaKind.bill => context.t('k_bill'),
        AgendaKind.meeting => context.t('k_meeting'),
        AgendaKind.lecture => context.t('k_class'),
        AgendaKind.assignment => context.t('k_assignment'),
        AgendaKind.trip => context.t('k_trip'),
        AgendaKind.delivery => context.t('k_delivery'),
        AgendaKind.countdown => context.t('k_countdown'),
        AgendaKind.reminder => context.t('reminder'),
        AgendaKind.task => context.t('task'),
      };

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DhCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: onTap,
        child: Row(children: [
          IconBadge(icon: item.icon, color: item.color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                [_kindLabel(context), if (item.time != null) context.timeOf(item.time!), if (item.subtitle.isNotEmpty) item.subtitle]
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodySmall,
              ),
            ]),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: tk.textFaint),
        ]),
      ),
    );
  }
}

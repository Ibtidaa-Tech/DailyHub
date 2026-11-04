import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import 'plan_tiles.dart';
import 'reminder_editor.dart';

/// All reminders: upcoming, repeating, and done.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final active = plan.activeReminders;
    final oneOff = active.where((r) => !r.repeats).toList();
    final repeating = active.where((r) => r.repeats).toList();
    final done = plan.reminders.where((r) => r.done).toList();
    return AppPage(
      title: context.t('m_reminders'),
      subtitle: context.t('reminders_sub'),
      fab: FloatingActionButton.extended(
        onPressed: () => openReminderEditor(context),
        icon: const Icon(Icons.add_alert_rounded),
        label: Text(context.t('new_reminder')),
      ),
      slivers: [
        if (active.isEmpty && done.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.notifications_active_rounded,
              color: AppColors.mReminders,
              title: context.t('no_reminders'),
              message: context.t('no_reminders_msg'),
              actionLabel: context.t('new_reminder'),
              onAction: () => openReminderEditor(context),
            ),
          ),
        if (oneOff.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('upcoming'))),
          SliverList.list(children: [for (final r in oneOff) ReminderTile(reminder: r)]),
        ],
        if (repeating.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('repeating'))),
          SliverList.list(children: [for (final r in repeating) ReminderTile(reminder: r)]),
        ],
        if (done.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionTitle(
              '${context.t('done')} · ${done.length}',
              action: context.t(_showDone ? 'hide' : 'show'),
              onAction: () => setState(() => _showDone = !_showDone),
            ),
          ),
          if (_showDone) SliverList.list(children: [for (final r in done) ReminderTile(reminder: r)]),
        ],
      ],
    );
  }
}

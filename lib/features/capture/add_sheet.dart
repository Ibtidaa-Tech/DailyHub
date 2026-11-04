import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/life_store.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/plan_store.dart';
import '../../core/workspace_provider.dart';
import '../../screens/countdown_screen.dart';
import '../../screens/journal_screen.dart';
import '../shopping/shopping_screen.dart';
import '../trips/trips_screen.dart';
import '../work/work_screen.dart';
import '../../ui/kit.dart';
import '../habits/habits_screen.dart';
import '../money/bills_screen.dart';
import '../money/ledger_screen.dart';
import '../money/txn_editor.dart';
import '../notes/note_editor.dart';
import '../plan/reminder_editor.dart';
import '../plan/task_editor.dart';
import 'capture.dart';

class _AddOption {
  final String id;
  final IconData icon;
  final Color color;
  final String labelKey;
  final void Function(BuildContext root) open;
  const _AddOption(this.id, this.icon, this.color, this.labelKey, this.open);
}

/// The centre "+": type anything, or pick exactly what to create.
Future<void> showAddSheet(BuildContext context) {
  final plan = context.read<PlanStore>();
  final money = context.read<MoneyStore>();
  final notes = context.read<NotesStore>();
  final habits = context.read<HabitsStore>();
  final settings = context.read<AppSettings>();
  final ws = context.read<WorkspaceProvider>();
  final root = context;

  final options = <_AddOption>[
    _AddOption('task', Icons.check_circle_rounded, AppColors.mTasks, 'task', (c) => openTaskEditor(c)),
    if (settings.isOn('reminders'))
      _AddOption('reminder', Icons.notifications_active_rounded, AppColors.mReminders, 'reminder', (c) => openReminderEditor(c)),
    if (settings.isOn('money')) ...[
      _AddOption('spent', Icons.north_east_rounded, AppColors.expense, 'spent', (c) => openTxnEditor(c, type: TxnType.expense)),
      _AddOption('earned', Icons.south_west_rounded, AppColors.income, 'earned', (c) => openTxnEditor(c, type: TxnType.income)),
    ],
    if (settings.isOn('notes')) ...[
      _AddOption('note', Icons.sticky_note_2_rounded, AppColors.mNotes, 'note', (c) => openNoteEditor(c)),
      _AddOption('checklist', Icons.checklist_rounded, AppColors.mNotes, 'checklist', (c) => openNoteEditor(c, checklist: true)),
    ],
    if (settings.isOn('habits'))
      _AddOption('habit', Icons.local_fire_department_rounded, AppColors.mHabits, 'habit', (c) => openHabitEditor(c)),
    if (settings.isOn('money')) ...[
      _AddOption('bill', Icons.receipt_long_rounded, AppColors.mReminders, 'bill', (c) => BillsScreen.editBill(c)),
      _AddOption('lend', Icons.handshake_rounded, AppColors.mJournal, 'lend_borrow', (c) => LedgerScreen.editDebt(c)),
      _AddOption('transfer', Icons.swap_horiz_rounded, AppColors.transfer, 'transfer', (c) => openTxnEditor(c, type: TxnType.transfer)),
    ],
    if (settings.isOn('trips'))
      _AddOption('trip', Icons.flight_takeoff_rounded, AppColors.mTrips, 'k_trip',
          (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const TripsScreen()))),
    if (settings.isOn('shopping'))
      _AddOption('shopping', Icons.shopping_cart_rounded, AppColors.mShopping, 'm_shopping',
          (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ShoppingScreen()))),
    if (settings.isOn('work'))
      _AddOption('meeting', Icons.groups_rounded, AppColors.mWork, 'k_meeting',
          (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const WorkScreen()))),
    if (settings.isOn('countdowns'))
      _AddOption('countdown', Icons.hourglass_bottom_rounded, AppColors.mCountdown, 'k_countdown',
          (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const CountdownScreen()))),
    if (settings.isOn('journal'))
      _AddOption('journal', Icons.auto_stories_rounded, AppColors.mJournal, 'm_journal',
          (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const JournalScreen()))),
  ].where((o) => o.id != 'task' || ws.canAdd).toList();

  return showAppSheet(context, builder: (ctx) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: plan),
        ChangeNotifierProvider.value(value: money),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: habits),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: ws),
      ],
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t('add_anything'), style: ctx.tt.titleLarge),
            const SizedBox(height: 12),
            SmartCaptureField(autofocus: false, compact: true, onSaved: () => Navigator.pop(ctx)),
            const SizedBox(height: 18),
            Text(ctx.t('or_create').toUpperCase(),
                style: ctx.tt.labelSmall?.copyWith(color: ctx.tokens.textMuted, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 500 ? 5 : 4;
              final w = (c.maxWidth - (cols - 1) * 8) / cols;
              return Wrap(spacing: 8, runSpacing: 12, children: [
                for (final o in options)
                  SizedBox(
                    width: w,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.pop(ctx);
                        o.open(root);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(children: [
                          IconBadge(icon: o.icon, color: o.color, size: 52, radius: 16),
                          const SizedBox(height: 6),
                          Text(ctx.t(o.labelKey),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ctx.tt.labelMedium),
                        ]),
                      ),
                    ),
                  ),
              ]);
            }),
          ]),
        ),
      ),
    );
  });
}

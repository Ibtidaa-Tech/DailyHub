import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'money_ui.dart';

/// Savings goals ("₹50,000 for a laptop") with progress rings.
class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final total = m.goals.fold(0.0, (s, g) => s + g.saved);
    return AppPage(
      title: context.t('m_savings'),
      subtitle: m.goals.isEmpty ? null : context.tr('saved_total', {'a': Money.format(total)}),
      fab: FloatingActionButton.extended(
        onPressed: () => editGoal(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('new_goal')),
      ),
      slivers: [
        if (m.goals.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.savings_rounded,
              color: AppColors.mTasks,
              title: context.t('no_goals'),
              message: context.t('no_goals_msg'),
              actionLabel: context.t('new_goal'),
              onAction: () => editGoal(context),
            ),
          )
        else
          SliverList.list(children: [for (final g in m.goals) _GoalCard(goal: g)]),
      ],
    );
  }

  static Future<void> editGoal(BuildContext context, {SavingsGoal? goal}) async {
    final m = context.read<MoneyStore>();
    final g = goal == null ? SavingsGoal() : SavingsGoal.fromMap({...goal.toMap(), 'id': goal.id});
    final name = TextEditingController(text: g.name);
    final target = TextEditingController(text: g.target == 0 ? '' : g.target.toStringAsFixed(0));
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t(goal == null ? 'new_goal' : 'edit_goal'), style: ctx.tt.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ctx.t('goal_name_hint'),
                  prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(g.emoji, style: const TextStyle(fontSize: 18))),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: ctx.t('target_amount'), prefixText: '${Money.symbol} '),
              ),
              const SizedBox(height: 10),
              FormFieldButton(
                icon: Icons.flag_outlined,
                label: ctx.t('target_date_optional'),
                value: parseDay(g.deadline) == null ? ctx.t('none') : ctx.fmtDate(parseDay(g.deadline)!, 'd MMM yyyy'),
                onTap: () async {
                  final t0 = todayDate();
                  final init = parseDay(g.deadline) ?? DateTime(t0.year, t0.month + 6);
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: init,
                    // A deadline that already passed must still be a valid initialDate.
                    firstDate: init.isBefore(t0) ? init : t0,
                    lastDate: DateTime(2100),
                  );
                  if (d != null) set(() => g.deadline = dayKey(d));
                },
              ),
              const SizedBox(height: 12),
              EmojiGrid(
                value: g.emoji,
                emojis: const ['🎯', '💻', '📱', '🏍️', '🚗', '🏠', '✈️', '💍', '🎓', '🏖️', '🛋️', '📷', '🎸', '🩺', '👶', '🎁'],
                onChanged: (v) => set(() => g.emoji = v),
              ),
              const SizedBox(height: 18),
              Row(children: [
                if (goal != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: ctx.tokens.danger),
                    onPressed: () async {
                      final ok = await confirmDialog(ctx, title: ctx.t('delete_goal_q'), danger: true, confirm: ctx.t('delete'));
                      if (!ok) return;
                      m.deleteGoal(goal);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final t = double.tryParse(target.text.replaceAll(',', '').trim()) ?? 0;
                    if (name.text.trim().isEmpty || t <= 0 || !t.isFinite) {
                      showToast(ctx, ctx.t('name_and_amount'));
                      return;
                    }
                    g
                      ..name = name.text.trim()
                      ..target = t;
                    m.saveGoal(g);
                    Navigator.pop(ctx);
                  },
                  child: Text(ctx.t('save')),
                ),
              ]),
            ]),
          ),
        );
      });
    });
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  const _GoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    final m = context.read<MoneyStore>();
    final tk = context.tokens;
    final g = goal;
    final left = (g.target - g.saved).clamp(0, double.infinity).toDouble();
    final deadline = parseDay(g.deadline);
    String? perMonth;
    if (deadline != null && left > 0) {
      final now = DateTime.now();
      final months = ((deadline.year - now.year) * 12 + deadline.month - now.month).clamp(1, 1200);
      perMonth = context.tr('per_month_needed', {'a': Money.format(left / months)});
    }
    final done = g.saved >= g.target;
    return DhCard(
      onTap: () => SavingsScreen.editGoal(context, goal: g),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        ProgressRing(
          value: g.progress,
          size: 64,
          stroke: 7,
          color: done ? tk.success : AppColors.swatch(g.color),
          child: Text(g.emoji, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.name, style: context.tt.titleMedium),
            const SizedBox(height: 2),
            Text('${Money.format(g.saved)} / ${Money.format(g.target)} · ${(g.progress * 100).round()}%', style: context.tt.bodySmall),
            if (done)
              Text(context.t('goal_reached'), style: context.tt.labelMedium?.copyWith(color: tk.success))
            else if (perMonth != null)
              Text(perMonth, style: context.tt.labelMedium?.copyWith(color: context.cs.primary)),
          ]),
        ),
        Column(children: [
          IconButton.filledTonal(
            tooltip: context.t('add_money'),
            icon: const Icon(Icons.add_rounded),
            onPressed: () async {
              final v = await promptAmount(context, title: context.t('add_money'));
              if (v != null && v > 0) m.addGoalEntry(g, v);
            },
          ),
          IconButton(
            tooltip: context.t('withdraw'),
            icon: Icon(Icons.remove_rounded, color: tk.textMuted, size: 20),
            onPressed: () async {
              final v = await promptAmount(context, title: context.t('withdraw'));
              if (v != null && v > 0) m.addGoalEntry(g, -v);
            },
          ),
        ]),
      ]),
    );
  }
}

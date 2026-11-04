import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'money_ui.dart';

/// Monthly budget overall and per category, against real spending.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final month = monthKeyOf(DateTime.now());
    final spent = m.totals(month).expense;
    final total = m.monthlyBudget;
    final explicitTotal = m.budgetFor('_total');
    final catBudgets = m.budgets.where((b) => b.category != '_total').toList();
    final now = DateTime.now();
    final daysLeft = daysInMonth(now.year, now.month) - now.day + 1;

    Color colorFor(double ratio) => ratio > 1 ? tk.danger : (ratio > 0.8 ? tk.warning : tk.success);

    return AppPage(
      title: context.t('m_budgets'),
      subtitle: context.monthLabel(now),
      fab: FloatingActionButton.extended(
        onPressed: () async {
          final cat = await pickCategory(context, 'expense');
          if (cat == null || !context.mounted) return;
          final v = await promptAmount(context, title: context.t('monthly_limit'), initial: m.budgetFor(cat)?.limit);
          if (v != null) m.setBudget(cat, v);
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('category_budget')),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: DhCard(
            onTap: () async {
              final v = await promptAmount(context, title: context.t('monthly_budget'), initial: explicitTotal?.limit);
              if (v != null) m.setBudget('_total', v);
            },
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(context.t('monthly_budget'), style: context.tt.titleMedium),
                const Spacer(),
                Icon(Icons.edit_rounded, size: 18, color: tk.textMuted),
              ]),
              const SizedBox(height: 8),
              if (total <= 0)
                Text(context.t('no_budget_msg'), style: context.tt.bodyMedium?.copyWith(color: tk.textMuted))
              else ...[
                Text('${Money.format(spent)} / ${Money.format(total)}',
                    style: context.tt.headlineSmall?.copyWith(color: colorFor(spent / total))),
                const SizedBox(height: 10),
                ProgressBar(value: spent / total, color: colorFor(spent / total), height: 10),
                const SizedBox(height: 8),
                Text(
                  spent <= total
                      ? context.tr('budget_left_per_day', {'a': Money.format(total - spent), 'd': Money.format((total - spent) / daysLeft), 'n': daysLeft})
                      : context.tr('budget_over', {'a': Money.format(spent - total)}),
                  style: context.tt.bodySmall?.copyWith(color: spent > total ? tk.danger : null),
                ),
              ],
            ]),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('by_category'))),
        if (catBudgets.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.pie_chart_rounded,
              color: AppColors.mGoals,
              title: context.t('no_cat_budgets'),
              message: context.t('no_cat_budgets_msg'),
              compact: true,
            ),
          )
        else
          SliverList.list(children: [
            for (final b in catBudgets)
              Builder(builder: (context) {
                final cat = m.catById(b.category);
                final s = m.spentInCategory(month, b.category);
                final ratio = b.limit <= 0 ? 0.0 : s / b.limit;
                return DhCard(
                  onTap: () async {
                    final v = await promptAmount(context, title: categoryName(context, cat), initial: b.limit);
                    if (v != null) m.setBudget(b.category, v);
                  },
                  onLongPress: () async {
                    final ok = await confirmDialog(context, title: context.t('remove_budget_q'), danger: true, confirm: context.t('remove'));
                    if (ok) m.setBudget(b.category, 0);
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(cat?.emoji ?? '📦', style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(categoryName(context, cat), style: context.tt.titleSmall)),
                      Text('${Money.format(s)} / ${Money.format(b.limit)}',
                          style: context.tt.labelLarge?.copyWith(color: colorFor(ratio))),
                    ]),
                    const SizedBox(height: 8),
                    ProgressBar(value: ratio, color: colorFor(ratio)),
                    if (ratio > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(context.tr('budget_over', {'a': Money.format(s - b.limit)}),
                            style: context.tt.bodySmall?.copyWith(color: tk.danger)),
                      ),
                  ]),
                );
              }),
          ]),
      ],
    );
  }
}

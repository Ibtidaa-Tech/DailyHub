import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'accounts_screen.dart';
import 'bills_screen.dart';
import 'budgets_screen.dart';
import 'categories_screen.dart';
import 'ledger_screen.dart';
import 'money_ui.dart';
import 'reports_screen.dart';
import 'savings_screen.dart';
import 'txn_editor.dart';

/// Money tab: this month's Earned / Spent / Saved at a glance, one-tap
/// entry, budgets, bills, lend/borrow, goals and every transaction.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});
  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  String _month = monthKeyOf(DateTime.now());
  String _filter = 'all'; // all | expense | income | transfer
  String? _catFilter;
  String _query = '';
  bool _searching = false;

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final tot = m.totals(_month);
    final isThisMonth = _month == monthKeyOf(DateTime.now());

    var list = m.monthTxns(_month);
    if (_filter != 'all') list = list.where((t) => t.type == _filter).toList();
    if (_catFilter != null) list = list.where((t) => t.category == _catFilter).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((t) =>
              t.note.toLowerCase().contains(q) ||
              categoryName(context, m.catById(t.category)).toLowerCase().contains(q) ||
              t.amount.toString().contains(q))
          .toList();
    }

    return AppPage(
      title: context.t('tab_money'),
      subtitle: context.t('money_sub'),
      showBack: false,
      actions: [
        IconButton(
          tooltip: context.t('search'),
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _query = '';
          }),
        ),
        IconButton(
          tooltip: context.t('m_reports'),
          icon: const Icon(Icons.bar_chart_rounded),
          onPressed: () => _push(const ReportsScreen()),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            final Widget? page = switch (v) {
              'accounts' => const AccountsScreen(),
              'categories' => const CategoriesScreen(),
              'budgets' => const BudgetsScreen(),
              'bills' => const BillsScreen(),
              'ledger' => const LedgerScreen(),
              'savings' => const SavingsScreen(),
              _ => null,
            };
            if (page != null) _push(page);
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'accounts', child: Text(ctx.t('m_accounts'))),
            PopupMenuItem(value: 'categories', child: Text(ctx.t('m_categories'))),
            PopupMenuItem(value: 'budgets', child: Text(ctx.t('m_budgets'))),
            PopupMenuItem(value: 'bills', child: Text(ctx.t('m_bills'))),
            PopupMenuItem(value: 'ledger', child: Text(ctx.t('m_ledger'))),
            PopupMenuItem(value: 'savings', child: Text(ctx.t('m_savings'))),
          ],
        ),
      ],
      slivers: [
        SliverToBoxAdapter(child: MonthSwitcher(month: _month, onChanged: (v) => setState(() => _month = v))),
        SliverToBoxAdapter(child: _SummaryCard(month: _month, totals: tot, isThisMonth: isThisMonth)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: _BigAction(
                  icon: Icons.remove_rounded,
                  label: context.t('spent'),
                  color: tk.expense,
                  onTap: () => openTxnEditor(context, type: TxnType.expense),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigAction(
                  icon: Icons.add_rounded,
                  label: context.t('earned'),
                  color: tk.income,
                  onTap: () => openTxnEditor(context, type: TxnType.income),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigAction(
                  icon: Icons.swap_horiz_rounded,
                  label: context.t('transfer'),
                  color: tk.transfer,
                  onTap: () => openTxnEditor(context, type: TxnType.transfer),
                ),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: _ShortcutStrip(onOpen: _push)),
        if (tot.expense > 0) SliverToBoxAdapter(child: _Breakdown(month: _month, onPick: (c) => setState(() => _catFilter = _catFilter == c ? null : c))),
        if (tot.expense > 0) SliverToBoxAdapter(child: _DailyBars(month: _month)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_searching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(hintText: context.t('search_txns'), prefixIcon: const Icon(Icons.search_rounded)),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
              ChipRow<String>(
                items: [
                  ('all', context.t('all')),
                  (TxnType.expense, context.t('spent')),
                  (TxnType.income, context.t('earned')),
                  (TxnType.transfer, context.t('transfers')),
                ],
                value: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              if (_catFilter != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InputChip(
                    avatar: Text(m.catById(_catFilter!)?.emoji ?? '📦'),
                    label: Text(categoryName(context, m.catById(_catFilter!))),
                    onDeleted: () => setState(() => _catFilter = null),
                  ),
                ),
            ]),
          ),
        ),
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.receipt_long_rounded,
              color: AppColors.mMoney,
              title: context.t('no_txns'),
              message: context.t('no_txns_msg'),
              compact: true,
            ),
          )
        else
          SliverList.list(children: txnDayGroups(context, list)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String month;
  final MonthTotals totals;
  final bool isThisMonth;
  const _SummaryCard({required this.month, required this.totals, required this.isThisMonth});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final saved = totals.saved;
    final budget = m.monthlyBudget;
    final now = DateTime.now();
    final start = monthStart(month);
    final dim = daysInMonth(start.year, start.month);
    final daysLeft = isThisMonth ? dim - now.day + 1 : 0;
    final left = budget - totals.expense;
    return DhCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(context.t(saved >= 0 ? 'net_saved' : 'overspent'), style: context.tt.bodyMedium?.copyWith(color: tk.textMuted)),
          const Spacer(),
          if (totals.income > 0)
            Pill(context.tr('savings_rate', {'p': (totals.rate * 100).round()}),
                color: saved >= 0 ? tk.income : tk.expense),
        ]),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(Money.format(saved.abs()),
              style: context.tt.displaySmall?.copyWith(color: saved >= 0 ? tk.income : tk.expense)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: StatBlock(label: context.t('earned'), value: Money.format(totals.income), color: tk.income, icon: Icons.south_west_rounded)),
          Container(width: 1, height: 36, color: tk.border),
          const SizedBox(width: 16),
          Expanded(child: StatBlock(label: context.t('spent'), value: Money.format(totals.expense), color: tk.expense, icon: Icons.north_east_rounded)),
        ]),
        const SizedBox(height: 14),
        if (budget > 0) ...[
          ProgressBar(
            value: budget <= 0 ? 0 : totals.expense / budget,
            color: totals.expense > budget ? tk.danger : (totals.expense > budget * 0.8 ? tk.warning : tk.success),
          ),
          const SizedBox(height: 6),
          Text(
            left >= 0
                ? (daysLeft > 0
                    ? context.tr('budget_left_per_day', {'a': Money.format(left), 'd': Money.format(left / daysLeft), 'n': daysLeft})
                    : context.tr('budget_left', {'a': Money.format(left)}))
                : context.tr('budget_over', {'a': Money.format(-left)}),
            style: context.tt.bodySmall?.copyWith(color: left < 0 ? tk.danger : null),
          ),
        ] else
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsScreen())),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(Icons.pie_chart_outline_rounded, size: 16, color: context.cs.primary),
                const SizedBox(width: 6),
                Text(context.t('set_budget_cta'), style: context.tt.labelMedium?.copyWith(color: context.cs.primary)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _BigAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.tokens.tint(color),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: context.tt.labelLarge?.copyWith(color: color)),
          ]),
        ),
      ),
    );
  }
}

class _ShortcutStrip extends StatelessWidget {
  final void Function(Widget) onOpen;
  const _ShortcutStrip({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final nextBill = m.activeBills.isEmpty ? null : m.activeBills.first;
    final goal = m.goals.isEmpty ? null : m.goals.first;
    final net = m.toReceive - m.toPay;
    Widget card(IconData icon, Color color, String title, String value, String? sub, Widget page) => SizedBox(
          width: 158,
          child: DhCard(
            margin: const EdgeInsets.only(right: 10, top: 6, bottom: 6),
            padding: const EdgeInsets.all(14),
            onTap: () => onOpen(page),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(icon: icon, color: color, size: 32, radius: 10),
              const SizedBox(height: 10),
              Text(title, style: context.tt.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: context.tt.titleMedium),
              ),
              if (sub != null)
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(fontSize: 11)),
            ]),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(children: [
        card(Icons.account_balance_rounded, AppColors.mMoney, context.t('balance'), Money.format(m.netWorth),
            context.tn('n_accounts', m.activeAccounts.length), const AccountsScreen()),
        card(
          Icons.receipt_long_rounded,
          AppColors.mReminders,
          context.t('m_bills'),
          nextBill == null ? '—' : Money.format(nextBill.amount),
          nextBill == null
              ? context.t('add_bills_cta')
              : '${nextBill.name} · ${nextBill.daysLeft() < 0 ? context.t('overdue') : context.tn('in_days', nextBill.daysLeft())}',
          const BillsScreen(),
        ),
        card(
          Icons.handshake_rounded,
          AppColors.mJournal,
          context.t('m_ledger'),
          net == 0 ? '—' : Money.format(net.abs()),
          net > 0 ? context.t('you_will_get') : (net < 0 ? context.t('you_owe') : context.t('all_settled')),
          const LedgerScreen(),
        ),
        card(
          Icons.savings_rounded,
          AppColors.mTasks,
          context.t('m_savings'),
          goal == null ? '—' : '${(goal.progress * 100).round()}%',
          goal?.name ?? context.t('add_goal_cta'),
          const SavingsScreen(),
        ),
      ]),
    );
  }
}

class _Breakdown extends StatelessWidget {
  final String month;
  final ValueChanged<String> onPick;
  const _Breakdown({required this.month, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final items = m.byCategory(month, TxnType.expense);
    final total = items.fold(0.0, (s, e) => s + e.amount);
    final top = items.take(6).toList();
    final other = items.skip(6).fold(0.0, (s, e) => s + e.amount);
    final values = [...top.map((e) => e.amount), if (other > 0) other];
    final colors = [...top.map((e) => categoryColor(e.category)), if (other > 0) context.tokens.textFaint];
    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.t('where_money_went'), style: context.tt.titleMedium),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final donut = Donut(
            values: values,
            colors: colors,
            size: 132,
            stroke: 18,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.t('spent'), style: context.tt.bodySmall),
              FittedBox(child: Text(Money.format(total, compact: true), style: context.tt.titleSmall)),
            ]),
          );
          final legend = Column(children: [
            for (final e in top)
              InkWell(
                onTap: () => onPick(e.category.id),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Text(e.category.emoji),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(categoryName(context, e.category),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelMedium),
                          ),
                          Text(Money.format(e.amount), style: context.tt.labelMedium),
                        ]),
                        const SizedBox(height: 3),
                        ProgressBar(value: total == 0 ? 0 : e.amount / total, color: categoryColor(e.category), height: 5),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]);
          if (c.maxWidth < 380) return Column(children: [Center(child: donut), const SizedBox(height: 14), legend]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            donut,
            const SizedBox(width: 18),
            Expanded(child: legend),
          ]);
        }),
      ]),
    );
  }
}

class _DailyBars extends StatelessWidget {
  final String month;
  const _DailyBars({required this.month});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final vals = m.dailyExpense(month);
    final now = DateTime.now();
    final isThis = month == monthKeyOf(now);
    final shown = isThis ? vals.sublist(0, now.day.clamp(1, vals.length)) : vals;
    final avg = shown.isEmpty ? 0.0 : shown.fold(0.0, (s, v) => s + v) / shown.length;
    final peak = shown.isEmpty ? 0.0 : shown.reduce((a, b) => a > b ? a : b);
    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(context.t('daily_spending'), style: context.tt.titleMedium),
          const Spacer(),
          Text(context.tr('avg_per_day', {'a': Money.format(avg)}), style: context.tt.bodySmall),
        ]),
        const SizedBox(height: 14),
        MiniBars(
          values: vals,
          color: context.tokens.expense,
          highlight: isThis ? now.day - 1 : null,
          height: 90,
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('1', style: context.tt.bodySmall),
          const Spacer(),
          Text(context.tr('peak_day', {'a': Money.format(peak)}), style: context.tt.bodySmall),
          const Spacer(),
          Text('${vals.length}', style: context.tt.bodySmall),
        ]),
      ]),
    );
  }
}

/// Used by Home: this month's snapshot with quick buttons.
class MoneySnapshot extends StatelessWidget {
  final VoidCallback? onOpen;
  const MoneySnapshot({super.key, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final month = monthKeyOf(DateTime.now());
    final tot = m.totals(month);
    final budget = m.monthlyBudget;
    final today = m.spentOn(DateTime.now());
    return DhCard(
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(icon: Icons.account_balance_wallet_rounded, color: AppColors.mMoney, size: 32, radius: 10),
          const SizedBox(width: 10),
          Expanded(child: Text(context.t('this_month'), style: context.tt.titleMedium)),
          Text('${context.t('today')}: ${Money.format(today)}', style: context.tt.bodySmall),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: StatBlock(label: context.t('earned'), value: Money.format(tot.income, compact: true), color: tk.income)),
          Expanded(child: StatBlock(label: context.t('spent'), value: Money.format(tot.expense, compact: true), color: tk.expense)),
          Expanded(
            child: StatBlock(
              label: context.t(tot.saved >= 0 ? 'net_saved' : 'overspent'),
              value: Money.format(tot.saved.abs(), compact: true),
              color: tot.saved >= 0 ? tk.income : tk.expense,
            ),
          ),
        ]),
        if (budget > 0) ...[
          const SizedBox(height: 12),
          ProgressBar(
            value: tot.expense / budget,
            color: tot.expense > budget ? tk.danger : (tot.expense > budget * 0.8 ? tk.warning : tk.success),
            height: 6,
          ),
          const SizedBox(height: 4),
          Text(context.tr('of_budget', {'a': Money.format(tot.expense), 'b': Money.format(budget)}), style: context.tt.bodySmall),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: tk.expense, minimumSize: const Size(0, 42)),
              onPressed: () => openTxnEditor(context, type: TxnType.expense),
              icon: const Icon(Icons.remove_rounded, size: 18),
              label: Text(context.t('spent')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: tk.income, minimumSize: const Size(0, 42)),
              onPressed: () => openTxnEditor(context, type: TxnType.income),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.t('earned')),
            ),
          ),
        ]),
      ]),
    );
  }
}

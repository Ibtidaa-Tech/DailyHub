import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import '../plan/pickers.dart';
import 'money_ui.dart';

/// Recurring bills, subscriptions and regular income (salary).
class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final bills = m.activeBills;
    final paused = m.bills.where((b) => !b.active).toList();
    final monthly = bills.where((b) => b.type == TxnType.expense).fold(0.0, (s, b) => s + _monthlyCost(b));
    final overdue = bills.where((b) => b.daysLeft() < 0).toList();
    final soon = bills.where((b) => b.daysLeft() >= 0 && b.daysLeft() <= 7).toList();
    final later = bills.where((b) => b.daysLeft() > 7).toList();

    return AppPage(
      title: context.t('m_bills'),
      subtitle: context.t('bills_sub'),
      fab: FloatingActionButton.extended(
        onPressed: () => editBill(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('add_bill')),
      ),
      slivers: [
        if (bills.isNotEmpty)
          SliverToBoxAdapter(
            child: DhCard(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(child: StatBlock(label: context.t('per_month'), value: Money.format(monthly), color: tk.expense)),
                Expanded(child: StatBlock(label: context.t('due_this_week'), value: '${soon.length + overdue.length}')),
                Expanded(child: StatBlock(label: context.t('overdue'), value: '${overdue.length}', color: overdue.isEmpty ? null : tk.danger)),
              ]),
            ),
          ),
        if (bills.isEmpty && paused.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.receipt_long_rounded,
              color: AppColors.mReminders,
              title: context.t('no_bills'),
              message: context.t('no_bills_msg'),
              actionLabel: context.t('add_bill'),
              onAction: () => editBill(context),
            ),
          ),
        if (overdue.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('overdue'))),
          SliverList.list(children: [for (final b in overdue) _BillRow(bill: b)]),
        ],
        if (soon.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('next_7_days'))),
          SliverList.list(children: [for (final b in soon) _BillRow(bill: b)]),
        ],
        if (later.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('later'))),
          SliverList.list(children: [for (final b in later) _BillRow(bill: b)]),
        ],
        if (paused.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('paused'))),
          SliverList.list(children: [for (final b in paused) _BillRow(bill: b)]),
        ],
      ],
    );
  }

  static double _monthlyCost(Bill b) => switch (b.freq) {
        'weekly' => b.amount * 52 / 12,
        'quarterly' => b.amount / 3,
        'yearly' => b.amount / 12,
        _ => b.amount,
      };

  static const presets = [
    ('🏠', 'preset_rent', 'rent', 'monthly'),
    ('💡', 'preset_electricity', 'bills', 'monthly'),
    ('📱', 'preset_mobile', 'bills', 'monthly'),
    ('🌐', 'preset_internet', 'bills', 'monthly'),
    ('📺', 'preset_ott', 'subscriptions', 'monthly'),
    ('🏦', 'preset_emi', 'emi', 'monthly'),
    ('🛡️', 'preset_insurance', 'bills', 'yearly'),
    ('📈', 'preset_sip', 'other', 'monthly'),
    ('💳', 'preset_card', 'bills', 'monthly'),
  ];

  static Future<void> editBill(BuildContext context, {Bill? bill}) async {
    final m = context.read<MoneyStore>();
    final b = bill == null
        ? Bill(due: dayKey(addDays(todayDate(), 7)), account: m.defaultAccountId, category: 'bills')
        : Bill.fromMap({...bill.toMap(), 'id': bill.id});
    final name = TextEditingController(text: b.name);
    final amount = TextEditingController(text: b.amount == 0 ? '' : b.amount.toStringAsFixed(b.amount == b.amount.roundToDouble() ? 0 : 2));
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final kind = b.type == TxnType.income ? 'income' : 'expense';
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t(bill == null ? 'add_bill' : 'edit_bill'), style: ctx.tt.titleLarge),
              const SizedBox(height: 12),
              PillTabs<String>(
                items: [(TxnType.expense, ctx.t('bill_to_pay')), (TxnType.income, ctx.t('income_to_get'))],
                value: b.type,
                onChanged: (v) => set(() {
                  b.type = v;
                  b.category = v == TxnType.income ? 'salary' : 'bills';
                }),
              ),
              if (bill == null && b.type == TxnType.expense) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final p in presets)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Text(p.$1),
                          label: Text(ctx.t(p.$2)),
                          onPressed: () => set(() {
                            b.emoji = p.$1;
                            name.text = ctx.t(p.$2);
                            b.category = m.catById(p.$3) != null ? p.$3 : b.category;
                            b.freq = p.$4;
                          }),
                        ),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: ctx.t('name'),
                  prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(b.emoji, style: const TextStyle(fontSize: 18))),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: ctx.t('amount'), prefixText: '${Money.symbol} '),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FormFieldButton(
                    icon: Icons.event_rounded,
                    label: ctx.t('next_due'),
                    value: b.dueDate == null ? '—' : ctx.fmtDate(b.dueDate!, 'd MMM yyyy'),
                    onTap: () async {
                      final init = b.dueDate ?? todayDate();
                      final d = await showDatePicker(
                          context: ctx,
                          initialDate: init,
                          firstDate: init.year < 2020 ? DateTime(init.year) : DateTime(2020),
                          lastDate: DateTime(2100));
                      if (d != null) set(() => b.due = dayKey(d));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FormFieldButton(
                    icon: Icons.repeat_rounded,
                    label: ctx.t('repeat'),
                    value: repeatLabel(ctx, b.freq),
                    onTap: () async {
                      final r = await showAppSheet<String>(ctx, builder: (c2) {
                        return SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SheetHeader(c2.t('repeat')),
                            for (final f in const ['weekly', 'monthly', 'quarterly', 'yearly'])
                              ListTile(
                                title: Text(repeatLabel(c2, f)),
                                trailing: f == b.freq ? Icon(Icons.check_rounded, color: c2.cs.primary) : null,
                                onTap: () => Navigator.pop(c2, f),
                              ),
                          ]),
                        );
                      });
                      if (r != null) set(() => b.freq = r);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FormFieldButton(
                    icon: Icons.category_outlined,
                    leading: Text(m.catById(b.category)?.emoji ?? '📦', style: const TextStyle(fontSize: 18)),
                    label: ctx.t('category'),
                    value: categoryName(ctx, m.catById(b.category)),
                    onTap: () async {
                      final c = await pickCategory(ctx, kind, current: b.category);
                      if (c != null) set(() => b.category = c);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FormFieldButton(
                    icon: Icons.account_balance_wallet_outlined,
                    label: ctx.t('account'),
                    value: accountName(ctx, m.accountById(b.account)),
                    onTap: () async {
                      final a = await pickAccount(ctx, current: b.account);
                      if (a != null) set(() => b.account = a);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(ctx.t('remind_me'), style: ctx.tt.labelMedium),
              const SizedBox(height: 6),
              ChipRow<int>(
                items: [
                  (0, ctx.t('on_the_day')),
                  (1, ctx.tn('days_before', 1)),
                  (2, ctx.tn('days_before', 2)),
                  (3, ctx.tn('days_before', 3)),
                  (7, ctx.tn('days_before', 7)),
                ],
                value: b.remindDays,
                onSelected: (v) => set(() => b.remindDays = v),
              ),
              const SizedBox(height: 18),
              Row(children: [
                if (bill != null)
                  TextButton(
                    onPressed: () {
                      m.saveBill(b..active = !b.active);
                      Navigator.pop(ctx);
                    },
                    child: Text(ctx.t(b.active ? 'pause' : 'resume')),
                  ),
                if (bill != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: ctx.tokens.danger),
                    onPressed: () async {
                      final ok = await confirmDialog(ctx, title: ctx.t('delete_bill_q'), danger: true, confirm: ctx.t('delete'));
                      if (!ok) return;
                      m.deleteBill(bill);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final a = double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
                    if (name.text.trim().isEmpty || a <= 0 || !a.isFinite) {
                      showToast(ctx, ctx.t('name_and_amount'));
                      return;
                    }
                    b
                      ..name = name.text.trim()
                      ..amount = a;
                    m.saveBill(b);
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

class _BillRow extends StatelessWidget {
  final Bill bill;
  const _BillRow({required this.bill});

  @override
  Widget build(BuildContext context) {
    final m = context.read<MoneyStore>();
    final tk = context.tokens;
    final left = bill.daysLeft();
    final dueText = left < 0
        ? context.tn('days_overdue', -left)
        : left == 0
            ? context.t('due_today')
            : context.tn('in_days', left);
    final dueColor = left < 0 ? tk.danger : (left <= 2 ? tk.warning : tk.textMuted);
    final isIncome = bill.type == TxnType.income;
    return DhCard(
      onTap: () => BillsScreen.editBill(context, bill: bill),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(children: [
        IconBadge(emoji: bill.emoji, color: isIncome ? tk.income : AppColors.mReminders, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bill.name, style: context.tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Wrap(spacing: 8, children: [
              Text(dueText, style: context.tt.bodySmall?.copyWith(color: dueColor, fontWeight: FontWeight.w700)),
              Text(repeatLabel(context, bill.freq), style: context.tt.bodySmall),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Money.format(bill.amount), style: context.tt.titleSmall?.copyWith(color: isIncome ? tk.income : null)),
          if (bill.active)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () {
                m.markBillPaid(bill);
                showToast(context, context.t(isIncome ? 'marked_received' : 'marked_paid'), icon: Icons.check_circle_rounded);
              },
              child: Text(context.t(isIncome ? 'received' : 'paid')),
            ),
        ]),
      ]),
    );
  }
}

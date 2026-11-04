import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'txn_editor.dart';

String categoryName(BuildContext context, Category? c) {
  if (c == null) return context.t('cat_other');
  if (c.name.isNotEmpty) return c.name;
  if (c.key.isNotEmpty) return context.t('cat_${c.key}');
  return context.t('cat_other');
}

String accountName(BuildContext context, Account? a) {
  if (a == null) return context.t('acc_none');
  if (a.name.isNotEmpty) return a.name;
  return context.t('acc_${a.kind}');
}

Color categoryColor(Category? c) => AppColors.swatch(c?.color ?? 7);

Color typeColor(BuildContext context, String type) => switch (type) {
      TxnType.income => context.tokens.income,
      TxnType.transfer => context.tokens.transfer,
      _ => context.tokens.expense,
    };

/// A transaction row. Tap to edit, swipe to delete (with undo).
class TxnTile extends StatelessWidget {
  final Txn txn;
  final bool showDate;
  const TxnTile({super.key, required this.txn, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final m = context.read<MoneyStore>();
    final tk = context.tokens;
    final t = txn;
    final cat = m.catById(t.category);
    final acc = m.accountById(t.account);
    final title = t.isTransfer
        ? '${accountName(context, acc)} → ${accountName(context, m.accountById(t.toAccount))}'
        : (t.note.isNotEmpty ? t.note : categoryName(context, cat));
    final sub = <String>[
      if (!t.isTransfer && t.note.isNotEmpty) categoryName(context, cat),
      if (t.isTransfer) context.t('transfer'),
      if (!t.isTransfer && acc != null) accountName(context, acc),
      if (showDate) context.dayLabel(t.day, short: true),
      if (t.split != null) context.tr('split_n', {'n': toI(t.split!['n'])}),
    ];
    final color = typeColor(context, t.type);
    final sign = t.isIncome ? '+' : (t.isExpense ? '−' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SwipeTile(
        swipeKey: ValueKey('txn_${t.id}'),
        leftIcon: Icons.delete_outline_rounded,
        leftColor: tk.danger,
        leftLabel: context.t('delete'),
        onSwipeLeft: () async {
          final data = m.deleteTxn(t);
          showUndo(context, context.t('txn_deleted'), () => m.restore('txns', t.id, data));
          return true;
        },
        child: DhCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          onTap: () => openTxnEditor(context, txn: t),
          child: Row(children: [
            t.isTransfer
                ? IconBadge(icon: Icons.swap_horiz_rounded, color: color, size: 40)
                : IconBadge(emoji: cat?.emoji ?? '📦', color: categoryColor(cat), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$sign${Money.format(t.amount)}',
                  style: context.tt.titleSmall?.copyWith(color: t.isTransfer ? null : color, fontWeight: FontWeight.w800)),
              if (t.time.isNotEmpty) Text(context.timeOfHm(t.time), style: context.tt.bodySmall?.copyWith(fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// ‹ September 2026 ›
class MonthSwitcher extends StatelessWidget {
  final String month;
  final ValueChanged<String> onChanged;
  const MonthSwitcher({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = monthKeyOf(DateTime.now());
    final isNow = month == now;
    return Row(children: [
      IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => onChanged(shiftMonth(month, -1))),
      Expanded(
        child: GestureDetector(
          onTap: isNow ? null : () => onChanged(now),
          child: Column(children: [
            Text(context.monthLabel(monthStart(month)), style: context.tt.titleMedium, textAlign: TextAlign.center),
            if (!isNow)
              Text(context.t('back_to_this_month'),
                  style: context.tt.bodySmall?.copyWith(color: context.cs.primary), textAlign: TextAlign.center),
          ]),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right_rounded),
        onPressed: month.compareTo(now) >= 0 ? null : () => onChanged(shiftMonth(month, 1)),
      ),
    ]);
  }
}

/// Transactions grouped by day with a daily total.
List<Widget> txnDayGroups(BuildContext context, List<Txn> txns) {
  final out = <Widget>[];
  final byDay = <String, List<Txn>>{};
  for (final t in txns) {
    byDay.putIfAbsent(t.date, () => []).add(t);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final d in days) {
    final list = byDay[d]!;
    final spent = list.where((t) => t.isExpense).fold(0.0, (s, t) => s + t.amount);
    final earned = list.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);
    final day = parseDay(d) ?? todayDate();
    out.add(Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
      child: Row(children: [
        Text(context.dayLabel(day), style: context.tt.labelLarge),
        const SizedBox(width: 6),
        Text(context.fmtDate(day, 'd MMM'), style: context.tt.bodySmall),
        const Spacer(),
        if (earned > 0)
          Text('+${Money.format(earned)}  ', style: context.tt.labelMedium?.copyWith(color: context.tokens.income)),
        if (spent > 0) Text('−${Money.format(spent)}', style: context.tt.labelMedium?.copyWith(color: context.tokens.expense)),
      ]),
    ));
    for (final t in list) {
      out.add(TxnTile(txn: t));
    }
  }
  return out;
}

/// Asks for an amount with the number keyboard.
Future<double?> promptAmount(BuildContext context, {required String title, double? initial, String? hint}) async {
  final c = TextEditingController(
      text: initial == null || initial == 0 ? '' : (initial == initial.roundToDouble() ? initial.toStringAsFixed(0) : '$initial'));
  // "NaN", "Infinity" or absurdly long input must never become an amount.
  double? parse(String s) {
    final v = double.tryParse(s.replaceAll(',', '').trim());
    return v != null && v.isFinite ? v : null;
  }

  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(prefixText: '${Money.symbol} ', hintText: hint ?? '0'),
        onSubmitted: (v) => Navigator.pop(ctx, parse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, parse(c.text)),
          child: Text(ctx.t('save')),
        ),
      ],
    ),
  );
  // Dispose after the dialog's exit animation, not while its TextField still uses the controller.
  WidgetsBinding.instance.addPostFrameCallback((_) => Future<void>.delayed(const Duration(milliseconds: 400), c.dispose));
  return r;
}

/// Picks a category of [kind]; returns its id.
Future<String?> pickCategory(BuildContext context, String kind, {String? current}) {
  final m = context.read<MoneyStore>();
  return showAppSheet<String>(context, builder: (ctx) {
    final cats = m.categoriesOf(kind);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: Column(children: [
          SheetHeader(ctx.t('category')),
          Expanded(
            child: ListView(children: [
              for (final c in cats)
                ListTile(
                  leading: IconBadge(emoji: c.emoji, color: categoryColor(c), size: 36),
                  title: Text(categoryName(ctx, c)),
                  trailing: c.id == current ? Icon(Icons.check_rounded, color: ctx.cs.primary) : null,
                  onTap: () => Navigator.pop(ctx, c.id),
                ),
            ]),
          ),
        ]),
      ),
    );
  });
}

/// Picks an account; returns its id.
Future<String?> pickAccount(BuildContext context, {String? current}) {
  final m = context.read<MoneyStore>();
  return showAppSheet<String>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(ctx.t('account')),
          for (final a in m.activeAccounts)
            ListTile(
              leading: IconBadge(emoji: a.emoji, color: AppColors.swatch(a.color), size: 36),
              title: Text(accountName(ctx, a)),
              subtitle: Text(Money.format(m.accountBalance(a.id))),
              trailing: a.id == current ? Icon(Icons.check_rounded, color: ctx.cs.primary) : null,
              onTap: () => Navigator.pop(ctx, a.id),
            ),
        ]),
      ),
    );
  });
}

/// A labelled tappable field used in money forms.

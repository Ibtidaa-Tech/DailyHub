import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'money_ui.dart';

/// Month / year reports, trends, category changes and CSV export.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _year = false;
  String _month = monthKeyOf(DateTime.now());
  int _yearNum = DateTime.now().year;

  (DateTime, DateTime) get _range {
    if (_year) return (DateTime(_yearNum, 1, 1), DateTime(_yearNum, 12, 31));
    final s = monthStart(_month);
    return (s, DateTime(s.year, s.month, daysInMonth(s.year, s.month)));
  }

  (DateTime, DateTime) get _prevRange {
    if (_year) return (DateTime(_yearNum - 1, 1, 1), DateTime(_yearNum - 1, 12, 31));
    final s = monthStart(shiftMonth(_month, -1));
    return (s, DateTime(s.year, s.month, daysInMonth(s.year, s.month)));
  }

  List<Txn> _inRange(MoneyStore m, (DateTime, DateTime) r) =>
      m.txns.where((t) => !t.day.isBefore(r.$1) && !t.day.isAfter(r.$2)).toList();

  Map<String, double> _byCat(List<Txn> list, String type) {
    final out = <String, double>{};
    for (final t in list) {
      if (t.type != type) continue;
      out[t.category] = (out[t.category] ?? 0.0) + t.amount;
    }
    return out;
  }

  Future<void> _exportCsv(MoneyStore m, List<Txn> list) async {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('Date,Time,Type,Amount,Currency,Category,Account,To account,Note\n');
    for (final t in list) {
      b.writeln([
        t.date,
        t.time,
        t.type,
        t.amount.toStringAsFixed(2),
        Money.current.code,
        esc(categoryName(context, m.catById(t.category))),
        esc(accountName(context, m.accountById(t.account))),
        esc(t.toAccount.isEmpty ? '' : accountName(context, m.accountById(t.toAccount))),
        esc(t.note),
      ].join(','));
    }
    final name = _year ? 'dailyhub-$_yearNum.csv' : 'dailyhub-$_month.csv';
    final bytes = Uint8List.fromList(utf8.encode('﻿${b.toString()}'));
    await Share.shareXFiles([XFile.fromData(bytes, name: name, mimeType: 'text/csv')],
        subject: 'DailyHub $name', fileNameOverrides: [name]);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final r = _range;
    final list = _inRange(m, r)..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    final prev = _inRange(m, _prevRange);
    double sum(List<Txn> l, String type) => l.where((t) => t.type == type).fold(0.0, (s, t) => s + t.amount);
    final inc = sum(list, TxnType.income);
    final exp = sum(list, TxnType.expense);
    final prevExp = sum(prev, TxnType.expense);
    final cats = _byCat(list, TxnType.expense).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final prevCats = _byCat(prev, TxnType.expense);
    final incomeCats = _byCat(list, TxnType.income).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final biggest = list.where((t) => t.isExpense).toList()..sort((a, b) => b.amount.compareTo(a.amount));

    // Trend: 6 months, or 12 months of the year.
    final trendMonths = _year
        ? [for (var i = 1; i <= 12; i++) monthKeyOf(DateTime(_yearNum, i))]
        : [for (var i = 5; i >= 0; i--) shiftMonth(_month, -i)];
    final trendInc = trendMonths.map((mk) => m.totals(mk).income).toList();
    final trendExp = trendMonths.map((mk) => m.totals(mk).expense).toList();
    final labels = trendMonths.map((mk) => context.fmtDate(monthStart(mk), 'MMM')).toList();

    return AppPage(
      title: context.t('m_reports'),
      actions: [
        IconButton(
          tooltip: context.t('export_csv'),
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: list.isEmpty ? null : () => _exportCsv(m, list),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: PillTabs<bool>(
            items: [(false, context.t('month')), (true, context.t('year'))],
            value: _year,
            onChanged: (v) => setState(() => _year = v),
          ),
        ),
        SliverToBoxAdapter(
          child: _year
              ? Row(children: [
                  IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => setState(() => _yearNum--)),
                  Expanded(child: Text('$_yearNum', textAlign: TextAlign.center, style: context.tt.titleMedium)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _yearNum >= DateTime.now().year ? null : () => setState(() => _yearNum++),
                  ),
                ])
              : MonthSwitcher(month: _month, onChanged: (v) => setState(() => _month = v)),
        ),
        SliverToBoxAdapter(
          child: DhCard(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Row(children: [
                Expanded(child: StatBlock(label: context.t('earned'), value: Money.format(inc, compact: true), color: tk.income)),
                Expanded(child: StatBlock(label: context.t('spent'), value: Money.format(exp, compact: true), color: tk.expense)),
                Expanded(
                  child: StatBlock(
                    label: context.t(inc - exp >= 0 ? 'net_saved' : 'overspent'),
                    value: Money.format((inc - exp).abs(), compact: true),
                    color: inc - exp >= 0 ? tk.income : tk.expense,
                  ),
                ),
              ]),
              if (prevExp > 0) ...[
                const SizedBox(height: 12),
                _ChangeLine(now: exp, before: prevExp, label: context.t(_year ? 'vs_last_year' : 'vs_last_month')),
              ],
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: DhCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('trend'), style: context.tt.titleMedium),
              const SizedBox(height: 4),
              Row(children: [
                _Legend(color: tk.income, label: context.t('earned')),
                const SizedBox(width: 12),
                _Legend(color: tk.expense, label: context.t('spent')),
              ]),
              const SizedBox(height: 14),
              MiniBars(values: trendInc, values2: trendExp, color: tk.income, color2: tk.expense, height: 110, labels: labels),
            ]),
          ),
        ),
        if (cats.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('spending_by_category'))),
          SliverList.list(children: [
            for (final e in cats)
              Builder(builder: (context) {
                final cat = m.catById(e.key);
                final before = prevCats[e.key] ?? 0.0;
                return DhCard(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(children: [
                    Row(children: [
                      Text(cat?.emoji ?? '📦', style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(categoryName(context, cat), style: context.tt.labelLarge)),
                      if (before > 0) _Delta(now: e.value, before: before),
                      const SizedBox(width: 8),
                      Text(Money.format(e.value), style: context.tt.labelLarge),
                    ]),
                    const SizedBox(height: 6),
                    ProgressBar(value: exp == 0 ? 0 : e.value / exp, color: categoryColor(cat), height: 6),
                  ]),
                );
              }),
          ]),
        ],
        if (incomeCats.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('income_sources'))),
          SliverList.list(children: [
            for (final e in incomeCats)
              DhCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(children: [
                  Text(m.catById(e.key)?.emoji ?? '💰', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(categoryName(context, m.catById(e.key)), style: context.tt.labelLarge)),
                  Text(Money.format(e.value), style: context.tt.labelLarge?.copyWith(color: tk.income)),
                ]),
              ),
          ]),
        ],
        if (biggest.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('biggest_expenses'))),
          SliverList.list(children: [for (final t in biggest.take(5)) TxnTile(txn: t, showDate: true)]),
        ],
        if (list.isEmpty)
          SliverToBoxAdapter(child: EmptyView(icon: Icons.bar_chart_rounded, title: context.t('no_data_period'), compact: true)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: context.tt.bodySmall),
      ]);
}

class _Delta extends StatelessWidget {
  final double now;
  final double before;
  const _Delta({required this.now, required this.before});
  @override
  Widget build(BuildContext context) {
    final ratio = before == 0 ? 0.0 : (now - before) / before * 100;
    // .round() throws on Infinity/NaN (e.g. a tiny previous amount).
    final pct = ratio.isFinite ? ratio.round() : 0;
    final up = pct > 0;
    final c = up ? context.tokens.expense : context.tokens.income;
    return Text('${up ? '▲' : '▼'} ${pct.abs()}%', style: context.tt.labelSmall?.copyWith(color: c));
  }
}

class _ChangeLine extends StatelessWidget {
  final double now;
  final double before;
  final String label;
  const _ChangeLine({required this.now, required this.before, required this.label});
  @override
  Widget build(BuildContext context) {
    final ratio = (now - before) / before * 100;
    final pct = ratio.isFinite ? ratio.round() : 0;
    final up = pct > 0;
    final c = up ? context.tokens.expense : context.tokens.income;
    return Row(children: [
      Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: c, size: 18),
      const SizedBox(width: 6),
      Text(context.tr(up ? 'spent_more_pct' : 'spent_less_pct', {'p': pct.abs()}), style: context.tt.labelMedium?.copyWith(color: c)),
      const SizedBox(width: 6),
      Text(label, style: context.tt.bodySmall),
    ]);
  }
}

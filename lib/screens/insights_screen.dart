import 'package:flutter/material.dart';

import '../core/currencies.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// Insights — how your week or month actually went, across every module.
///
/// Everything here is drawn with the shared kit charts ([MiniBars], [Donut],
/// [ProgressRing]) so the colours follow the theme in light and dark mode.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _monthly = false;

  int get _days => _monthly ? 30 : 7;

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('todos', workspace: true),
      builder: (context, todoSnap) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.stream('txns'),
        builder: (context, txnSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: db.stream('habits'),
          builder: (context, habitSnap) => StreamBuilder<List<Map<String, dynamic>>>(
            stream: db.stream('notes'),
            builder: (context, noteSnap) => _page(
              context,
              todos: todoSnap.data ?? const [],
              txns: txnSnap.data ?? const [],
              habits: habitSnap.data ?? const [],
              notes: noteSnap.data ?? const [],
              loading: todoSnap.data == null && txnSnap.data == null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(
    BuildContext context, {
    required List<Map<String, dynamic>> todos,
    required List<Map<String, dynamic>> txns,
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> notes,
    required bool loading,
  }) {
    final tk = context.tokens;
    final days = _days;
    final today = todayDate();
    final start = addDays(today, -(days - 1));

    /// Index of [iso] within the window, or null when it falls outside it.
    int? bucket(String iso) {
      final d = parseDay(iso);
      if (d == null) return null;
      final i = daysBetween(start, d);
      return (i < 0 || i >= days) ? null : i;
    }

    // ------------------------------------------------------------- tasks
    final doneByDay = List<double>.filled(days, 0);
    var completed = 0;
    var pending = 0;
    for (final t in todos) {
      final status = str(t['status']).isEmpty ? 'upcoming' : str(t['status']);
      if (status != 'completed') {
        if (status == 'upcoming') pending++;
        continue;
      }
      final done = str(t['doneAt']);
      final b = bucket(done.isEmpty ? str(t['date']) : done);
      if (b == null) continue;
      doneByDay[b] += 1;
      completed++;
    }
    final taskTotal = completed + pending;
    final doneShare = taskTotal == 0 ? 0.0 : completed / taskTotal;

    // ------------------------------------------------------------- money
    final spendByDay = List<double>.filled(days, 0);
    var spent = 0.0;
    var earned = 0.0;
    for (final e in txns) {
      final b = bucket(str(e['date']));
      if (b == null) continue;
      final type = str(e['type']).isEmpty ? 'expense' : str(e['type']);
      final amount = toD(e['amount']);
      if (type == 'expense') {
        spent += amount;
        spendByDay[b] += amount;
      } else if (type == 'income') {
        earned += amount;
      }
      // Transfers move money between your own accounts, so they are neither
      // spending nor income and are deliberately left out.
    }

    // ------------------------------------------------------------ habits
    final ticksByDay = List<double>.filled(days, 0);
    var ticks = 0;
    for (final h in habits) {
      final history = h['history'];
      if (history is! Map) continue;
      history.forEach((k, v) {
        final did = v == true || (v is num && v > 0);
        if (!did) return;
        final b = bucket(str(k));
        if (b == null) return;
        ticksByDay[b] += 1;
        ticks++;
      });
    }
    final possible = habits.length * days;
    // `.clamp` is declared on num and returns num, so the result is forced back
    // to double before it reaches ProgressRing's `value`.
    final double consistency =
        possible == 0 ? 0.0 : (ticks / possible).clamp(0.0, 1.0).toDouble();

    // ------------------------------------------------------------- notes
    var notesMade = 0;
    for (final n in notes) {
      final created = str(n['createdAt']);
      if (bucket(created.isEmpty ? str(n['date']) : created) != null) notesMade++;
    }

    final labels = _monthly
        ? null
        : [for (var i = 0; i < days; i++) context.fmtDate(addDays(start, i), 'EEE')];
    final highlight = _monthly ? null : days - 1;
    final nothing = completed == 0 &&
        pending == 0 &&
        spent == 0 &&
        earned == 0 &&
        ticks == 0 &&
        notesMade == 0;

    return AppPage(
      title: context.t('m_insights'),
      subtitle: context.t(_monthly ? 'last_30_days' : 'last_7_days'),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: PillTabs<bool>(
          items: [
            (false, context.t('last_7_days')),
            (true, context.t('last_30_days')),
          ],
          value: _monthly,
          onChanged: (v) => setState(() => _monthly = v),
        ),
      ),
      slivers: [
        if (loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 70),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (nothing)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.insights_rounded,
              color: AppColors.mInsights,
              title: context.t('ins_empty'),
              message: context.t('ins_empty_msg'),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: DhCard(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              // Two rows of two rather than four across, so the captions still
              // fit on a narrow phone with large system text.
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: StatBlock(
                      label: context.t('completed'),
                      value: '$completed',
                      color: tk.success,
                    ),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: context.t('upcoming'),
                      value: '$pending',
                      color: tk.warning,
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: tk.border),
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: StatBlock(
                      label: context.t('spent'),
                      value: Money.format(spent, compact: true),
                      color: tk.expense,
                    ),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: context.t('m_notes'),
                      value: '$notesMade',
                      color: AppColors.mNotes,
                    ),
                  ),
                ]),
              ]),
            ),
          ),

          // ----------------------------------------------------- tasks
          if (taskTotal > 0) ...[
            SliverToBoxAdapter(child: SectionTitle(context.t('m_tasks'))),
            SliverToBoxAdapter(
              child: DhCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ProgressRing(
                      value: doneShare,
                      size: 62,
                      stroke: 7,
                      color: AppColors.mTasks,
                      child: Text('${(doneShare * 100).round()}%',
                          style: context.tt.labelMedium),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t('ins_tasks_daily'), style: context.tt.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('ins_done_pending',
                              {'a': completed, 'b': pending}),
                          style: context.tt.bodySmall,
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  MiniBars(
                    values: doneByDay,
                    color: AppColors.mTasks,
                    height: 96,
                    labels: labels,
                    highlight: highlight,
                  ),
                ]),
              ),
            ),
          ],

          // ----------------------------------------------------- money
          if (spent > 0 || earned > 0) ...[
            SliverToBoxAdapter(child: SectionTitle(context.t('m_money'))),
            SliverToBoxAdapter(
              child: DhCard(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Donut(
                    values: [spent, earned],
                    colors: [tk.expense, tk.income],
                    size: 128,
                    stroke: 15,
                    center: Padding(
                      padding: const EdgeInsets.all(30),
                      child: FittedBox(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(context.t('spent'), style: context.tt.bodySmall),
                          Text(Money.format(spent, compact: true),
                              style: context.tt.titleMedium),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Legend(
                        color: tk.expense,
                        label: context.t('spent'),
                        value: Money.format(spent, compact: true),
                      ),
                      const SizedBox(height: 12),
                      _Legend(
                        color: tk.income,
                        label: context.t('earned'),
                        value: Money.format(earned, compact: true),
                      ),
                      const SizedBox(height: 12),
                      _Legend(
                        color: earned - spent >= 0 ? tk.income : tk.expense,
                        label: context.t(earned - spent >= 0 ? 'net_saved' : 'overspent'),
                        value: Money.format((earned - spent).abs(), compact: true),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            if (spent > 0)
              SliverToBoxAdapter(
                child: DhCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('ins_daily_spend'), style: context.tt.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('ins_per_day',
                          {'a': Money.format(spent / days, compact: true)}),
                      style: context.tt.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    MiniBars(
                      values: spendByDay,
                      color: AppColors.mMoney,
                      height: 110,
                      labels: labels,
                      highlight: highlight,
                    ),
                  ]),
                ),
              ),
          ],

          // ---------------------------------------------------- habits
          if (habits.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(context.t('m_habits'))),
            SliverToBoxAdapter(
              child: DhCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    ProgressRing(
                      value: consistency,
                      size: 66,
                      stroke: 7,
                      color: consistency >= 0.7 ? tk.success : tk.warning,
                      child: Text('${(consistency * 100).round()}%',
                          style: context.tt.labelMedium),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t('ins_consistency'), style: context.tt.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('ins_checkins', {'a': ticks, 'b': possible}),
                          style: context.tt.bodySmall,
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  MiniBars(
                    values: ticksByDay,
                    color: AppColors.mHabits,
                    height: 96,
                    labels: labels,
                    highlight: highlight,
                  ),
                ]),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// A colour dot, a caption and the amount it stands for.
class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _Legend({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tt.labelLarge?.copyWith(color: color),
          ),
        ]),
      ),
    ]);
  }
}

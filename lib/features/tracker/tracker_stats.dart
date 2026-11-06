import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';
import 'tick_list_sheet.dart';

enum _Split { week, month, weekday, day }

/// The analysis view: how the run is going overall, sliced by week, month,
/// weekday and day, then habit by habit.
///
/// Everything here reads from [TrackerStore.tally], so no number on this
/// screen can disagree with the sheet or with what a mentor sees.
class TrackerStats extends StatefulWidget {
  final Challenge challenge;
  final TrackerStore store;
  const TrackerStats({super.key, required this.challenge, required this.store});

  @override
  State<TrackerStats> createState() => _TrackerStatsState();
}

class _TrackerStatsState extends State<TrackerStats> {
  _Split _split = _Split.week;

  /// Opens the entries behind a figure in the summary. Read-only here — the
  /// dashboard is for reading the run, not editing it, and the same list is
  /// reachable from the Today header where ticking belongs.
  Future<void> _open(TickStatus? status, bool lateEntryOnly) async {
    await showTickList(
      context,
      challenge: widget.challenge,
      store: widget.store,
      status: status,
      lateEntryOnly: lateEntryOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final store = widget.store;
    final total = store.tally(c);

    if (total.expected == 0 || total.done == 0) {
      return EmptyView(
        icon: Icons.insights_rounded,
        color: AppColors.mTracker,
        title: context.t('tr_nothing_yet'),
        message: context.t('tr_nothing_yet_msg'),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Summary(challenge: c, store: store, total: total, onOpen: _open),
      SectionTitle(context.t('tr_split')),
      PillTabs<_Split>(
        items: [
          (_Split.week, context.t('tr_by_week')),
          (_Split.month, context.t('tr_by_month')),
          (_Split.weekday, context.t('tr_by_weekday')),
          (_Split.day, context.t('tr_by_day')),
        ],
        value: _split,
        onChanged: (v) => setState(() => _split = v),
      ),
      const SizedBox(height: 10),
      switch (_split) {
        _Split.week => _WeekSplit(challenge: c, store: store),
        _Split.month => _MonthSplit(challenge: c, store: store),
        _Split.weekday => _WeekdaySplit(challenge: c, store: store),
        _Split.day => _DaySplit(challenge: c, store: store),
      },
      SectionTitle(context.t('tr_by_habit')),
      _HabitTable(challenge: c, store: store),
      const SizedBox(height: 90),
    ]);
  }
}

// ------------------------------------------------------------------ summary

class _Summary extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  final TrackerTally total;
  final void Function(TickStatus? status, bool lateEntryOnly) onOpen;
  const _Summary({
    required this.challenge,
    required this.store,
    required this.total,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final items = store.byItem(challenge);

    // Average minutes late across everything that was ticked late. Worth
    // seeing: "late by 4 minutes" and "late by 3 hours" are different habits.
    var lateMinutes = 0, lateCount = 0;
    for (final l in store.logs) {
      if (l.challengeId != challenge.id || !l.wasLate) continue;
      lateMinutes += l.lateBy;
      lateCount++;
    }

    (TrackerItem, TrackerTally)? best, worst;
    for (final e in items) {
      if (e.$2.expected == 0) continue;
      if (best == null || e.$2.rate > best.$2.rate) best = e;
      if (worst == null || e.$2.rate < worst.$2.rate) worst = e;
    }

    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Donut(
            size: 118,
            stroke: 14,
            values: [
              total.onTime.toDouble(),
              total.lateTicks.toDouble(),
              total.missed.toDouble(),
            ],
            colors: [tk.success, tk.warning, tk.danger],
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(total.rate * 100).round()}%', style: context.tt.titleLarge),
              Text(context.t('tr_done_rate'), style: context.tt.bodySmall),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Key(
                color: tk.success,
                label: context.t('tr_on_time'),
                value: total.onTime,
                onTap: () => onOpen(TickStatus.onTime, false),
              ),
              _Key(
                color: tk.warning,
                label: context.t('tr_late'),
                value: total.lateTicks,
                onTap: () => onOpen(TickStatus.overdue, false),
              ),
              _Key(
                color: tk.transfer,
                label: context.t('tr_late_entries'),
                value: total.recordedLate,
                onTap: () => onOpen(null, true),
              ),
              _Key(
                color: tk.danger,
                label: context.t('tr_missed'),
                value: total.missed,
                onTap: () => onOpen(TickStatus.missed, false),
              ),
            ]),
          ),
        ]),
        const Divider(height: 26),
        Row(children: [
          Expanded(
            child: StatBlock(
              label: context.t('tr_ontime_rate'),
              value: '${(total.onTimeRate * 100).round()}%',
              color: tk.success,
            ),
          ),
          Expanded(
            child: StatBlock(
              label: context.t('tr_perfect_days'),
              value: '${store.perfectDays(challenge)}',
              color: AppColors.mTracker,
            ),
          ),
          Expanded(
            child: StatBlock(
              label: context.t('tr_total_ticks'),
              value: '${total.done}',
            ),
          ),
          Expanded(
            child: StatBlock(
              label: context.t('tr_avg_late'),
              value: lateCount == 0
                  ? '—'
                  : context.tr('dur_min', {'n': (lateMinutes / lateCount).round()}),
              color: lateCount == 0 ? tk.success : tk.warning,
            ),
          ),
        ]),
        if (best != null && worst != null && best.$1.id != worst.$1.id) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _Highlight(
                label: context.t('tr_best_habit'),
                item: best.$1,
                tally: best.$2,
                good: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Highlight(
                label: context.t('tr_worst_habit'),
                item: worst.$1,
                tally: worst.$2,
                good: false,
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  final VoidCallback? onTap;
  const _Key({required this.color, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.s),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: context.tt.bodySmall)),
        Text('$value', style: context.tt.labelLarge),
        if (onTap != null)
          Icon(Icons.chevron_right_rounded, size: 16, color: context.tokens.textFaint),
      ]),
    ),
    );
  }
}

class _Highlight extends StatelessWidget {
  final String label;
  final TrackerItem item;
  final TrackerTally tally;
  final bool good;
  const _Highlight({required this.label, required this.item, required this.tally, required this.good});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final c = good ? tk.success : tk.warning;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: tk.tint(c), borderRadius: BorderRadius.circular(Radii.m)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: context.tt.bodySmall?.copyWith(color: c)),
        const SizedBox(height: 4),
        Row(children: [
          Text(item.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(item.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
          ),
          Text('${(tally.rate * 100).round()}%', style: context.tt.labelLarge?.copyWith(color: c)),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------- splits

/// One row of a breakdown: a label, a bar, and the raw counts behind it.
class _SplitRow extends StatelessWidget {
  final String label;
  final String? sub;
  final TrackerTally tally;
  const _SplitRow({required this.label, this.sub, required this.tally});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final empty = tally.expected == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
          width: 74,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: context.tt.labelMedium),
            if (sub != null)
              Text(sub!, style: context.tt.bodySmall?.copyWith(fontSize: 10, color: tk.textMuted)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Two bars stacked: everything ticked, and the on-time share of it.
            ProgressBar(value: empty ? 0.0 : tally.rate, color: AppColors.mTracker, height: 7),
            const SizedBox(height: 3),
            ProgressBar(value: empty ? 0.0 : tally.onTimeRate, color: tk.success, height: 4),
          ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 86,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(empty ? '—' : '${(tally.rate * 100).round()}%', style: context.tt.labelLarge),
            Text(
              empty
                  ? ''
                  : context.tr('tr_of_expected', {'d': tally.done, 'e': tally.expected}),
              style: context.tt.bodySmall?.copyWith(fontSize: 10, color: tk.textMuted),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _WeekSplit extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  const _WeekSplit({required this.challenge, required this.store});

  @override
  Widget build(BuildContext context) {
    final rows = store.byWeek(challenge);
    final start = challenge.start ?? todayDate();
    return DhCard(
      child: Column(children: [
        for (final r in rows)
          _SplitRow(
            label: context.tr('tr_week_n', {'n': r.$1}),
            sub: context.fmtDate(addDays(start, (r.$1 - 1) * 7), 'd MMM'),
            tally: r.$2,
          ),
      ]),
    );
  }
}

class _MonthSplit extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  const _MonthSplit({required this.challenge, required this.store});

  @override
  Widget build(BuildContext context) {
    final rows = store.byMonth(challenge);
    return DhCard(
      child: Column(children: [
        for (final r in rows)
          _SplitRow(
            label: context.fmtDate(r.$1, 'MMM'),
            sub: context.fmtDate(r.$1, 'yyyy'),
            tally: r.$2,
          ),
      ]),
    );
  }
}

class _WeekdaySplit extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  const _WeekdaySplit({required this.challenge, required this.store});

  @override
  Widget build(BuildContext context) {
    final weekStart = context.watch<AppSettings>().weekStart;
    final rows = store.byWeekday(challenge, weekStart: weekStart);
    // Any date with the right weekday works as a label source.
    final ref = todayDate();
    return DhCard(
      child: Column(children: [
        for (final r in rows)
          _SplitRow(
            label: context.fmtDate(addDays(ref, r.$1 - ref.weekday), 'EEE'),
            tally: r.$2,
          ),
      ]),
    );
  }
}

class _DaySplit extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  const _DaySplit({required this.challenge, required this.store});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final days = store.byDay(challenge);
    final weekStart = context.watch<AppSettings>().weekStart;
    if (days.isEmpty) return const SizedBox.shrink();

    final values = [for (final d in days) d.$2];
    final labels = [
      for (var i = 0; i < days.length; i++)
        // Only every few days get a label, or they collide.
        (i == 0 || i == days.length - 1 || (i + 1) % 5 == 0) ? '${i + 1}' : '',
    ];

    (DateTime, double)? best, worst;
    for (final d in days) {
      if (best == null || d.$2 > best.$2) best = d;
      if (worst == null || d.$2 < worst.$2) worst = d;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DhCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('tr_daily_trend'), style: context.tt.labelMedium),
          const SizedBox(height: 10),
          MiniBars(
            values: values,
            color: AppColors.mTracker,
            height: 110,
            labels: labels,
            highlight: days.length - 1,
          ),
          if (best != null && worst != null && best.$2 > worst.$2) ...[
            const Divider(height: 22),
            Row(children: [
              Expanded(
                child: StatBlock(
                  label: context.t('tr_best_day'),
                  value: context.fmtDate(best.$1, 'd MMM'),
                  color: tk.success,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: context.t('tr_worst_day'),
                  value: context.fmtDate(worst.$1, 'd MMM'),
                  color: tk.danger,
                ),
              ),
            ]),
          ],
        ]),
      ),
      DhCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('tr_heatmap'), style: context.tt.labelMedium),
          const SizedBox(height: 10),
          Heatmap(
            weeks: (challenge.days / 7).ceil() + 1,
            weekStart: weekStart,
            color: AppColors.mTracker,
            valueOf: (d) => challenge.dayNumber(d) == null ? 0.0 : store.progressOn(challenge, d),
            scheduled: (d) => challenge.dayNumber(d) != null,
          ),
        ]),
      ),
    ]);
  }
}

// --------------------------------------------------------------- per habit

class _HabitTable extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  const _HabitTable({required this.challenge, required this.store});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final rows = store.byItem(challenge);
    return DhCard(
      child: Column(children: [
        for (var n = 0; n < rows.length; n++) ...[
          if (n > 0) Divider(height: 18, color: tk.border),
          _HabitRow(
            item: rows[n].$1,
            tally: rows[n].$2,
            streak: store.streakOf(challenge, rows[n].$1),
            best: store.bestStreakOf(challenge, rows[n].$1),
          ),
        ],
      ]),
    );
  }
}

class _HabitRow extends StatelessWidget {
  final TrackerItem item;
  final TrackerTally tally;
  final int streak;
  final int best;
  const _HabitRow({required this.item, required this.tally, required this.streak, required this.best});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = AppColors.swatch(item.color);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconBadge(emoji: item.emoji, color: color, size: 32, radius: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Text(item.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
        ),
        Text('${(tally.rate * 100).round()}%',
            style: context.tt.titleSmall?.copyWith(color: color)),
      ]),
      const SizedBox(height: 8),
      ProgressBar(value: tally.rate, color: color, height: 6),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 4, children: [
        Pill('${tally.onTime} ${context.t('tr_on_time')}', color: tk.success),
        if (tally.lateTicks > 0) Pill('${tally.lateTicks} ${context.t('tr_late')}', color: tk.warning),
        if (tally.recordedLate > 0)
          Pill('${tally.recordedLate} ${context.t('tr_late_entries')}', color: tk.transfer),
        if (tally.missed > 0) Pill('${tally.missed} ${context.t('tr_missed')}', color: tk.danger),
        Pill('${context.t('tr_streak_now')} $streak', color: AppColors.mTracker, icon: Icons.bolt_rounded),
        Pill('${context.t('tr_best')} $best', color: tk.textMuted),
      ]),
    ]);
  }
}

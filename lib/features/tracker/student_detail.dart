import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';
import 'challenge_editor.dart';
import 'tracker_grid.dart';
import 'tracker_stats.dart';
import 'tracker_ui.dart';

enum _Tab { progress, activity, sheet }

/// A mentor's view of one student's tracker.
///
/// Read-only on purpose: the mentor sets the habits and watches, the student
/// does the ticking. The database rules back this up — a mentor has no write
/// access to trackerLogs at all, so even a bug here could not record a tick
/// on someone else's behalf.
class StudentDetailScreen extends StatefulWidget {
  final String studentUid;
  final String name;
  const StudentDetailScreen({super.key, required this.studentUid, required this.name});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late final TrackerStore _store = TrackerStore(forUid: widget.studentUid);
  _Tab _tab = _Tab.progress;

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    final id = await showChallengeEditor(context, store: _store);
    if (id != null && mounted) {
      showToast(context, context.t('tr_assigned_ok'), icon: Icons.check_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The store is a plain ChangeNotifier here rather than a provider, so
    // this rebuilds it by hand as the student's data arrives.
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final c = _store.active;
        return AppPage(
          title: widget.name,
          subtitle: c?.title,
          actions: [
            IconButton(
              tooltip: context.t('tr_assign'),
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: _assign,
            ),
          ],
          slivers: c == null ? _emptySlivers() : _runSlivers(c),
        );
      },
    );
  }

  List<Widget> _emptySlivers() => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyView(
              icon: Icons.fact_check_outlined,
              color: AppColors.mTracker,
              title: context.t('tr_student_no_run'),
              message: context.t('tr_no_students_msg'),
              actionLabel: context.t('tr_assign'),
              onAction: _assign,
            ),
          ),
        ),
      ];

  List<Widget> _runSlivers(Challenge c) {
    final tally = _store.tally(c);
    final last = _store.logs.where((l) => l.challengeId == c.id).toList();
    final lastAt = last.isEmpty ? null : last.first.tickedAt;

    return [
      SliverToBoxAdapter(
        child: DhCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ProgressRing(
                value: tally.rate,
                size: 48,
                stroke: 5.5,
                color: AppColors.mTracker,
                child: Text('${(tally.rate * 100).round()}%', style: context.tt.labelSmall),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('tr_day_of', {'n': c.currentDay, 't': c.days}),
                      style: context.tt.titleSmall),
                  Text(
                    lastAt == null
                        ? context.t('tr_never')
                        : context.tr('tr_last_seen', {'x': context.relative(lastAt)}),
                    style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: StatBlock(
                  label: context.t('tr_on_time'),
                  value: '${tally.onTime}',
                  color: context.tokens.success,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: context.t('tr_late'),
                  value: '${tally.lateTicks + tally.backfilled}',
                  color: context.tokens.warning,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: context.t('tr_missed'),
                  value: '${tally.missed}',
                  color: tally.missed == 0 ? context.tokens.textMuted : context.tokens.danger,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: context.t('tr_perfect_days'),
                  value: '${_store.perfectDays(c)}',
                  color: AppColors.mTracker,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.visibility_outlined, size: 14, color: context.tokens.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(context.t('tr_view_only'),
                    style: context.tt.bodySmall?.copyWith(color: context.tokens.textFaint)),
              ),
            ]),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: PillTabs<_Tab>(
            items: [
              (_Tab.progress, context.t('tr_tab_stats')),
              (_Tab.activity, context.t('tr_recent')),
              (_Tab.sheet, context.t('tr_tab_grid')),
            ],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
      ),
      switch (_tab) {
        _Tab.progress => SliverToBoxAdapter(child: TrackerStats(challenge: c, store: _store)),
        _Tab.activity => _activitySliver(c),
        _Tab.sheet => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.64).clamp(340.0, 680.0),
                child: TrackerGrid(
                  challenge: c,
                  store: _store,
                  readOnly: true,
                  onTick: (_, __) {},
                ),
              ),
            ),
          ),
      },
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ];
  }

  /// Every tick, newest first, with the exact moment it happened. This is the
  /// answer to "did they do it, and was it on time" — nothing is summarised
  /// away.
  Widget _activitySliver(Challenge c) {
    final logs = _store.logs.where((l) => l.challengeId == c.id).take(60).toList();
    if (logs.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyView(
          icon: Icons.history_rounded,
          color: AppColors.mTracker,
          title: context.t('tr_no_recent'),
          compact: true,
        ),
      );
    }
    return SliverList.builder(
      itemCount: logs.length,
      itemBuilder: (context, n) {
        final l = logs[n];
        final item = _store.itemById(l.itemId);
        final at = l.tickedAt;
        final day = l.day;
        final color = item == null ? AppColors.mTracker : AppColors.swatch(item.color);
        return DhCard(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Row(children: [
            IconBadge(emoji: item?.emoji ?? '✅', color: color, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item?.name ?? '—',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
                const SizedBox(height: 1),
                Text(
                  at == null
                      ? ''
                      : '${context.dayLabel(day ?? at, short: true)} · ${context.timeOf(at)}',
                  style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted),
                ),
              ]),
            ),
            TickPill(l.tickStatus, itemColor: color, lateBy: l.lateBy),
          ]),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';
import 'challenge_editor.dart';
import 'done_time_sheet.dart';
import 'tick_detail_sheet.dart';
import 'tick_list_sheet.dart';
import 'item_editor.dart';
import 'mentor_screen.dart';
import 'tracker_grid.dart';
import 'tracker_stats.dart';
import 'tracker_ui.dart';

enum _View { today, sheet, stats }

/// The tracker: today's list, and the whole sheet.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});
  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  _View _view = _View.today;
  String? _challengeId;

  Challenge? _current(TrackerStore store) {
    if (_challengeId != null) {
      final c = store.byId(_challengeId!);
      if (c != null) return c;
    }
    return store.active;
  }

  /// Ticks a box, asking first when it was actually done.
  ///
  /// The time is never assumed from the tap, because the tap is usually not
  /// the moment: a Fajr prayed at 5:30 and ticked at 8pm is on time, and
  /// stamping 8pm would quietly call it late.
  Future<void> _tick(TrackerStore store, Challenge c, TrackerItem i, DateTime day) async {
    if (day.isAfter(todayDate())) {
      showToast(context, context.t('tr_future_day'), icon: Icons.block_rounded);
      return;
    }
    // Already ticked: show what is recorded rather than silently undoing it.
    // A stray tap should never cost a record.
    final existing = store.logFor(c.id, i.id, day);
    if (existing != null) {
      final action = await showTickDetail(
        context,
        item: i,
        day: day,
        log: existing,
        dayNumber: i.dayNumber(day),
      );
      if (action == null || !mounted) return;
      if (action == TickAction.clear) {
        final data = existing.toMap();
        final id = existing.id;
        store.untick(c, i, day);
        showUndo(context, context.t('tr_toast_cleared'), () => store.restoreLog(id, data));
        return;
      }
      // Change the time: reopen the picker seeded with what is there now.
      final revised = await askDoneTime(
        context,
        item: i,
        day: day,
        initial: existing.completedAt,
      );
      if (revised == null || !mounted) return;
      final updated = store.tick(c, i, revised);
      showToast(
        context,
        updated.tickStatus == TickStatus.overdue
            ? context.tr('tr_toast_late', {'n': updated.lateBy})
            : context.t('tr_toast_ontime'),
        icon: Icons.edit_rounded,
      );
      return;
    }

    final when = await askDoneTime(context, item: i, day: day);
    if (when == null || !mounted) return;

    final log = store.tick(c, i, when);
    if (log.tickStatus == TickStatus.overdue) {
      showToast(context, context.tr('tr_toast_late', {'n': log.lateBy}), icon: Icons.schedule_rounded);
    } else if (log.recordedLater) {
      showToast(context, context.tr('tr_toast_recorded', {'t': context.timeOf(when)}),
          icon: Icons.history_rounded);
    } else {
      showToast(context, context.t('tr_toast_ontime'), icon: Icons.check_circle_rounded);
    }
  }

  /// Opens the entries behind a figure. Picking one leads into it: a missed
  /// day goes straight to the time prompt, a done one to its details.
  Future<void> _openList(
    TrackerStore store,
    Challenge c, {
    TickStatus? status,
    bool lateEntryOnly = false,
  }) async {
    final picked = await showTickList(
      context,
      challenge: c,
      store: store,
      status: status,
      lateEntryOnly: lateEntryOnly,
    );
    if (picked == null || !mounted) return;
    await _tick(store, c, picked.item, picked.day);
  }

  /// Runs the same programme again. The finished one stays in the list with
  /// all its ticks intact — you can switch back to it any time.
  Future<void> _restart(TrackerStore store, Challenge c) async {
    final ok = await confirmDialog(
      context,
      title: context.t('tr_restart'),
      message: context.tr('tr_restart_q', {'t': c.title, 'n': store.itemsOf(c.id).length}),
      confirm: context.t('tr_restart_do'),
    );
    if (!ok || !mounted) return;
    // A finished run should not keep sending reminders once it is replaced.
    if (c.isActive) store.setChallengeStatus(c, ChallengeStatus.finished);
    final id = store.restart(c);
    if (mounted) {
      setState(() => _challengeId = id);
      showToast(context, context.t('tr_restarted'), icon: Icons.replay_rounded);
    }
  }

  Future<void> _newChallenge() async {
    final id = await showChallengeEditor(context);
    if (id != null && mounted) setState(() => _challengeId = id);
  }

  Future<void> _switchChallenge(TrackerStore store) async {
    final picked = await showAppSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetHeader(ctx.t('tr_switch')),
          const SizedBox(height: 6),
          GroupCard(children: [
            for (final c in store.challenges)
              OptionTile(
                icon: c.isActive ? Icons.play_circle_rounded : Icons.check_circle_outline_rounded,
                color: c.isActive ? AppColors.mTracker : null,
                title: c.title,
                subtitle: '${ctx.dayLabel(c.start ?? todayDate())} · ${ctx.tr('tr_length_n', {'n': c.days})}',
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ]),
        ]),
      ),
    );
    if (picked != null && mounted) setState(() => _challengeId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TrackerStore>();
    final c = _current(store);

    if (c == null) {
      return AppPage(
        title: context.t('tr_title'),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyView(
                icon: Icons.fact_check_rounded,
                color: AppColors.mTracker,
                title: context.t('tr_none_title'),
                message: context.t('tr_none_msg'),
                actionLabel: context.t('tr_start'),
                onAction: _newChallenge,
              ),
            ),
          ),
        ],
      );
    }

    return AppPage(
      title: c.title,
      subtitle: c.subtitle.isEmpty ? null : c.subtitle,
      actions: [
        if (store.challenges.length > 1)
          IconButton(
            tooltip: context.t('tr_switch'),
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () => _switchChallenge(store),
          ),
        PopupMenuButton<String>(
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'add', child: Text(ctx.t('tr_add_item'))),
            PopupMenuItem(value: 'edit', child: Text(ctx.t('tr_edit_challenge'))),
            PopupMenuItem(value: 'align', child: Text(ctx.t('tr_align'))),
            PopupMenuItem(value: 'restart', child: Text(ctx.t('tr_restart'))),
            PopupMenuItem(value: 'new', child: Text(ctx.t('tr_new'))),
            PopupMenuItem(value: 'mentor', child: Text(ctx.t('tr_mentor_title'))),
            if (c.isActive) PopupMenuItem(value: 'finish', child: Text(ctx.t('tr_finish'))),
            PopupMenuItem(value: 'delete', child: Text(ctx.t('tr_delete_challenge'))),
          ],
          onSelected: (v) => _menu(v, store, c),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            challenge: c,
            store: store,
            onOpen: (status) => _openList(store, c, status: status),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: PillTabs<_View>(
              items: [
                (_View.today, context.t('tr_tab_today')),
                (_View.sheet, context.t('tr_tab_grid')),
                (_View.stats, context.t('tr_tab_stats')),
              ],
              value: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
          ),
        ),
        if (_view == _View.today)
          ..._todaySlivers(store, c)
        else if (_view == _View.stats)
          SliverToBoxAdapter(child: TrackerStats(challenge: c, store: store))
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              // A fixed box rather than SliverFillRemaining: AppPage appends a
              // sliver after this one, so "fill the rest" would let the whole
              // table scroll away while its own scroller fought the page's.
              child: SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.64).clamp(340.0, 680.0),
                child: TrackerGrid(
                  challenge: c,
                  store: store,
                  onTick: (i, d) => _tick(store, c, i, d),
                  onItemTap: (i) => showItemEditor(context, challenge: c, item: i),
                ),
              ),
            ),
          ),
      ],
      fab: _view == _View.today
          ? FloatingActionButton.extended(
              heroTag: 'trackerAdd',
              onPressed: () => showItemEditor(context, challenge: c),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.t('tr_add_item')),
            )
          : null,
    );
  }

  Future<void> _menu(String v, TrackerStore store, Challenge c) async {
    switch (v) {
      case 'add':
        await showItemEditor(context, challenge: c);
        break;
      case 'edit':
        await showChallengeEditor(context, challenge: c);
        break;
      case 'align':
        {
          final ok = await confirmDialog(
            context,
            title: context.t('tr_align'),
            message: context.tr('tr_align_q', {'d': context.dayLabel(c.start ?? todayDate())}),
            confirm: context.t('tr_align_do'),
          );
          if (!ok) return;
          final moved = store.alignItemsToStart(c);
          if (mounted) {
            showToast(context, context.tr('tr_aligned', {'n': moved}),
                icon: Icons.align_horizontal_left_rounded);
          }
          break;
        }
      case 'restart':
        await _restart(store, c);
        break;
      case 'new':
        await _newChallenge();
        break;
      case 'mentor':
        await Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => const MentorScreen()));
        break;
      // Each case gets its own block: every case of a switch shares one
      // scope, so two cases both declaring `ok` would not compile.
      case 'finish':
        {
          final ok = await confirmDialog(context,
              title: context.t('tr_finish_q'), confirm: context.t('tr_finish'));
          if (ok) store.setChallengeStatus(c, ChallengeStatus.finished);
          break;
        }
      case 'delete':
        {
          // A run that has been ticked is a record. It can be finished, but
          // not quietly erased.
          if (store.tickedTotal(c) > 0) {
            await confirmDialog(
              context,
              title: context.t('tr_delete_challenge'),
              message: context.t('tr_delete_locked'),
              confirm: context.t('ok'),
            );
            return;
          }
          final ok = await confirmDialog(
            context,
            title: context.t('tr_delete_challenge'),
            message: context.t('tr_delete_challenge_q'),
            confirm: context.t('delete'),
            danger: true,
          );
          if (ok) {
            store.deleteChallenge(c);
            if (mounted) setState(() => _challengeId = null);
          }
          break;
        }
    }
  }

  List<Widget> _todaySlivers(TrackerStore store, Challenge c) {
    final today = todayDate();
    final items = store.itemsOn(c.id, today);

    if (!c.hasStarted) {
      final left = daysBetween(today, c.start ?? today);
      return [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.hourglass_top_rounded,
            color: AppColors.mTracker,
            title: left == 1 ? context.t('tr_starts_tomorrow') : context.tr('tr_starts_in', {'n': left}),
            message: context.t('tr_template_edit_hint'),
            actionLabel: context.t('tr_add_item'),
            onAction: () => showItemEditor(context, challenge: c),
          ),
        ),
      ];
    }

    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.playlist_add_rounded,
            color: AppColors.mTracker,
            title: context.t('tr_no_items_title'),
            message: context.t('tr_no_items_msg'),
            actionLabel: context.t('tr_add_item'),
            onAction: () => showItemEditor(context, challenge: c),
          ),
        ),
      ];
    }

    // The run is over: close it off properly rather than leaving an empty
    // list that looks like a day with nothing to do.
    if (c.isOver || c.status != ChallengeStatus.active) {
      final tally = store.tally(c);
      return [
        SliverToBoxAdapter(
          child: DhCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('🏁', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr('tr_run_done', {'n': c.days}), style: context.tt.titleMedium),
                    Text(
                      context.tr('tr_run_done_msg', {
                        'p': (tally.rate * 100).round(),
                        'd': store.perfectDays(c),
                      }),
                      style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _restart(store, c),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(context.t('tr_restart')),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => setState(() => _view = _View.stats),
                  child: Text(context.t('tr_tab_stats')),
                ),
              ]),
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ];
    }

    final todo = <TrackerItem>[];
    final done = <TrackerItem>[];
    for (final i in items) {
      (store.isTicked(c.id, i.id, today) ? done : todo).add(i);
    }
    todo.sort((a, b) {
      final da = a.deadlineOn(today);
      final db = b.deadlineOn(today);
      if (da == null && db == null) return a.order.compareTo(b.order);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return [
      if (todo.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionTitle(context.t('tr_to_do'), trailing: Text('${todo.length}'))),
        SliverList.builder(
          itemCount: todo.length,
          itemBuilder: (_, n) => _ItemTile(
            challenge: c,
            item: todo[n],
            day: today,
            store: store,
            onTick: () => _tick(store, c, todo[n], today),
            onEdit: () => showItemEditor(context, challenge: c, item: todo[n]),
          ),
        ),
      ] else
        SliverToBoxAdapter(
          child: DhCard(
            child: Row(children: [
              const Text('🎯', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('tr_all_done_title'), style: context.tt.titleSmall),
                  Text(context.t('tr_all_done_msg'), style: context.tt.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
      if (done.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionTitle(context.t('tr_done_today'), trailing: Text('${done.length}'))),
        SliverList.builder(
          itemCount: done.length,
          itemBuilder: (_, n) => _ItemTile(
            challenge: c,
            item: done[n],
            day: today,
            store: store,
            onTick: () => _tick(store, c, done[n], today),
            onEdit: () => showItemEditor(context, challenge: c, item: done[n]),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ];
  }
}

// -------------------------------------------------------------------- header

/// A figure that opens the list behind it.
class _TapStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  const _TapStat({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: StatBlock(label: label, value: value, color: color),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Challenge challenge;
  final TrackerStore store;
  final void Function(TickStatus status) onOpen;
  const _Header({required this.challenge, required this.store, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final tk = context.tokens;
    final today = todayDate();
    final tally = store.tally(c);
    final pct = tally.rate;
    final todayDone = store.doneOn(c, today);
    final todayTotal = store.expectedOn(c, today);

    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProgressRing(
            value: todayTotal == 0 ? 0 : todayDone / todayTotal,
            size: 54,
            stroke: 6,
            color: AppColors.mTracker,
            child: Text('$todayDone/$todayTotal', style: context.tt.labelSmall),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('tr_day_of', {'n': c.currentDay, 't': c.days}),
                  style: context.tt.titleMedium),
              const SizedBox(height: 2),
              Text(context.fmtDate(today, 'EEEE, d MMMM'),
                  style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (c.assignedByMentor)
                  Pill(context.tr('tr_assigned_by', {'name': c.mentorName}),
                      color: AppColors.mStudy, icon: Icons.school_rounded),
                if (!c.isActive)
                  Pill(context.t(c.status == ChallengeStatus.finished ? 'tr_finished' : 'tr_abandoned'),
                      color: tk.textMuted, icon: Icons.flag_rounded),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        ProgressBar(value: pct, color: AppColors.mTracker),
        const SizedBox(height: 10),
        // Each figure opens the list behind it — tapping "6 missed" should
        // answer which six, and lead straight to filling them in.
        Row(children: [
          Expanded(
            child: StatBlock(
              label: context.t('tr_overall'),
              value: '${(pct * 100).round()}%',
              color: AppColors.mTracker,
            ),
          ),
          Expanded(
            child: _TapStat(
              label: context.t('tr_on_time'),
              value: '${tally.onTime}',
              color: tk.success,
              onTap: () => onOpen(TickStatus.onTime),
            ),
          ),
          Expanded(
            child: _TapStat(
              label: context.t('tr_late'),
              value: '${tally.lateTicks}',
              color: tk.warning,
              onTap: () => onOpen(TickStatus.overdue),
            ),
          ),
          Expanded(
            child: _TapStat(
              label: context.t('tr_missed'),
              value: '${tally.missed}',
              color: tally.missed == 0 ? tk.textMuted : tk.danger,
              onTap: () => onOpen(TickStatus.missed),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- item tile

class _ItemTile extends StatelessWidget {
  final Challenge challenge;
  final TrackerItem item;
  final DateTime day;
  final TrackerStore store;
  final VoidCallback onTick;
  final VoidCallback onEdit;

  const _ItemTile({
    required this.challenge,
    required this.item,
    required this.day,
    required this.store,
    required this.onTick,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = AppColors.swatch(item.color);
    final log = store.logFor(challenge.id, item.id, day);
    final status = store.statusOf(challenge, item, day);
    final n = item.dayNumber(day);
    final closes = log == null ? closesInText(context, item, day) : null;

    final meta = <Widget>[
      if (n != null) Pill(context.tr('tr_day_n', {'n': n}), color: tk.textMuted),
      if (item.isAvoid) Pill(context.t('tr_kind_avoid'), color: tk.transfer, icon: Icons.block_rounded),
      if (log != null)
        TickPill(status, itemColor: color, lateBy: log.lateBy)
      else if (closes != null)
        Pill(closes,
            color: closes == context.t('tr_closed') ? tk.danger : tk.warning,
            icon: Icons.schedule_rounded),
      // Shown only when it actually lagged, so a live tick stays uncluttered.
      if (log != null && log.recordedLater)
        Pill(context.t('tr_recorded_later'), color: tk.transfer, icon: Icons.history_rounded),
    ];

    final when = log?.completedAt;

    return DhCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      onTap: onEdit,
      child: Row(children: [
        IconBadge(emoji: item.emoji, color: color, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.titleSmall?.copyWith(
                  decoration: log != null ? TextDecoration.lineThrough : null,
                  color: log != null ? tk.textMuted : null,
                )),
            const SizedBox(height: 2),
            Text(
              when != null
                  ? context.tr('tr_ticked_at', {'t': context.timeOf(when)})
                  : windowText(context, item),
              style: context.tt.bodySmall?.copyWith(color: tk.textMuted),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: meta),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        TickBox(status: status, color: color, size: 34, onTap: onTick),
      ]),
    );
  }
}

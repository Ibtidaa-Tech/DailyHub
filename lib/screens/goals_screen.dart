import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// Long-term goals with a progress ring you can nudge straight from the list.
///
/// The `goals` node is shared with the money module's savings goals
/// (name/target/entries), so only the records carrying a `title` are shown
/// here. Fields written by either screen are preserved on save.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('goals'),
      builder: (context, snap) {
        final raw = snap.data;
        final goals = (raw ?? const <Map<String, dynamic>>[])
            .where((g) => str(g['title']).trim().isNotEmpty)
            .toList();
        final active = goals.where((g) => _goalPct(g) < 100).toList()..sort(_byDeadline);
        final achieved = goals.where((g) => _goalPct(g) >= 100).toList()
          ..sort((a, b) => str(b['createdAt']).compareTo(str(a['createdAt'])));

        return AppPage(
          title: context.t('m_goals'),
          subtitle: context.t('gl_sub'),
          fab: FloatingActionButton.extended(
            heroTag: 'goalFab',
            onPressed: () => _openGoalEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.t('gl_new')),
          ),
          header: goals.isEmpty
              ? null
              : _GoalsSummary(goals: goals, active: active.length, achieved: achieved.length),
          slivers: [
            if (raw == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 70),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (goals.isEmpty)
              SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.flag_outlined,
                  color: AppColors.mGoals,
                  title: context.t('gl_none'),
                  message: context.t('gl_none_msg'),
                  actionLabel: context.t('gl_new'),
                  onAction: () => _openGoalEditor(context),
                ),
              )
            else ...[
              if (active.isNotEmpty) ...[
                SliverToBoxAdapter(child: SectionTitle(context.t('gl_active'))),
                SliverList.list(
                  children: [
                    for (final g in active) _LifeGoalCard(key: ValueKey('goal_${str(g['id'])}'), goal: g),
                  ],
                ),
              ],
              if (achieved.isNotEmpty) ...[
                SliverToBoxAdapter(child: SectionTitle(context.t('gl_achieved'))),
                SliverList.list(
                  children: [
                    for (final g in achieved) _LifeGoalCard(key: ValueKey('goal_${str(g['id'])}'), goal: g),
                  ],
                ),
              ],
              if (achieved.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text(
                      context.t('gl_nothing_achieved'),
                      textAlign: TextAlign.center,
                      style: context.tt.bodySmall,
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Progress as a whole percentage, however the record stored it.
int _goalPct(Map<String, dynamic> g) {
  final p = toI(g['progress']);
  if (p < 0) return 0;
  return p > 100 ? 100 : p;
}

/// Soonest target date first; goals without one fall to the bottom.
int _byDeadline(Map<String, dynamic> a, Map<String, dynamic> b) {
  final da = parseDay(str(a['deadline']));
  final dbb = parseDay(str(b['deadline']));
  if (da != null && dbb != null) return da.compareTo(dbb);
  if (da != null) return -1;
  if (dbb != null) return 1;
  return _goalPct(b).compareTo(_goalPct(a));
}

/// "On track" / "Falling behind", judged against the time already spent.
(String, Color)? _goalPace(BuildContext context, Map<String, dynamic> g) {
  final deadline = parseDay(str(g['deadline']));
  if (deadline == null) return null;
  final tk = context.tokens;
  final today = todayDate();
  final left = daysBetween(today, deadline);
  if (left < 0) return (context.t('gl_past_due'), tk.danger);
  if (left == 0) return (context.t('gl_due_today'), tk.warning);
  final start = parseDay(str(g['createdAt'])) ?? today;
  final total = daysBetween(start, deadline);
  final gone = daysBetween(start, today);
  if (total <= 0 || gone <= 0) return (context.t('gl_on_track'), tk.success);
  final expected = (gone / total) * 100;
  if (_goalPct(g) + 5 >= expected) return (context.t('gl_on_track'), tk.success);
  return (context.t('gl_behind'), tk.warning);
}

class _GoalsSummary extends StatelessWidget {
  final List<Map<String, dynamic>> goals;
  final int active;
  final int achieved;
  const _GoalsSummary({required this.goals, required this.active, required this.achieved});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final avg = goals.isEmpty
        ? 0
        : (goals.fold<int>(0, (s, g) => s + _goalPct(g)) / goals.length).round();
    return DhCard(
      child: Row(children: [
        Expanded(
          child: StatBlock(
            label: context.t('gl_active'),
            value: '$active',
            color: AppColors.mGoals,
            icon: Icons.flag_rounded,
          ),
        ),
        Container(width: 1, height: 34, color: tk.border),
        Expanded(
          child: StatBlock(
            label: context.t('gl_achieved'),
            value: '$achieved',
            color: tk.success,
            icon: Icons.emoji_events_rounded,
            align: CrossAxisAlignment.center,
          ),
        ),
        Container(width: 1, height: 34, color: tk.border),
        Expanded(
          child: StatBlock(
            label: context.t('gl_avg'),
            value: '$avg%',
            color: tk.textMuted,
            align: CrossAxisAlignment.end,
          ),
        ),
      ]),
    );
  }
}

/// One goal: ring, target date, pace, and a slider that writes on release.
class _LifeGoalCard extends StatefulWidget {
  final Map<String, dynamic> goal;
  const _LifeGoalCard({super.key, required this.goal});

  @override
  State<_LifeGoalCard> createState() => _LifeGoalCardState();
}

class _LifeGoalCardState extends State<_LifeGoalCard> {
  double? _drag;

  @override
  void didUpdateWidget(_LifeGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_goalPct(widget.goal) != _goalPct(oldWidget.goal)) _drag = null;
  }

  void _set(int value) {
    final v = value < 0 ? 0 : (value > 100 ? 100 : value);
    DbService.instance.update('goals', str(widget.goal['id']), {'progress': v});
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final g = widget.goal;
    final value = _drag ?? _goalPct(g).toDouble();
    final pct = value.round();
    final done = pct >= 100;
    final color = done ? tk.success : AppColors.mGoals;
    final deadline = parseDay(str(g['deadline']));
    final pace = done ? null : _goalPace(context, g);

    return SwipeTile(
      swipeKey: ValueKey('goalswipe_${str(g['id'])}'),
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        await _removeGoal(context, g);
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        onTap: () => _openGoalEditor(context, existing: g),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ProgressRing(
              value: value / 100,
              size: 52,
              stroke: 6,
              color: color,
              child: SizedBox(
                width: 34,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$pct%',
                    style: context.tt.labelSmall?.copyWith(color: color, fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  str(g['title']),
                  style: context.tt.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (deadline != null)
                      MetaChip(Icons.event_outlined, context.dayLabel(deadline)),
                    if (done)
                      Pill(context.t('gl_achieved'), color: tk.success, icon: Icons.check_rounded)
                    else if (pace != null)
                      Pill(pace.$1, color: pace.$2),
                  ],
                ),
              ]),
            ),
            if (done)
              IconButton(
                tooltip: context.t('gl_reopen'),
                icon: Icon(Icons.undo_rounded, color: tk.textMuted),
                onPressed: () {
                  _set(90);
                  showUndo(context, context.t('gl_reopened'), () => _set(100));
                },
              ),
          ]),
          if (!done)
            Row(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.t('less'),
                icon: const Icon(Icons.remove_rounded, size: 20),
                onPressed: pct <= 0 ? null : () => _set(pct - 5),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  max: 100,
                  divisions: 20,
                  label: '$pct%',
                  activeColor: color,
                  thumbColor: color,
                  onChanged: (v) => setState(() => _drag = v),
                  onChangeEnd: (v) => _set(v.round()),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.t('more'),
                icon: const Icon(Icons.add_rounded, size: 20),
                onPressed: () => _set(pct + 5),
              ),
            ]),
        ]),
      ),
    );
  }
}

/// Removes a goal, recoverable for a few seconds.
Future<void> _removeGoal(BuildContext context, Map<String, dynamic> goal) async {
  final db = DbService.instance;
  final id = str(goal['id']);
  final data = Map<String, dynamic>.from(goal)..remove('id');
  await db.remove('goals', id);
  if (!context.mounted) return;
  showUndo(context, context.t('gl_deleted'), () => db.set('goals', id, data));
}

/// Add or edit a goal: name, optional target date, starting progress.
Future<void> _openGoalEditor(BuildContext context, {Map<String, dynamic>? existing}) async {
  final ex = existing;
  final db = DbService.instance;
  final title = TextEditingController(text: str(ex?['title']));
  var deadline = parseDay(str(ex?['deadline']));
  var progress = ex == null ? 0 : _goalPct(ex);
  final wasDone = ex != null && _goalPct(ex) >= 100;

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ctx.t(ex == null ? 'gl_new' : 'gl_edit'), style: ctx.tt.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                autofocus: ex == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ctx.t('gl_title_hint'),
                  prefixIcon: const Icon(Icons.flag_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FormFieldButton(
                icon: Icons.event_rounded,
                label: ctx.t('gl_deadline'),
                value: deadline == null ? ctx.t('gl_no_deadline') : ctx.dayLabel(deadline!),
                onTap: () async {
                  final now = DateTime.now();
                  final first = DateTime(now.year - 30);
                  final last = DateTime(now.year + 50);
                  var start = deadline ?? addDays(todayDate(), 30);
                  if (start.isBefore(first)) start = first;
                  if (start.isAfter(last)) start = last;
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: start,
                    firstDate: first,
                    lastDate: last,
                  );
                  if (picked != null) set(() => deadline = dateOnly(picked));
                },
              ),
              if (deadline != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => set(() => deadline = null),
                    child: Text(ctx.t('remove')),
                  ),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(ctx.t('gl_progress'), style: ctx.tt.labelMedium)),
                Text('$progress%',
                    style: ctx.tt.titleMedium?.copyWith(color: AppColors.mGoals)),
              ]),
              Slider(
                value: progress.toDouble(),
                max: 100,
                divisions: 20,
                label: '$progress%',
                activeColor: AppColors.mGoals,
                thumbColor: AppColors.mGoals,
                onChanged: (v) => set(() => progress = v.round()),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in [0, 25, 50, 75, 100])
                  ChoiceChip(
                    label: Text('$v%'),
                    selected: progress == v,
                    onSelected: (_) => set(() => progress = v),
                  ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                if (ex != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(ctx.t('delete')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _removeGoal(context, ex);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final text = title.text.trim();
                    if (text.isEmpty) {
                      showToast(ctx, ctx.t('gl_enter_title'));
                      return;
                    }
                    final created = str(ex?['createdAt']);
                    final data = <String, dynamic>{
                      ...?ex,
                      'title': text,
                      'progress': progress,
                      'deadline': deadline == null ? '' : dayKey(deadline!),
                      'createdAt': created.isEmpty ? nowIso() : created,
                    }..remove('id');
                    if (ex == null) {
                      db.add('goals', data);
                    } else {
                      db.set('goals', str(ex['id']), data);
                    }
                    Navigator.pop(ctx);
                    if (progress >= 100 && !wasDone && context.mounted) {
                      showToast(context, context.t('gl_done_toast'),
                          icon: Icons.emoji_events_rounded);
                    }
                  },
                  child: Text(ctx.t('save')),
                ),
              ]),
            ],
          ),
        ),
      );
    });
  });
  // Dispose after the sheet's exit animation, not while it still uses it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), title.dispose);
  });
}

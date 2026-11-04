import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/life_store.dart';
import '../../data/models.dart';
import '../../ui/kit.dart';
import '../plan/pickers.dart';

/// Habits: tick today (or any recent day), streaks, counts, heatmaps.
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  DateTime _day = todayDate();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitsStore>();
    final today = todayDate();
    final scheduled = store.scheduledOn(_day);
    final rest = store.active.where((h) => !h.isScheduled(_day)).toList();
    final (done, total) = store.progressOn(_day);
    return AppPage(
      title: context.t('m_habits'),
      subtitle: total == 0 ? null : context.tr('x_of_y_done', {'x': done, 'y': total}),
      fab: FloatingActionButton.extended(
        heroTag: 'habitFab',
        onPressed: () => editHabit(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('new_habit')),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _WeekStrip(
            selected: _day,
            onSelect: (d) => setState(() => _day = d),
          ),
        ),
        if (store.active.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.local_fire_department_rounded,
              color: AppColors.mHabits,
              title: context.t('no_habits'),
              message: context.t('no_habits_msg'),
              actionLabel: context.t('new_habit'),
              onAction: () => editHabit(context),
            ),
          ),
        if (scheduled.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(sameDay(_day, today) ? context.t('today') : context.dayLabel(_day))),
          SliverList.list(children: [for (final h in scheduled) HabitTile(habit: h, day: _day)]),
        ],
        if (rest.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('not_scheduled'))),
          SliverList.list(children: [for (final h in rest) HabitTile(habit: h, day: _day, muted: true)]),
        ],
        if (store.habits.any((h) => h.archived))
          SliverToBoxAdapter(
            child: TextButton.icon(
              icon: const Icon(Icons.archive_outlined),
              label: Text(context.t('archived_habits')),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _ArchivedHabits())),
            ),
          ),
      ],
    );
  }

  static const templates = [
    ('💧', 'tpl_water', 'count', 8, 'tpl_unit_glasses'),
    ('📚', 'tpl_read', 'count', 20, 'tpl_unit_pages'),
    ('🏃', 'tpl_exercise', 'check', 1, ''),
    ('🧘', 'tpl_meditate', 'check', 1, ''),
    ('🚶', 'tpl_walk', 'count', 10, 'tpl_unit_ksteps'),
    ('😴', 'tpl_sleep', 'check', 1, ''),
    ('🍎', 'tpl_fruit', 'check', 1, ''),
    ('📵', 'tpl_no_phone', 'check', 1, ''),
    ('✍️', 'tpl_journal', 'check', 1, ''),
    ('🙏', 'tpl_pray', 'check', 1, ''),
  ];

  static Future<void> editHabit(BuildContext context, {Habit? habit}) async {
    final store = context.read<HabitsStore>();
    final h = habit == null ? Habit(color: store.habits.length) : Habit.fromMap({...habit.toMap(), 'id': habit.id});
    final name = TextEditingController(text: h.name);
    final unit = TextEditingController(text: h.unit);
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t(habit == null ? 'new_habit' : 'edit_habit'), style: ctx.tt.titleLarge),
              if (habit == null) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final t in templates)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Text(t.$1),
                          label: Text(ctx.t(t.$2)),
                          onPressed: () => set(() {
                            h.emoji = t.$1;
                            name.text = ctx.t(t.$2);
                            h.kind = t.$3;
                            h.target = t.$4;
                            unit.text = t.$5.isEmpty ? '' : ctx.t(t.$5);
                          }),
                        ),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ctx.t('habit_name_hint'),
                  prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(h.emoji, style: const TextStyle(fontSize: 18))),
                ),
              ),
              const SizedBox(height: 12),
              PillTabs<String>(
                items: [('check', ctx.t('habit_yes_no')), ('count', ctx.t('habit_count'))],
                value: h.kind,
                onChanged: (v) => set(() {
                  h.kind = v;
                  if (v == 'count' && h.target < 2) h.target = 8;
                  if (v == 'check') h.target = 1;
                }),
              ),
              if (h.kind == 'count') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Text(ctx.t('daily_target'), style: ctx.tt.bodyLarge),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: h.target <= 2 ? null : () => set(() => h.target--),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(width: 44, child: Text('${h.target}', textAlign: TextAlign.center, style: ctx.tt.titleLarge)),
                  IconButton.filledTonal(
                    onPressed: h.target >= 999 ? null : () => set(() => h.target++),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: unit,
                  decoration: InputDecoration(hintText: ctx.t('unit_hint'), isDense: true),
                ),
              ],
              const SizedBox(height: 14),
              Text(ctx.t('which_days'), style: ctx.tt.labelMedium),
              const SizedBox(height: 8),
              Row(children: [
                for (var d = 1; d <= 7; d++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: GestureDetector(
                        onTap: () => set(() {
                          final days = h.days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : List.of(h.days);
                          days.contains(d) ? days.remove(d) : days.add(d);
                          days.sort();
                          h.days = days.length == 7 || days.isEmpty ? [] : days;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: h.isScheduled(DateTime(2024, 1, d)) ? ctx.cs.primary : ctx.tokens.subtle,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(names[d - 1],
                              style: ctx.tt.labelLarge?.copyWith(
                                  color: h.isScheduled(DateTime(2024, 1, d)) ? ctx.cs.onPrimary : ctx.tokens.textMuted)),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(h.days.isEmpty ? ctx.t('every_day') : ctx.tn('n_days_week', h.days.length), style: ctx.tt.bodySmall),
              const SizedBox(height: 12),
              OptionTile(
                icon: h.remind.isEmpty ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
                title: h.remind.isEmpty ? ctx.t('no_reminder') : ctx.tr('remind_at', {'t': ctx.timeOfHm(h.remind)}),
                trailing: h.remind.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => set(() => h.remind = '')),
                onTap: () async {
                  final t = await pickTime(ctx, initial: parseHm(h.remind), allowNone: true);
                  if (t != null) set(() => h.remind = t.value == null ? '' : hmKey(t.value!.hour, t.value!.minute));
                },
              ),
              const SizedBox(height: 8),
              ColorDots(value: h.color % AppColors.swatches.length, onChanged: (v) => set(() => h.color = v)),
              const SizedBox(height: 12),
              EmojiGrid(value: h.emoji, onChanged: (v) => set(() => h.emoji = v)),
              const SizedBox(height: 18),
              Row(children: [
                if (habit != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: ctx.tokens.danger),
                    onPressed: () async {
                      final ok = await confirmDialog(ctx, title: ctx.t('delete_habit_q'), message: ctx.t('delete_habit_msg'), danger: true, confirm: ctx.t('delete'));
                      if (!ok) return;
                      store.delete(habit);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                if (habit != null)
                  TextButton(
                    onPressed: () {
                      store.archive(habit, !habit.archived);
                      Navigator.pop(ctx);
                    },
                    child: Text(ctx.t(habit.archived ? 'restore' : 'archive')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    if (name.text.trim().isEmpty) return;
                    h
                      ..name = name.text.trim()
                      ..unit = unit.text.trim();
                    store.save(h);
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

class _WeekStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _WeekStrip({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitsStore>();
    final t0 = todayDate();
    final days = [for (var i = 6; i >= 0; i--) addDays(t0, -i)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        for (final d in days)
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(d),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sameDay(d, selected) ? context.cs.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Text(context.fmtDate(d, 'EEE'), style: context.tt.labelSmall?.copyWith(color: context.tokens.textMuted)),
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final (done, total) = store.progressOn(d);
                    return ProgressRing(
                      value: total == 0 ? 0 : done / total,
                      size: 34,
                      stroke: 4,
                      color: done == total && total > 0 ? context.tokens.success : AppColors.mHabits,
                      child: Text('${d.day}', style: context.tt.labelMedium),
                    );
                  }),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One habit row with its tap control.
class HabitTile extends StatelessWidget {
  final Habit habit;
  final DateTime day;
  final bool muted;
  const HabitTile({super.key, required this.habit, required this.day, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final store = context.read<HabitsStore>();
    final tk = context.tokens;
    final h = habit;
    final color = AppColors.swatch(h.color);
    final v = h.valueOn(day);
    final done = h.doneOn(day);
    final streak = h.streak();
    return DhCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id))),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Opacity(
        opacity: muted ? 0.55 : 1,
        child: Row(children: [
          IconBadge(emoji: h.emoji, color: color, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, style: context.tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Wrap(spacing: 10, children: [
                if (streak > 0) Text('🔥 ${context.tn('day_streak', streak)}', style: context.tt.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                if (h.kind == 'count') Text('$v/${h.target} ${h.unit}'.trim(), style: context.tt.bodySmall),
                if (streak == 0 && h.kind != 'count') Text(context.t('start_streak'), style: context.tt.bodySmall),
              ]),
            ]),
          ),
          GestureDetector(
            onLongPress: h.kind == 'count'
                ? () async {
                    final ctrl = TextEditingController(text: '$v');
                    final r = await showDialog<int>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(h.name),
                        content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: Text(ctx.t('save'))),
                        ],
                      ),
                    );
                    if (r != null) store.setCount(h, day, r);
                  }
                : null,
            child: InkResponse(
              radius: 30,
              onTap: () {
                HapticFeedback.lightImpact();
                store.tap(h, day);
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: h.kind == 'count'
                    ? ProgressRing(
                        value: v / h.target,
                        size: 46,
                        stroke: 5,
                        color: done ? tk.success : color,
                        child: done
                            ? Icon(Icons.check_rounded, color: tk.success, size: 22)
                            : Text('+1', style: context.tt.labelMedium?.copyWith(color: color)),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: done ? tk.success : tk.tint(color),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(done ? Icons.check_rounded : Icons.add_rounded,
                            color: done ? Colors.white : color, size: 26),
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Stats, heatmap and history for one habit.
class HabitDetailScreen extends StatelessWidget {
  final String habitId;
  const HabitDetailScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitsStore>();
    final settings = context.watch<AppSettings>();
    final h = store.byId(habitId);
    if (h == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(context.t('not_found'))));
    }
    final color = AppColors.swatch(h.color);
    final tk = context.tokens;
    return AppPage(
      title: '${h.emoji} ${h.name}',
      subtitle: h.days.isEmpty ? context.t('every_day') : context.tn('n_days_week', h.days.length),
      actions: [
        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _HabitsScreenState.editHabit(context, habit: h)),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Row(children: [
            Expanded(child: _Stat(label: context.t('current_streak'), value: '🔥 ${h.streak()}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: context.t('best_streak'), value: '🏆 ${h.bestStreak()}')),
          ]),
        ),
        SliverToBoxAdapter(
          child: Row(children: [
            Expanded(child: _Stat(label: context.t('last_30_days'), value: '${(h.rate(30) * 100).round()}%')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: context.t('total_done'), value: '${h.totalDone()}')),
          ]),
        ),
        SliverToBoxAdapter(
          child: DhCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('history'), style: context.tt.titleMedium),
              const SizedBox(height: 12),
              Heatmap(
                weeks: MediaQuery.sizeOf(context).width > 600 ? 26 : 17,
                color: color,
                weekStart: settings.weekStart,
                scheduled: h.isScheduled,
                valueOf: (d) => h.target <= 0 ? 0 : h.valueOn(d) / h.target,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text(context.t('less'), style: context.tt.bodySmall),
                const SizedBox(width: 6),
                for (final a in const [0.0, 0.35, 0.65, 1.0])
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: a == 0 ? tk.subtle : color.withValues(alpha: 0.25 + 0.75 * a),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: 3),
                Text(context.t('more_word'), style: context.tt.bodySmall),
              ]),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('last_7_days'))),
        SliverList.list(children: [
          for (var i = 0; i < 7; i++)
            Builder(builder: (context) {
              final d = addDays(todayDate(), -i);
              return HabitTile(habit: h, day: d, muted: !h.isScheduled(d))
                  .withLabel(context, context.dayLabel(d));
            }),
        ]),
      ],
    );
  }
}

extension on HabitTile {
  Widget withLabel(BuildContext context, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 4, top: 6), child: Text(label, style: context.tt.labelMedium)),
        this,
      ]);
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => DhCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: context.tt.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: context.tt.headlineSmall),
        ]),
      );
}

class _ArchivedHabits extends StatelessWidget {
  const _ArchivedHabits();
  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitsStore>();
    final list = store.habits.where((h) => h.archived).toList();
    return AppPage(
      title: context.t('archived_habits'),
      slivers: [
        SliverList.list(children: [
          for (final h in list)
            DhCard(
              onTap: () => _HabitsScreenState.editHabit(context, habit: h),
              child: Row(children: [
                IconBadge(emoji: h.emoji, color: AppColors.swatch(h.color), size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text(h.name, style: context.tt.titleSmall)),
                TextButton(onPressed: () => store.archive(h, false), child: Text(context.t('restore'))),
              ]),
            ),
        ]),
      ],
    );
  }
}

/// Compact horizontal habits row for Home.
class HabitsRow extends StatelessWidget {
  const HabitsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitsStore>();
    final t0 = todayDate();
    final list = store.scheduledOn(t0);
    final tk = context.tokens;
    if (list.isEmpty) {
      return DhCard(
        onTap: () => _HabitsScreenState.editHabit(context),
        child: Row(children: [
          const IconBadge(icon: Icons.local_fire_department_rounded, color: AppColors.mHabits, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Text(context.t('build_habit_cta'), style: context.tt.bodyMedium)),
          Icon(Icons.add_rounded, color: tk.textMuted),
        ]),
      );
    }
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final h = list[i];
          final c = AppColors.swatch(h.color);
          final done = h.doneOn(t0);
          final v = h.valueOn(t0);
          return SizedBox(
            width: 92,
            child: Material(
              color: done ? tk.tint(tk.success) : tk.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: done ? Colors.transparent : tk.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  HapticFeedback.lightImpact();
                  store.tap(h, t0);
                },
                onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id))),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    ProgressRing(
                      value: v / h.target,
                      size: 44,
                      stroke: 4,
                      color: done ? tk.success : c,
                      child: Text(h.emoji, style: const TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(height: 6),
                    Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelSmall?.copyWith(letterSpacing: 0)),
                    Text(
                      h.kind == 'count' ? '$v/${h.target}' : (h.streak() > 0 ? '🔥${h.streak()}' : ' '),
                      style: context.tt.labelSmall?.copyWith(color: tk.textMuted, letterSpacing: 0),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Public entry for other screens (add sheet, onboarding).
Future<void> openHabitEditor(BuildContext context, {Habit? habit}) =>
    _HabitsScreenState.editHabit(context, habit: habit);

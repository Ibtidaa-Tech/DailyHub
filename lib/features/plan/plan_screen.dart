import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/quick_parse.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/agenda.dart';
import '../../data/extras_store.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import '../search/search_screen.dart';
import '../shell/shell.dart';
import 'calendar_view.dart';
import 'lists_screen.dart';
import 'matrix_view.dart';
import 'plan_tiles.dart';
import 'reminder_editor.dart';
import 'task_editor.dart';

enum PlanView { today, upcoming, calendar, matrix }

class PlanScreen extends StatefulWidget {
  final PlanView? initialView;
  final bool standalone;
  const PlanScreen({super.key, this.initialView, this.standalone = false});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late PlanView _view = widget.initialView ?? PlanView.today;
  String? _listFilter; // null = all
  bool _showDone = false;
  bool _showOverdue = true;
  DateTime _calDay = todayDate();

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final money = context.watch<MoneyStore>();
    final extras = context.watch<ExtrasStore?>();
    final settings = context.watch<AppSettings>();
    final ws = context.watch<WorkspaceProvider>();
    final shell = context.watch<ShellController?>();
    if (shell?.planRequest != null) {
      _view = shell!.planRequest!;
      shell.planRequest = null;
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PillTabs<PlanView>(
            items: [
              (PlanView.today, context.t('today')),
              (PlanView.upcoming, context.t('upcoming')),
              (PlanView.calendar, context.t('calendar')),
              (PlanView.matrix, context.t('matrix')),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
        ),
      ),
      if ((_view == PlanView.today || _view == PlanView.upcoming) && plan.lists.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ChipRow<String?>(
              items: [
                (null, context.t('all')),
                ('', context.t('inbox')),
                for (final l in plan.lists) (l.id, '${l.emoji} ${l.name}'),
              ],
              value: _listFilter,
              onSelected: (v) => setState(() => _listFilter = v),
            ),
          ),
        ),
      ...switch (_view) {
        PlanView.today => _today(context, plan, money, extras, ws),
        PlanView.upcoming => _upcoming(context, plan, money, extras, ws),
        PlanView.calendar => [
            SliverToBoxAdapter(
              child: CalendarView(
                selected: _calDay,
                weekStart: settings.weekStart,
                onSelect: (d) => setState(() => _calDay = d),
              ),
            ),
            ..._dayList(context, _calDay, plan, money, extras, ws, header: true),
          ],
        PlanView.matrix => [const SliverToBoxAdapter(child: MatrixView())],
      },
    ];

    return AppPage(
      title: context.t('tab_plan'),
      subtitle: context.fmtDate(DateTime.now(), 'EEEE, d MMMM'),
      showBack: widget.standalone,
      actions: [
        IconButton(
          tooltip: context.t('search'),
          icon: const Icon(Icons.search_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
        IconButton(
          tooltip: context.t('m_lists'),
          icon: const Icon(Icons.folder_open_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListsScreen())),
        ),
      ],
      fab: widget.standalone && ws.canAdd
          ? FloatingActionButton(
              onPressed: () => openTaskEditor(context, day: _view == PlanView.calendar ? _calDay : todayDate()),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      slivers: slivers,
    );
  }

  bool _inFilter(Task t) => _listFilter == null || t.list == _listFilter;

  // ------------------------------------------------------------- today

  List<Widget> _today(BuildContext context, PlanStore plan, MoneyStore money, ExtrasStore? extras, WorkspaceProvider ws) {
    final t0 = todayDate();
    final overdue = plan.overdue.where(_inFilter).toList();
    final overdueRem = plan.overdueReminders;
    final items = Agenda.forDay(t0, plan: plan, money: money, extras: extras, includeDone: false)
        .where((i) => i.kind != AgendaKind.task || _inFilter(i.ref as Task))
        .where((i) => !(i.kind == AgendaKind.task && overdue.contains(i.ref)))
        .toList();
    final doneToday = plan.completedToday.where(_inFilter).toList();
    final dueTotal = items.where((i) => i.kind == AgendaKind.task).length + doneToday.length;
    final progress = dueTotal == 0 ? 0.0 : doneToday.length / dueTotal;

    return [
      if (ws.canAdd) SliverToBoxAdapter(child: _InlineAdd(day: t0, list: _listFilter)),
      SliverToBoxAdapter(
        child: DhCard(
          child: Row(children: [
            ProgressRing(
              value: progress,
              size: 54,
              stroke: 6,
              color: context.tokens.success,
              child: Text('${(progress * 100).round()}%', style: context.tt.labelSmall),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  dueTotal == 0
                      ? context.t('nothing_due_today')
                      : context.tr('x_of_y_done', {'x': doneToday.length, 'y': dueTotal}),
                  style: context.tt.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  overdue.isEmpty ? context.t('keep_going') : context.tn('overdue_count', overdue.length),
                  style: context.tt.bodySmall?.copyWith(color: overdue.isEmpty ? null : context.tokens.danger),
                ),
              ]),
            ),
          ]),
        ),
      ),
      if (overdue.isNotEmpty || overdueRem.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionTitle(
            '${context.t('overdue')} · ${overdue.length + overdueRem.length}',
            action: ws.canAdd && overdue.isNotEmpty ? context.t('move_to_today') : null,
            onAction: () {
              plan.rescheduleAll(overdue, t0);
              showToast(context, context.t('moved_to_today'), icon: Icons.today_rounded);
            },
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(_showOverdue ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              onPressed: () => setState(() => _showOverdue = !_showOverdue),
            ),
          ),
        ),
        if (_showOverdue)
          SliverList.list(children: [
            for (final t in overdue) TaskTile(task: t),
            for (final r in overdueRem) ReminderTile(reminder: r),
          ]),
      ],
      SliverToBoxAdapter(child: SectionTitle('${context.t('today')} · ${context.fmtDate(t0, 'd MMM')}')),
      if (items.isEmpty)
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.wb_sunny_rounded,
            color: AppColors.mReminders,
            title: context.t('all_clear'),
            message: context.t('all_clear_msg'),
            compact: true,
          ),
        )
      else
        SliverList.list(children: [for (final i in items) _row(context, i, t0)]),
      if (doneToday.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionTitle(
            '${context.t('completed')} · ${doneToday.length}',
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              onPressed: () => setState(() => _showDone = !_showDone),
            ),
          ),
        ),
        if (_showDone) SliverList.list(children: [for (final t in doneToday) TaskTile(task: t, showDate: false)]),
      ],
    ];
  }

  Widget _row(BuildContext context, AgendaItem i, DateTime day) {
    switch (i.kind) {
      case AgendaKind.task:
        return TaskTile(task: i.ref as Task, showDate: false);
      case AgendaKind.reminder:
        return ReminderTile(reminder: i.ref as Reminder, showDate: false, occurrence: i.time);
      default:
        return EventTile(item: i);
    }
  }

  // ---------------------------------------------------------- upcoming

  List<Widget> _upcoming(BuildContext context, PlanStore plan, MoneyStore money, ExtrasStore? extras, WorkspaceProvider ws) {
    final t0 = todayDate();
    final out = <Widget>[
      if (ws.canAdd) SliverToBoxAdapter(child: _InlineAdd(day: addDays(t0, 1), list: _listFilter)),
    ];
    var any = false;
    for (var i = 0; i < 30; i++) {
      final d = addDays(t0, i);
      final items = Agenda.forDay(d, plan: plan, money: money, extras: extras, includeDone: false)
          .where((x) => x.kind != AgendaKind.task || _inFilter(x.ref as Task))
          .where((x) => !(x.kind == AgendaKind.reminder && (x.ref as Reminder).repeat == 'daily' && i > 0))
          .toList();
      if (items.isEmpty) continue;
      any = true;
      out.add(SliverToBoxAdapter(child: _DayHeader(day: d, onAdd: ws.canAdd ? () => openTaskEditor(context, day: d, list: _listFilter) : null)));
      out.add(SliverList.list(children: [for (final it in items) _row(context, it, d)]));
    }
    final later = plan.open.where((t) => t.dueDate != null && t.dueDate!.isAfter(addDays(t0, 29)) && _inFilter(t)).toList();
    if (later.isNotEmpty) {
      any = true;
      out.add(SliverToBoxAdapter(child: SectionTitle('${context.t('later')} · ${later.length}')));
      out.add(SliverList.list(children: [for (final t in later) TaskTile(task: t)]));
    }
    final someday = plan.noDate.where(_inFilter).toList();
    if (someday.isNotEmpty) {
      any = true;
      out.add(SliverToBoxAdapter(child: SectionTitle('${context.t('someday')} · ${someday.length}')));
      out.add(SliverList.list(children: [for (final t in someday) TaskTile(task: t)]));
    }
    if (!any) {
      out.add(SliverToBoxAdapter(
        child: EmptyView(
          icon: Icons.event_available_rounded,
          title: context.t('nothing_upcoming'),
          message: context.t('nothing_upcoming_msg'),
          actionLabel: ws.canAdd ? context.t('add_task') : null,
          onAction: () => openTaskEditor(context, day: addDays(t0, 1)),
        ),
      ));
    }
    return out;
  }

  List<Widget> _dayList(BuildContext context, DateTime day, PlanStore plan, MoneyStore money, ExtrasStore? extras,
      WorkspaceProvider ws,
      {bool header = false}) {
    final items = Agenda.forDay(day, plan: plan, money: money, extras: extras);
    return [
      if (header)
        SliverToBoxAdapter(
          child: _DayHeader(day: day, onAdd: ws.canAdd ? () => _addFor(context, day) : null),
        ),
      if (items.isEmpty)
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.event_available_rounded,
            title: context.t('free_day'),
            message: context.t('free_day_msg'),
            compact: true,
          ),
        )
      else
        SliverList.list(children: [for (final i in items) _row(context, i, day)]),
    ];
  }

  Future<void> _addFor(BuildContext context, DateTime day) async {
    final choice = await showAppSheet<String>(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(ctx.dayLabel(day)),
            OptionTile(icon: Icons.check_circle_outline_rounded, color: AppColors.mTasks, title: ctx.t('task'), onTap: () => Navigator.pop(ctx, 'task')),
            OptionTile(icon: Icons.notifications_active_outlined, color: AppColors.mReminders, title: ctx.t('reminder'), onTap: () => Navigator.pop(ctx, 'rem')),
          ]),
        ),
      );
    });
    if (!context.mounted) return;
    if (choice == 'task') openTaskEditor(context, day: day);
    if (choice == 'rem') {
      final now = DateTime.now();
      openReminderEditor(context, when: DateTime(day.year, day.month, day.day, sameDay(day, now) ? now.hour + 1 : 9));
    }
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final VoidCallback? onAdd;
  const _DayHeader({required this.day, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isToday = sameDay(day, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 4),
      child: Row(children: [
        Text(context.dayLabel(day),
            style: context.tt.titleMedium?.copyWith(color: isToday ? context.cs.primary : null)),
        const SizedBox(width: 8),
        Text(context.fmtDate(day, 'd MMM'), style: context.tt.bodySmall),
        const Spacer(),
        if (onAdd != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_rounded, color: context.tokens.textMuted),
            onPressed: onAdd,
          ),
      ]),
    );
  }
}

/// "Add a task…" row. Understands natural language; Enter saves.
class _InlineAdd extends StatefulWidget {
  final DateTime day;
  final String? list;
  const _InlineAdd({required this.day, this.list});
  @override
  State<_InlineAdd> createState() => _InlineAddState();
}

class _InlineAddState extends State<_InlineAdd> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    final p = QuickParse.parse(text);
    final d = p.date ?? widget.day;
    final t = Task(
      title: p.title.isEmpty ? text : p.title,
      date: dayKey(d),
      time: p.hasTime && p.date != null ? hmOf(p.date!) : '',
      priority: p.priority,
      repeat: p.repeat,
      tags: p.tags,
      list: widget.list ?? '',
    );
    context.read<PlanStore>().saveTask(t);
    _c.clear();
    _focus.requestFocus();
    showToast(context, '${context.t('task_added')} · ${context.dayLabel(d)}', icon: Icons.check_circle_rounded);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _c,
        focusNode: _focus,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: context.t('inline_add_hint'),
          prefixIcon: Icon(Icons.add_circle_outline_rounded, color: context.cs.primary),
          suffixIcon: IconButton(
            icon: const Icon(Icons.open_in_full_rounded, size: 20),
            tooltip: context.t('more_options'),
            onPressed: () {
              final text = _c.text;
              _c.clear();
              openTaskEditor(context, day: widget.day, list: widget.list, initialTitle: text.isEmpty ? null : text);
            },
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

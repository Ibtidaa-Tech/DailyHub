import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import 'plan_tiles.dart';
import 'task_editor.dart';

/// Eisenhower priority matrix.
/// Important = High/Medium priority. Urgent = overdue or due within 2 days.
class MatrixView extends StatelessWidget {
  const MatrixView({super.key});

  static bool important(Task t) => t.priority == Prio.high || t.priority == Prio.medium;

  static bool urgent(Task t) {
    final d = t.dueDate;
    if (d == null) return false;
    return daysBetween(DateTime.now(), d) <= 1;
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final open = plan.open;
    final q1 = open.where((t) => urgent(t) && important(t)).toList();
    final q2 = open.where((t) => !urgent(t) && important(t)).toList();
    final q3 = open.where((t) => urgent(t) && !important(t)).toList();
    final q4 = open.where((t) => !urgent(t) && !important(t)).toList();

    final quads = [
      _Quad('mx_do', 'mx_do_hint', Icons.local_fire_department_rounded, const Color(0xFFE5484D), q1, Prio.high, 0),
      _Quad('mx_schedule', 'mx_schedule_hint', Icons.event_rounded, const Color(0xFF4F7DF3), q2, Prio.medium, 3),
      _Quad('mx_quick', 'mx_quick_hint', Icons.bolt_rounded, const Color(0xFFF59E0B), q3, Prio.low, 0),
      _Quad('mx_later', 'mx_later_hint', Icons.inventory_2_outlined, const Color(0xFF64748B), q4, Prio.none, -1),
    ];

    return LayoutBuilder(builder: (context, c) {
      final two = c.maxWidth >= 560;
      final cards = quads.map((q) => _QuadCard(q: q)).toList();
      if (two) {
        return Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[2]), const SizedBox(width: 10), Expanded(child: cards[3])]),
        ]);
      }
      return Column(children: cards);
    });
  }
}

class _Quad {
  final String titleKey;
  final String hintKey;
  final IconData icon;
  final Color color;
  final List<Task> tasks;
  final String prio;
  final int dayOffset; // -1 = no date
  const _Quad(this.titleKey, this.hintKey, this.icon, this.color, this.tasks, this.prio, this.dayOffset);
}

class _QuadCard extends StatelessWidget {
  final _Quad q;
  const _QuadCard({required this.q});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>();
    return DhCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(icon: q.icon, color: q.color, size: 32, radius: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t(q.titleKey), style: context.tt.titleSmall),
              Text(context.t(q.hintKey), style: context.tt.bodySmall),
            ]),
          ),
          Pill('${q.tasks.length}', color: q.color),
          if (ws.canAdd)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: () {
                final t0 = todayDate();
                openTaskEditor(context, day: q.dayOffset < 0 ? null : addDays(t0, q.dayOffset), priority: q.prio);
              },
            ),
        ]),
        const SizedBox(height: 6),
        if (q.tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Text(context.t('mx_empty'), style: context.tt.bodySmall),
          )
        else
          ...q.tasks.take(6).map((t) => TaskTile(task: t, dense: true)),
        if (q.tasks.length > 6)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(context.tr('and_n_more', {'n': q.tasks.length - 6}), style: context.tt.bodySmall),
          ),
      ]),
    );
  }
}

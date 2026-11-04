import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/student_store.dart';
import '../../ui/kit.dart';
import 'attendance_view.dart';
import 'student_editors.dart';
import 'timetable_view.dart';

enum StudentView { today, timetable, attendance, grades }

/// Timetable, attendance and coursework in one place.
class StudentScreen extends StatefulWidget {
  final StudentView initialView;
  const StudentScreen({super.key, this.initialView = StudentView.today});

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  late StudentView _view = widget.initialView;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StudentStore>();
    return AppPage(
      title: context.t('m_student'),
      subtitle: _subtitle(context, s),
      actions: [
        IconButton(
          tooltip: context.t('add'),
          icon: const Icon(Icons.add_rounded),
          onPressed: () => _add(context, s),
        ),
      ],
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: PillTabs<StudentView>(
          items: [
            (StudentView.today, context.t('today')),
            (StudentView.timetable, context.t('st_timetable')),
            (StudentView.attendance, context.t('st_attendance')),
            (StudentView.grades, context.t('st_grades')),
          ],
          value: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
      ),
      slivers: switch (_view) {
        StudentView.today => todaySlivers(context, s),
        StudentView.timetable => timetableSlivers(context, s),
        StudentView.attendance => attendanceSlivers(context, s),
        StudentView.grades => gradesSlivers(context, s),
      },
    );
  }

  String? _subtitle(BuildContext context, StudentStore s) {
    switch (_view) {
      case StudentView.attendance:
        final (_, t) = s.overall;
        if (t == 0) return null;
        return context.tr('st_overall_pct', {'p': (s.overallRate * 100).round()});
      case StudentView.grades:
        final (cg, credits) = s.cgpa;
        if (credits == 0) return null;
        return context.tr('st_cgpa_is', {'v': cg.toStringAsFixed(2)});
      default:
        return context.fmtDate(DateTime.now(), 'EEEE, d MMMM');
    }
  }

  void _add(BuildContext context, StudentStore s) {
    switch (_view) {
      case StudentView.today:
      case StudentView.timetable:
        editClass(context);
      case StudentView.attendance:
        addSubjectForAttendance(context);
      case StudentView.grades:
        editSubject(context);
    }
  }
}

// ----------------------------------------------------------------- today

List<Widget> todaySlivers(BuildContext context, StudentStore s) {
  final today = todayDate();
  final classes = s.classesOn(today)..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final due = s.assignmentsDueOn(today);
  final overdue = s.overdueAssignments;
  final soon = s.openAssignments
      .where((a) => a.dueDate != null && a.dueDate!.isAfter(today) && daysBetween(today, a.dueDate!) <= 7)
      .toList();
  final nowM = DateTime.now().hour * 60 + DateTime.now().minute;

  return [
    if (classes.isEmpty && due.isEmpty && overdue.isEmpty && soon.isEmpty)
      SliverToBoxAdapter(
        child: EmptyView(
          icon: Icons.school_rounded,
          color: AppColors.mStudy,
          title: context.t('st_no_classes_today'),
          message: context.t('st_no_classes_msg'),
          actionLabel: context.t('st_add_class'),
          onAction: () => editClass(context),
        ),
      ),
    if (classes.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionTitle(context.tn('st_n_classes', classes.length))),
      SliverList.list(
        children: [
          for (final k in classes)
            ClassCard(
              klass: k,
              day: today,
              status: s.statusOf(k, today),
              isNow: nowM >= k.startMinutes && nowM < k.endMinutes,
              isPast: nowM >= k.endMinutes,
              onMark: (status) => s.markClass(k, today, status),
              onEdit: () => editClass(context, klass: k),
            ),
        ],
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(context.t('st_mark_hint'), style: context.tt.bodySmall),
        ),
      ),
    ],
    if (overdue.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionTitle(context.t('st_overdue_work'))),
      SliverList.list(children: [for (final a in overdue) AssignmentTile(assignment: a)]),
    ],
    if (due.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionTitle(context.t('st_due_today'))),
      SliverList.list(children: [for (final a in due) AssignmentTile(assignment: a)]),
    ],
    if (soon.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionTitle(context.t('st_due_soon'))),
      SliverList.list(children: [for (final a in soon) AssignmentTile(assignment: a)]),
    ],
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.assignment_outlined, size: 18),
          label: Text(context.t('st_add_assignment')),
          onPressed: () => editAssignment(context),
        ),
      ),
    ),
    if (s.assignments.any((a) => a.done))
      SliverToBoxAdapter(
        child: Center(
          child: TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AssignmentsScreen())),
            child: Text(context.t('st_all_assignments')),
          ),
        ),
      ),
  ];
}

// ------------------------------------------------------------ assignments

/// One row for a piece of coursework.
class AssignmentTile extends StatelessWidget {
  final Assignment assignment;
  final bool showSubject;
  const AssignmentTile({super.key, required this.assignment, this.showSubject = true});

  @override
  Widget build(BuildContext context) {
    final s = context.read<StudentStore>();
    final a = assignment;
    final tk = context.tokens;
    final d = a.dueDate;
    final left = a.daysLeft;
    final Color dueColor = a.isOverdue
        ? tk.danger
        : (left != null && left <= 1 ? tk.warning : tk.textMuted);
    return SwipeTile(
      swipeKey: ValueKey('asg_${a.id}'),
      rightIcon: a.done ? Icons.undo_rounded : Icons.check_rounded,
      rightColor: tk.success,
      rightLabel: context.t(a.done ? 'reopen' : 'done'),
      onSwipeRight: () async {
        s.toggleAssignment(a);
        return false;
      },
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        final data = s.deleteAssignment(a);
        if (context.mounted) {
          showUndo(context, context.t('st_assignment_deleted'),
              () => s.restore('assignments', a.id, data));
        }
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        onTap: () => editAssignment(context, assignment: a),
        child: Row(children: [
          IconButton(
            icon: Icon(a.done ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: a.done ? tk.success : tk.textFaint),
            onPressed: () => s.toggleAssignment(a),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                a.title.isEmpty ? context.t('st_untitled_work') : a.title,
                style: context.tt.titleSmall?.copyWith(
                  decoration: a.done ? TextDecoration.lineThrough : null,
                  color: a.done ? tk.textFaint : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (showSubject && a.subject.isNotEmpty)
                  MetaChip(Icons.menu_book_outlined, a.subject, color: AppColors.mStudy),
                if (d != null)
                  MetaChip(
                    Icons.event_outlined,
                    a.isOverdue
                        ? context.tn('days_overdue', -(left ?? 0))
                        : context.dayLabel(d, short: true),
                    color: dueColor,
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Every assignment, including the finished ones.
class AssignmentsScreen extends StatelessWidget {
  const AssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StudentStore>();
    final open = s.assignments.where((a) => !a.done).toList();
    final done = s.assignments.where((a) => a.done).toList();
    return AppPage(
      title: context.t('st_assignments'),
      subtitle: context.tn('n_tasks', open.length),
      fab: FloatingActionButton.extended(
        onPressed: () => editAssignment(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('st_add_assignment')),
      ),
      slivers: [
        if (s.assignments.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.assignment_outlined,
              color: AppColors.mStudy,
              title: context.t('st_no_assignments'),
              message: context.t('st_no_assignments_msg'),
            ),
          ),
        if (open.isNotEmpty)
          SliverList.list(children: [for (final a in open) AssignmentTile(assignment: a)]),
        if (done.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle('${context.t('completed')} · ${done.length}')),
          SliverList.list(children: [for (final a in done) AssignmentTile(assignment: a)]),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------- grades

List<Widget> gradesSlivers(BuildContext context, StudentStore s) {
  final (cg, credits) = s.cgpa;
  final graded = s.subjects.where((x) => kGradePoints.containsKey(x.grade)).length;
  return [
    if (s.subjects.isEmpty)
      SliverToBoxAdapter(
        child: EmptyView(
          icon: Icons.workspace_premium_outlined,
          color: AppColors.mStudy,
          title: context.t('st_no_subjects'),
          message: context.t('st_no_subjects_msg'),
          actionLabel: context.t('st_add_subject'),
          onAction: () => editSubject(context),
        ),
      )
    else ...[
      SliverToBoxAdapter(
        child: DhCard(
          child: Row(children: [
            ProgressRing(
              value: cg / 10,
              size: 76,
              stroke: 7,
              color: AppColors.mStudy,
              child: Text(credits == 0 ? '—' : cg.toStringAsFixed(2), style: context.tt.titleMedium),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('st_cgpa'), style: context.tt.titleMedium),
                const SizedBox(height: 2),
                Text(
                  credits == 0
                      ? context.t('st_cgpa_hint')
                      : context.tr('st_from_credits', {'n': _num(credits), 'g': graded}),
                  style: context.tt.bodySmall,
                ),
              ]),
            ),
          ]),
        ),
      ),
      SliverToBoxAdapter(child: SectionTitle(context.t('st_subjects'))),
      SliverList.list(
        children: [
          for (final sub in s.subjects)
            DhCard(
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => editSubject(context, subject: sub),
              child: Row(children: [
                IconBadge(
                  emoji: sub.grade.isEmpty ? '📘' : null,
                  icon: Icons.workspace_premium_rounded,
                  color: AppColors.swatch(sub.color),
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sub.name, style: context.tt.titleSmall),
                    Text(
                      [
                        if (sub.code.isNotEmpty) sub.code,
                        context.tr('st_n_credits', {'n': _num(sub.credits)}),
                      ].join(' · '),
                      style: context.tt.bodySmall,
                    ),
                  ]),
                ),
                if (sub.grade.isEmpty)
                  Text(context.t('st_no_grade'), style: context.tt.bodySmall)
                else
                  Pill(sub.grade, color: AppColors.swatch(sub.color), filled: true),
              ]),
            ),
        ],
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(context.t('st_add_subject')),
            onPressed: () => editSubject(context),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(context.t('st_grade_scale'), style: context.tt.bodySmall),
        ),
      ),
    ],
  ];
}

String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

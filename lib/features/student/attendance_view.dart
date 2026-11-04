import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/student_store.dart';
import '../../ui/kit.dart';
import 'student_editors.dart';

/// Colour for an attendance rate against the required target.
Color attendanceColor(BuildContext context, double rate, double target) {
  final tk = context.tokens;
  if (rate >= target) return tk.success;
  if (rate >= target - 0.08) return tk.warning;
  return tk.danger;
}

List<Widget> attendanceSlivers(BuildContext context, StudentStore s) {
  final settings = context.watch<AppSettings>();
  final target = settings.attendanceTarget / 100;
  final (attended, total) = s.overall;
  final rate = s.overallRate;

  if (s.attendance.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: EmptyView(
          icon: Icons.fact_check_outlined,
          color: AppColors.mStudy,
          title: context.t('st_no_attendance'),
          message: context.t('st_no_attendance_msg'),
          actionLabel: context.t('st_track_subject'),
          onAction: () => addSubjectForAttendance(context),
        ),
      ),
    ];
  }

  return [
    SliverToBoxAdapter(child: _OverallCard(attended: attended, total: total, rate: rate, target: target)),
    SliverToBoxAdapter(child: SectionTitle(context.t('st_by_subject'))),
    SliverList.list(
      children: [
        for (final a in s.attendance) _SubjectAttendanceCard(record: a, target: target),
      ],
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(context.t('st_track_subject')),
          onPressed: () => addSubjectForAttendance(context),
        ),
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(context.t('st_attendance_hint'), style: context.tt.bodySmall),
      ),
    ),
  ];
}

class _OverallCard extends StatelessWidget {
  final int attended;
  final int total;
  final double rate;
  final double target;
  const _OverallCard({
    required this.attended,
    required this.total,
    required this.rate,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettings>();
    final color = attendanceColor(context, rate, target);
    final pct = total == 0 ? 0 : (rate * 100).round();
    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProgressRing(
            value: rate,
            size: 78,
            stroke: 8,
            color: color,
            child: Text('$pct%', style: context.tt.titleMedium),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('st_overall'), style: context.tt.titleMedium),
              const SizedBox(height: 2),
              Text(context.tr('st_attended_of', {'a': attended, 'b': total}),
                  style: context.tt.bodySmall),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pickTarget(context, settings),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.flag_outlined, size: 15, color: context.cs.primary),
                    const SizedBox(width: 5),
                    Text(
                      context.tr('st_target_is', {'p': settings.attendanceTarget}),
                      style: context.tt.labelMedium?.copyWith(color: context.cs.primary),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }

  Future<void> _pickTarget(BuildContext context, AppSettings settings) async {
    final picked = await showAppSheet<int>(context, builder: (ctx) {
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('st_required_attendance'), subtitle: ctx.t('st_required_sub')),
          for (final p in [60, 65, 70, 75, 80, 85, 90])
            OptionTile(
              icon: Icons.flag_outlined,
              title: '$p%',
              color: p == settings.attendanceTarget ? ctx.cs.primary : null,
              trailing: p == settings.attendanceTarget
                  ? Icon(Icons.check_circle_rounded, color: ctx.cs.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, p),
            ),
          const SizedBox(height: 8),
        ]),
      );
    });
    if (picked != null) settings.setAttendanceTarget(picked);
  }
}

class _SubjectAttendanceCard extends StatelessWidget {
  final Attendance record;
  final double target;
  const _SubjectAttendanceCard({required this.record, required this.target});

  @override
  Widget build(BuildContext context) {
    final s = context.read<StudentStore>();
    final tk = context.tokens;
    final a = record;
    final color = attendanceColor(context, a.rate, target);
    final safe = a.rate >= target;
    final canSkip = a.canSkip(target);
    final mustAttend = a.mustAttend(target);

    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => editAttendanceBase(context, a),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(a.subject, style: context.tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text('${a.percent}%', style: context.tt.titleMedium?.copyWith(color: color)),
        ]),
        const SizedBox(height: 6),
        ProgressBar(value: a.rate, color: color, height: 7),
        const SizedBox(height: 6),
        Row(children: [
          Text(context.tr('st_attended_of', {'a': a.attended, 'b': a.total}), style: context.tt.bodySmall),
          const Spacer(),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('st_mark_present'),
            icon: const Icon(Icons.add_rounded, size: 18),
            onPressed: () => s.bumpAttendance(a.subject, present: true),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('st_mark_absent'),
            icon: const Icon(Icons.remove_rounded, size: 18),
            onPressed: () => s.bumpAttendance(a.subject, present: false),
          ),
        ]),
        if (a.total > 0) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: tk.tint(safe ? tk.success : tk.danger),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(safe ? Icons.sentiment_satisfied_rounded : Icons.warning_amber_rounded,
                  size: 18, color: safe ? tk.success : tk.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  safe
                      ? (canSkip > 0
                          ? context.tn('st_can_skip', canSkip)
                          : context.t('st_cant_skip'))
                      : context.tn('st_must_attend', mustAttend),
                  style: context.tt.labelMedium?.copyWith(color: safe ? tk.success : tk.danger),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

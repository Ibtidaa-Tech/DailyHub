import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/student_store.dart';
import '../../ui/kit.dart';
import 'student_editors.dart';

/// Translated short day name for a stored day key ('Mon' → 'सोम').
String dayLabelOf(BuildContext context, String key) => context.t('day_${key.toLowerCase()}');

List<Widget> timetableSlivers(BuildContext context, StudentStore s) =>
    [SliverToBoxAdapter(child: _Timetable(store: s))];

class _Timetable extends StatefulWidget {
  final StudentStore store;
  const _Timetable({required this.store});
  @override
  State<_Timetable> createState() => _TimetableState();
}

class _TimetableState extends State<_Timetable> {
  late String _day = dayKeyOfWeekday(DateTime.now().weekday);

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final todayKey = dayKeyOfWeekday(DateTime.now().weekday);
    final classes = s.classes.where((c) => c.day == _day).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 74,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final k in kDayKeys)
              _DayChip(
                label: dayLabelOf(context, k),
                count: s.classes.where((c) => c.day == k).length,
                selected: k == _day,
                isToday: k == todayKey,
                onTap: () => setState(() => _day = k),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (classes.isEmpty)
        EmptyView(
          icon: Icons.free_breakfast_outlined,
          color: AppColors.mStudy,
          title: context.t('st_free_day'),
          message: context.t('st_free_day_msg'),
          actionLabel: context.t('st_add_class'),
          onAction: () => editClass(context, day: _day),
          compact: true,
        )
      else
        for (final k in classes)
          ClassCard(
            klass: k,
            day: _nextDateFor(k.day),
            status: '',
            showMarks: false,
            onEdit: () => editClass(context, klass: k),
          ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(context.t('st_add_class')),
        onPressed: () => editClass(context, day: _day),
      ),
    ]);
  }

  /// The next calendar date that falls on [dayKey], today included.
  DateTime _nextDateFor(String dayKey) {
    final want = kDayKeys.indexOf(dayKey) + 1;
    final t0 = todayDate();
    final diff = (want - t0.weekday) % 7;
    return addDays(t0, diff);
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;
  const _DayChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tk = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? cs.primary : tk.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? cs.primary : (isToday ? cs.primary : tk.border),
                width: isToday && !selected ? 1.5 : 1,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                label,
                style: context.tt.labelLarge?.copyWith(
                  color: selected ? cs.onPrimary : (isToday ? cs.primary : null),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                count == 0 ? '—' : '$count',
                style: context.tt.bodySmall?.copyWith(
                  color: selected ? cs.onPrimary.withValues(alpha: 0.85) : tk.textMuted,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One class, with optional present / absent / cancelled buttons.
class ClassCard extends StatelessWidget {
  final Klass klass;
  final DateTime day;
  final String status;
  final bool isNow;
  final bool isPast;
  final bool showMarks;
  final void Function(String status)? onMark;
  final VoidCallback? onEdit;

  const ClassCard({
    super.key,
    required this.klass,
    required this.day,
    this.status = '',
    this.isNow = false,
    this.isPast = false,
    this.showMarks = true,
    this.onMark,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final cs = context.cs;
    final k = klass;
    final marked = status.isNotEmpty;
    final Color accent = switch (status) {
      'present' => tk.success,
      'absent' => tk.danger,
      'cancelled' => tk.textMuted,
      _ => isNow ? cs.primary : AppColors.mStudy,
    };

    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
      borderColor: isNow ? cs.primary : null,
      onTap: onEdit,
      child: Row(children: [
        Container(
          width: 5,
          height: showMarks ? 84 : 62,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(Radii.l)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    k.subject.isEmpty ? context.t('st_untitled_class') : k.subject,
                    style: context.tt.titleSmall?.copyWith(
                      color: isPast && !marked ? tk.textMuted : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isNow) Pill(context.t('st_now'), color: cs.primary, filled: true),
                if (marked && !isNow)
                  Pill(context.t('st_$status'), color: accent, filled: true),
              ]),
              const SizedBox(height: 3),
              Wrap(spacing: 10, runSpacing: 2, children: [
                MetaChip(Icons.schedule_rounded,
                    '${context.timeOfHm(k.start)} – ${context.timeOfHm(k.end)}'),
                if (k.room.isNotEmpty) MetaChip(Icons.meeting_room_outlined, k.room),
                if (k.teacher.isNotEmpty) MetaChip(Icons.person_outline_rounded, k.teacher),
              ]),
              if (showMarks && onMark != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  _MarkButton(
                    label: context.t('st_present'),
                    icon: Icons.check_rounded,
                    color: tk.success,
                    selected: status == 'present',
                    onTap: () => onMark!('present'),
                  ),
                  const SizedBox(width: 6),
                  _MarkButton(
                    label: context.t('st_absent'),
                    icon: Icons.close_rounded,
                    color: tk.danger,
                    selected: status == 'absent',
                    onTap: () => onMark!('absent'),
                  ),
                  const SizedBox(width: 6),
                  _MarkButton(
                    label: context.t('st_cancelled'),
                    icon: Icons.block_rounded,
                    color: tk.textMuted,
                    selected: status == 'cancelled',
                    onTap: () => onMark!('cancelled'),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MarkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _MarkButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? color : context.tokens.tint(color),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 15, color: selected ? Colors.white : color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelSmall?.copyWith(
                    color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

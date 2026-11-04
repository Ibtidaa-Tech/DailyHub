import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/agenda.dart';
import '../../data/extras_store.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';

/// Month grid with coloured dots for anything happening on each day.
/// Swipe left/right (or use the arrows) to change month.
class CalendarView extends StatefulWidget {
  final DateTime selected;
  final int weekStart;
  final ValueChanged<DateTime> onSelect;
  const CalendarView({super.key, required this.selected, required this.onSelect, this.weekStart = DateTime.monday});
  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  void _shift(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final money = context.watch<MoneyStore>();
    final extras = context.watch<ExtrasStore?>();
    final tk = context.tokens;
    final dots = Agenda.monthDots(_month, plan: plan, money: money, extras: extras);
    final first = DateTime(_month.year, _month.month, 1);
    final lead = (first.weekday - widget.weekStart + 7) % 7;
    final days = daysInMonth(_month.year, _month.month);
    final cells = ((lead + days) / 7).ceil() * 7;
    final today = todayDate();

    // Weekday initials starting at the chosen first day of the week.
    final names = List.generate(7, (i) {
      final d = DateTime(2024, 1, 1 + ((widget.weekStart - 1 + i) % 7)); // 1 Jan 2024 = Monday
      return context.fmtDate(d, 'EEEEE');
    });

    return DhCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) _shift(1);
          if (v > 200) _shift(-1);
        },
        child: Column(children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shift(-1)),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _month = DateTime(today.year, today.month));
                  widget.onSelect(today);
                },
                child: Text(context.fmtDate(_month, 'MMMM yyyy'),
                    textAlign: TextAlign.center, style: context.tt.titleMedium),
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shift(1)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            for (final n in names)
              Expanded(
                child: Center(
                  child: Text(n, style: context.tt.labelSmall?.copyWith(color: tk.textFaint)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 46,
            ),
            itemBuilder: (context, i) {
              final dayNum = i - lead + 1;
              if (dayNum < 1 || dayNum > days) return const SizedBox.shrink();
              final d = DateTime(_month.year, _month.month, dayNum);
              final sel = sameDay(d, widget.selected);
              final isToday = sameDay(d, today);
              final c = dots[dayNum] ?? const [];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onSelect(d);
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: sel ? context.cs.primary : null,
                    borderRadius: BorderRadius.circular(12),
                    border: isToday && !sel ? Border.all(color: context.cs.primary, width: 1.4) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$dayNum',
                        style: context.tt.labelLarge?.copyWith(
                          color: sel ? context.cs.onPrimary : (d.isBefore(today) ? tk.textMuted : null),
                          fontWeight: isToday || sel ? FontWeight.w800 : FontWeight.w600,
                        )),
                    const SizedBox(height: 3),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final col in c)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: sel ? context.cs.onPrimary : col,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ]),
                  ]),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}

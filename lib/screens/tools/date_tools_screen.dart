import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../ui/kit.dart';

/// Date tools: age, the gap between two dates, and date arithmetic.
///
/// Every answer is given twice — once in calendar terms (years, months, days),
/// which is what people say out loud, and once as a plain total.
class DateToolsScreen extends StatefulWidget {
  const DateToolsScreen({super.key});

  @override
  State<DateToolsScreen> createState() => _DateToolsScreenState();
}

/// Years / months / days between two dates, borrowing days from the previous
/// month rather than dividing by an average month length.
({int years, int months, int days}) _breakdown(DateTime a, DateTime b) {
  final from = a.isAfter(b) ? b : a;
  final to = a.isAfter(b) ? a : b;
  var years = to.year - from.year;
  var months = to.month - from.month;
  var days = to.day - from.day;
  if (days < 0) {
    months--;
    days += daysInMonth(to.year, to.month == 1 ? 12 : to.month - 1);
  }
  if (months < 0) {
    years--;
    months += 12;
  }
  return (years: years, months: months, days: days);
}

/// Mon–Fri days in [from, to), counted a week at a time so a century-wide
/// range costs the same as a week.
int _workdays(DateTime from, DateTime to) {
  final total = daysBetween(from, to).abs();
  final start = from.isAfter(to) ? to : from;
  final fullWeeks = total ~/ 7;
  var count = fullWeeks * 5;
  for (var i = 0; i < total % 7; i++) {
    if (addDays(start, fullWeeks * 7 + i).weekday <= DateTime.friday) count++;
  }
  return count;
}

class _DateToolsScreenState extends State<DateToolsScreen> {
  int _tab = 0;

  DateTime _dob = DateTime(2000, 1, 1);
  DateTime _start = todayDate();
  DateTime _end = addDays(todayDate(), 30);
  DateTime _base = todayDate();

  final _amount = TextEditingController(text: '30');
  int _unit = 0; // 0 days, 1 weeks, 2 months, 3 years
  bool _subtract = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime current, ValueChanged<DateTime> onPick) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    onPick(dateOnly(d));
  }

  Widget _dateField(String labelKey, DateTime value, ValueChanged<DateTime> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FormFieldButton(
        icon: Icons.calendar_today_rounded,
        label: context.t(labelKey),
        value: context.fmtDate(value, 'EEE, d MMM yyyy'),
        onTap: () => _pickDate(value, (d) => setState(() => onPick(d))),
      ),
    );
  }

  String _ymd(DateTime a, DateTime b) {
    final p = _breakdown(a, b);
    return context.tr('dt_ymd', {'y': p.years, 'm': p.months, 'd': p.days});
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: context.t('tool_date'),
      subtitle: context.t('tool_date_sub'),
      maxWidth: 600,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: PillTabs<int>(
          items: [
            (0, context.t('dt_age')),
            (1, context.t('dt_diff')),
            (2, context.t('dt_add')),
          ],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      slivers: switch (_tab) {
        1 => _diffSlivers(context),
        2 => _addSlivers(context),
        _ => _ageSlivers(context),
      },
    );
  }

  // ----------------------------------------------------------------- Age

  List<Widget> _ageSlivers(BuildContext context) {
    final today = todayDate();
    final totalDays = daysBetween(_dob, today);
    final p = _breakdown(_dob, today);

    var next = DateTime(today.year, _dob.month, _dob.day);
    if (next.isBefore(today)) next = DateTime(today.year + 1, _dob.month, _dob.day);
    final untilBirthday = daysBetween(today, next);

    return [
      SliverToBoxAdapter(
        child: Column(children: [
          _dateField('dt_dob', _dob, (d) => _dob = d),
          _ResultCard(
            label: context.t('dt_age'),
            value: _ymd(_dob, today),
            color: AppColors.mCalendar,
            rows: [
              (context.t('dt_total_days'), '$totalDays'),
              (context.t('dt_total_weeks'), '${(totalDays / 7).floor()}'),
              (context.t('dt_total_months'), '${p.years * 12 + p.months}'),
              (
                context.t('dt_next_birthday'),
                untilBirthday == 0
                    ? context.t('dt_birthday_today')
                    : context.tr('dt_in_days', {'n': untilBirthday}),
              ),
            ],
          ),
        ]),
      ),
    ];
  }

  // ---------------------------------------------------------- Difference

  List<Widget> _diffSlivers(BuildContext context) {
    final days = daysBetween(_start, _end).abs();
    final workdays = _workdays(_start, _end);

    return [
      SliverToBoxAdapter(
        child: Column(children: [
          _dateField('from', _start, (d) => _start = d),
          _dateField('to', _end, (d) => _end = d),
          _ResultCard(
            label: context.t('dt_diff'),
            value: days == 0 ? context.t('dt_same_day') : _ymd(_start, _end),
            color: AppColors.mTrips,
            rows: [
              (context.t('dt_total_days'), '$days'),
              (
                context.t('dt_total_weeks'),
                context.tr('dt_weeks_days', {'w': (days / 7).floor(), 'd': days % 7}),
              ),
              (context.t('dt_working_days'), '$workdays'),
              (context.t('dt_weekend_days'), '${days - workdays}'),
              (context.t('dt_hours'), '${days * 24}'),
            ],
          ),
        ]),
      ),
    ];
  }

  // ------------------------------------------------------- Add / Subtract

  DateTime get _addResult {
    // Clamp before touching DateTime: a silly number here would otherwise
    // produce a nonsense year rather than an obviously capped one.
    final raw = int.tryParse(_amount.text.trim()) ?? 0;
    final n = raw.clamp(-100000, 100000).toInt() * (_subtract ? -1 : 1);
    return switch (_unit) {
      1 => addDays(_base, n * 7),
      2 => addMonths(_base, n),
      3 => addMonths(_base, n * 12),
      _ => addDays(_base, n),
    };
  }

  List<Widget> _addSlivers(BuildContext context) {
    final result = dateOnly(_addResult);
    final gap = daysBetween(_base, result);

    return [
      SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _dateField('dt_start_date', _base, (d) => _base = d),
          PillTabs<bool>(
            items: [(false, context.t('add')), (true, context.t('dt_subtract'))],
            value: _subtract,
            onChanged: (v) => setState(() => _subtract = v),
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.t('amount')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _unit,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.t('dt_unit')),
                items: [
                  DropdownMenuItem(value: 0, child: Text(context.t('dt_days'))),
                  DropdownMenuItem(value: 1, child: Text(context.t('dt_weeks'))),
                  DropdownMenuItem(value: 2, child: Text(context.t('dt_months'))),
                  DropdownMenuItem(value: 3, child: Text(context.t('dt_years'))),
                ],
                onChanged: (v) => setState(() => _unit = v ?? 0),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _ResultCard(
            label: context.t('dt_result'),
            value: context.fmtDate(result, 'EEE, d MMM yyyy'),
            color: AppColors.mGoals,
            rows: [
              (context.t('dt_total_days'), '${gap.abs()}'),
              (context.t('dt_diff'), _ymd(_base, result)),
            ],
          ),
        ]),
      ),
    ];
  }
}

/// Tinted answer card: one headline plus the supporting numbers.
class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> rows;
  final Color color;
  const _ResultCard({
    required this.label,
    required this.value,
    required this.color,
    this.rows = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return DhCard(
      color: tk.tint(color),
      borderColor: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label,
            textAlign: TextAlign.center,
            style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
        const SizedBox(height: 4),
        Text(value,
            textAlign: TextAlign.center,
            style: context.tt.headlineSmall?.copyWith(color: color)),
        if (rows.isNotEmpty) ...[
          Divider(height: 26, color: color.withValues(alpha: 0.25)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(r.$1,
                      style: context.tt.bodyMedium?.copyWith(color: tk.textMuted)),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(r.$2,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelLarge),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

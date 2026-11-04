import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'extras_store.dart';
import 'models.dart';
import 'money_store.dart';
import 'plan_store.dart';

enum AgendaKind { task, reminder, bill, meeting, lecture, assignment, trip, delivery, countdown }

/// One row on the combined day timeline.
class AgendaItem {
  final AgendaKind kind;
  final String id;
  final String title;
  final String subtitle; // raw detail, e.g. room or route
  final DateTime? time; // null = all-day
  final bool done;
  final IconData icon;
  final Color color;
  final Object? ref; // Task / Reminder / Bill / raw map

  const AgendaItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.time,
    this.done = false,
    required this.icon,
    required this.color,
    this.ref,
  });
}

/// Does a reminder fire on [day]? (Handles repeats.)
bool reminderOccursOn(Reminder r, DateTime day) {
  final w = r.when;
  if (w == null || r.done) return false;
  final start = dateOnly(w);
  final d = dateOnly(day);
  if (d.isBefore(start) && r.repeat != 'once') return false;
  switch (r.repeat) {
    case 'daily':
      return true;
    case 'weekdays':
      return d.weekday <= 5;
    case 'weekly':
      return d.weekday == w.weekday;
    case 'monthly':
      final anchor = r.anchor > 0 ? r.anchor : w.day;
      return d.day == anchor.clamp(1, daysInMonth(d.year, d.month));
    case 'yearly':
      return d.month == w.month && d.day == w.day;
    default:
      return sameDay(w, d);
  }
}

class Agenda {
  /// Everything happening on [day], timed items first in clock order.
  static List<AgendaItem> forDay(
    DateTime day, {
    required PlanStore plan,
    MoneyStore? money,
    ExtrasStore? extras,
    bool includeDone = true,
    bool includeTasks = true,
  }) {
    final out = <AgendaItem>[];
    final d0 = dateOnly(day);

    if (includeTasks) {
      for (final t in plan.dueOn(d0, includeDone: includeDone)) {
        out.add(AgendaItem(
          kind: AgendaKind.task,
          id: t.id,
          title: t.title,
          time: t.hasTime ? t.due : null,
          done: t.isDone,
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.mTasks,
          ref: t,
        ));
      }
    }
    for (final r in plan.reminders) {
      if (!reminderOccursOn(r, d0)) continue;
      final w = r.when!;
      out.add(AgendaItem(
        kind: AgendaKind.reminder,
        id: r.id,
        title: r.title,
        time: DateTime(d0.year, d0.month, d0.day, w.hour, w.minute),
        icon: Icons.notifications_active_outlined,
        color: AppColors.mReminders,
        ref: r,
      ));
    }
    if (money != null) {
      for (final b in money.activeBills) {
        final due = b.dueDate;
        if (due == null || !sameDay(due, d0)) continue;
        out.add(AgendaItem(
          kind: AgendaKind.bill,
          id: b.id,
          title: b.name,
          icon: Icons.receipt_long_rounded,
          color: b.type == 'income' ? AppColors.income : AppColors.expense,
          ref: b,
        ));
      }
    }
    if (extras != null) {
      for (final m in extras.meetingsOn(d0)) {
        out.add(AgendaItem(
          kind: AgendaKind.meeting,
          id: str(m['id']),
          title: str(m['title']),
          time: DateTime.tryParse(str(m['at'])),
          icon: Icons.groups_rounded,
          color: AppColors.mWork,
          ref: m,
        ));
      }
      for (final c in extras.classesOn(d0)) {
        final t = parseHm(str(c['start']));
        out.add(AgendaItem(
          kind: AgendaKind.lecture,
          id: str(c['id']),
          title: str(c['subject']),
          subtitle: [str(c['room']), if (str(c['end']).isNotEmpty) '→ ${str(c['end'])}']
              .where((e) => e.isNotEmpty)
              .join(' '),
          time: t == null ? null : DateTime(d0.year, d0.month, d0.day, t.hour, t.minute),
          icon: Icons.menu_book_rounded,
          color: AppColors.mStudy,
          ref: c,
        ));
      }
      for (final a in extras.assignmentsDue(d0)) {
        out.add(AgendaItem(
          kind: AgendaKind.assignment,
          id: str(a['id']),
          title: str(a['title']),
          subtitle: str(a['subject']),
          icon: Icons.assignment_rounded,
          color: AppColors.mStudy,
          ref: a,
        ));
      }
      for (final t in extras.tripsOn(d0)) {
        final tm = parseHm(str(t['depTime']));
        out.add(AgendaItem(
          kind: AgendaKind.trip,
          id: str(t['id']),
          title: '${str(t['from'])} → ${str(t['to'])}',
          subtitle: str(t['pnr']),
          time: tm == null ? null : DateTime(d0.year, d0.month, d0.day, tm.hour, tm.minute),
          icon: switch (str(t['type'])) {
            'train' => Icons.train_rounded,
            'bus' => Icons.directions_bus_rounded,
            'car' => Icons.directions_car_rounded,
            _ => Icons.flight_rounded,
          },
          color: AppColors.mTrips,
          ref: t,
        ));
      }
      for (final p in extras.packagesOn(d0)) {
        out.add(AgendaItem(
          kind: AgendaKind.delivery,
          id: str(p['id']),
          title: str(p['item']),
          subtitle: str(p['carrier']),
          icon: Icons.local_shipping_rounded,
          color: AppColors.mPackages,
          ref: p,
        ));
      }
      for (final c in extras.countdownsOn(d0)) {
        out.add(AgendaItem(
          kind: AgendaKind.countdown,
          id: str(c['id']),
          title: '${str(c['emoji'])} ${str(c['title'])}'.trim(),
          icon: Icons.celebration_rounded,
          color: AppColors.mCountdown,
          ref: c,
        ));
      }
    }

    out.sort((a, b) {
      if (a.time == null && b.time == null) return a.kind.index.compareTo(b.kind.index);
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });
    return out;
  }

  /// Days in [month] that have anything on them (for calendar dots).
  static Map<int, List<Color>> monthDots(
    DateTime month, {
    required PlanStore plan,
    MoneyStore? money,
    ExtrasStore? extras,
  }) {
    final out = <int, List<Color>>{};
    final n = daysInMonth(month.year, month.month);
    for (var i = 1; i <= n; i++) {
      final d = DateTime(month.year, month.month, i);
      final items = forDay(d, plan: plan, money: money, extras: extras, includeDone: false);
      if (items.isEmpty) continue;
      final colors = <Color>[];
      for (final it in items) {
        if (!colors.contains(it.color)) colors.add(it.color);
        if (colors.length == 3) break;
      }
      out[i] = colors;
    }
    return out;
  }
}

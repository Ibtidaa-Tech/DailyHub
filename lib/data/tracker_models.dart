import 'package:flutter/material.dart';

import 'models.dart';

/// ---------------------------------------------------------------------------
/// The habit tracker: a fixed-length challenge (21 days by default), a set of
/// items to tick each day, and one log row per tick.
///
/// Three things make this different from the open-ended Habits module:
///
///  * Every tick stores the EXACT timestamp it happened at, not just a day
///    flag, so "did it, but at 11pm" is distinguishable from "did it at 6am".
///  * Each item carries its own start day, so an item added on day 5 counts
///    from its own day 1 while the others carry on from day 5.
///  * An item can have a time window. Ticking inside it is on time; ticking
///    after it is late, and by how much is recorded.
///
/// "Missed" is never written. It is the absence of a log for a day that has
/// already passed, so it can never go stale or disagree with the data.
/// ---------------------------------------------------------------------------

/// What a log row means.
///
/// This is PUNCTUALITY only — did the thing happen inside its window. When it
/// was typed into the app is a separate question, answered by
/// [TrackerLog.recordedLater], because the two are independent: praying Fajr
/// at 5:30 and ticking the box at 8pm is on time, recorded late. Collapsing
/// them would mark a whole week of honest catch-up as failure.
///
/// [missed] and [pending] are never stored; they come from the calendar.
enum TickStatus {
  /// Done inside the window, or the habit has no window.
  onTime,

  /// Done after the window closed.
  overdue,

  /// The day has passed with no log at all. Never stored.
  missed,

  /// Today or later, not logged yet. Never stored.
  pending,
}

String tickStatusKey(TickStatus s) => switch (s) {
      TickStatus.onTime => 'tr_on_time',
      TickStatus.overdue => 'tr_late',
      TickStatus.missed => 'tr_missed',
      TickStatus.pending => 'tr_pending',
    };

TickStatus tickStatusFromName(String s) => switch (s) {
      'late' => TickStatus.overdue,
      'missed' => TickStatus.missed,
      'pending' => TickStatus.pending,
      // 'backfill' is from before punctuality and recording time were split.
      // Those rows carry no window verdict, so they read as on time.
      _ => TickStatus.onTime,
    };

String tickStatusName(TickStatus s) => switch (s) {
      TickStatus.onTime => 'ontime',
      TickStatus.overdue => 'late',
      TickStatus.missed => 'missed',
      TickStatus.pending => 'pending',
    };

// ----------------------------------------------------------------- challenge

class ChallengeStatus {
  static const active = 'active';
  static const finished = 'finished';
  static const abandoned = 'abandoned';
}

class Challenge {
  final String id;
  final Map<String, dynamic> raw;
  String title;
  String subtitle;

  /// Day key of day 1.
  String startDay;

  /// How many days the challenge runs for.
  int days;
  String status;
  int color;

  /// Uid of the account this challenge belongs to.
  String ownerUid;

  /// Set when a mentor assigned this challenge; empty when self-started.
  String mentorUid;
  String mentorName;
  String createdAt;

  Challenge({
    this.id = '',
    Map<String, dynamic>? raw,
    this.title = '',
    this.subtitle = '',
    this.startDay = '',
    this.days = 21,
    this.status = ChallengeStatus.active,
    this.color = 0,
    this.ownerUid = '',
    this.mentorUid = '',
    this.mentorName = '',
    this.createdAt = '',
  }) : raw = raw ?? {};

  factory Challenge.fromMap(Map<String, dynamic> m) => Challenge(
        id: str(m['id']),
        raw: m,
        title: str(m['title']),
        subtitle: str(m['subtitle']),
        startDay: str(m['startDay']),
        days: toI(m['days']) < 1 ? 21 : toI(m['days']),
        status: str(m['status']).isEmpty ? ChallengeStatus.active : str(m['status']),
        color: toI(m['color']),
        ownerUid: str(m['ownerUid']),
        mentorUid: str(m['mentorUid']),
        mentorName: str(m['mentorName']),
        createdAt: str(m['createdAt']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'title': title,
        'subtitle': subtitle,
        'startDay': startDay,
        'days': days,
        'status': status,
        'color': color,
        'ownerUid': ownerUid,
        'mentorUid': mentorUid,
        'mentorName': mentorName,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
      }..remove('id');

  DateTime? get start => parseDay(startDay);

  /// Last day of the challenge, inclusive.
  DateTime? get end {
    final s = start;
    return s == null ? null : addDays(s, days - 1);
  }

  bool get assignedByMentor => mentorUid.isNotEmpty;

  /// True once day 1 has arrived.
  bool get hasStarted {
    final s = start;
    return s != null && !s.isAfter(todayDate());
  }

  bool get isOver {
    final e = end;
    return e != null && todayDate().isAfter(e);
  }

  bool get isActive => status == ChallengeStatus.active && !isOver;

  /// 1-based day number for [day], or null when it falls outside the run.
  int? dayNumber(DateTime day) {
    final s = start;
    if (s == null) return null;
    final n = daysBetween(s, day) + 1;
    return (n < 1 || n > days) ? null : n;
  }

  /// Today's day number, clamped into the run so the header always reads
  /// sensibly: 1 before it starts, [days] once it is over.
  int get currentDay {
    final s = start;
    if (s == null) return 1;
    final n = daysBetween(s, todayDate()) + 1;
    return n.clamp(1, days);
  }

  /// Every day of the challenge, earliest first.
  List<DateTime> allDays() {
    final s = start;
    if (s == null) return const [];
    return [for (var i = 0; i < days; i++) addDays(s, i)];
  }

  /// Days up to and including today, newest first — what the grid shows by
  /// default, so you are not scrolling past empty future rows.
  List<DateTime> daysSoFar() {
    final t = todayDate();
    return allDays().where((d) => !d.isAfter(t)).toList().reversed.toList();
  }

  /// Which week of the challenge [day] falls in, 1-based.
  int? weekNumber(DateTime day) {
    final n = dayNumber(day);
    return n == null ? null : ((n - 1) ~/ 7) + 1;
  }

  int get weekCount => ((days - 1) ~/ 7) + 1;
}

// ---------------------------------------------------------------------- item

class ItemKind {
  /// Something to do — ticking means you did it.
  static const doIt = 'do';

  /// Something to avoid — ticking means you stayed clear of it all day.
  static const avoid = 'avoid';
}

/// A target that applies from one day onward — "20 from 29 Oct", "40 from
/// 8 Nov".
///
/// Raising a target mid-run is the normal shape of progress, and rewriting the
/// habit would quietly relabel the ten days you already did at 20. So targets
/// are a dated list instead of a single number: history keeps the target that
/// was actually in force, and today keeps the one you are aiming at now.
class TargetStep {
  /// 'YYYY-MM-DD' — the first day this target applies.
  String from;
  double value;

  /// Free text: 'reps', 'problems', 'lessons', 'pages'. Optional.
  String unit;

  TargetStep({this.from = '', this.value = 0, this.unit = ''});

  factory TargetStep.fromMap(Map<String, dynamic> m) => TargetStep(
        from: str(m['from']),
        value: (m['value'] as num?)?.toDouble() ?? 0,
        unit: str(m['unit']),
      );

  Map<String, dynamic> toMap() => {'from': from, 'value': value, 'unit': unit};

  DateTime? get day => parseDay(from);

  /// Whole numbers lose the '.0': 40, not 40.0. Halves survive: 1.5.
  String get valueLabel =>
      value == value.roundToDouble() ? value.round().toString() : value.toString();

  /// "40 reps", or just "40" when no unit is set.
  String get label => unit.isEmpty ? valueLabel : '$valueLabel $unit';

  TargetStep copy() => TargetStep(from: from, value: value, unit: unit);
}

class TrackerItem {
  final String id;
  final Map<String, dynamic> raw;
  String challengeId;
  String name;
  String emoji;
  int color;

  /// This item's own day 1. Items added mid-challenge count from here, so
  /// their day number is independent of everything else.
  String startDay;

  /// 'HH:mm', or empty for an item with no particular time.
  String windowStart;
  String windowEnd;

  /// Minutes after [windowEnd] that still count as on time.
  int grace;
  String kind;
  int order;
  String addedBy;
  String addedAt;

  /// Dated targets, earliest first. Empty for a habit where a number means
  /// nothing — Fajr, No Junk Food.
  List<TargetStep> targets;

  TrackerItem({
    this.id = '',
    Map<String, dynamic>? raw,
    this.challengeId = '',
    this.name = '',
    this.emoji = '✅',
    this.color = 0,
    this.startDay = '',
    this.windowStart = '',
    this.windowEnd = '',
    this.grace = 0,
    this.kind = ItemKind.doIt,
    this.order = 0,
    this.addedBy = '',
    this.addedAt = '',
    List<TargetStep>? targets,
  })  : raw = raw ?? {},
        targets = targets ?? [];

  factory TrackerItem.fromMap(Map<String, dynamic> m) => TrackerItem(
        id: str(m['id']),
        raw: m,
        challengeId: str(m['challengeId']),
        name: str(m['name']),
        emoji: str(m['emoji']).isEmpty ? '✅' : str(m['emoji']),
        color: toI(m['color']),
        startDay: str(m['startDay']),
        windowStart: str(m['windowStart']),
        windowEnd: str(m['windowEnd']),
        grace: toI(m['grace']),
        kind: str(m['kind']) == ItemKind.avoid ? ItemKind.avoid : ItemKind.doIt,
        order: toI(m['order']),
        addedBy: str(m['addedBy']),
        addedAt: str(m['addedAt']),
        // Written as a list, but Firebase hands back a Map when the keys are
        // sparse, so accept either.
        targets: _targetsFrom(m['targets']),
      );

  static List<TargetStep> _targetsFrom(Object? v) {
    final out = <TargetStep>[];
    if (v is List) {
      for (final e in v) {
        if (e is Map) out.add(TargetStep.fromMap(Map<String, dynamic>.from(e)));
      }
    } else if (v is Map) {
      for (final e in v.values) {
        if (e is Map) out.add(TargetStep.fromMap(Map<String, dynamic>.from(e)));
      }
    }
    out.removeWhere((t) => t.day == null);
    out.sort((a, b) => a.from.compareTo(b.from));
    return out;
  }

  Map<String, dynamic> toMap() => {
        ...raw,
        'challengeId': challengeId,
        'name': name,
        'emoji': emoji,
        'color': color,
        'startDay': startDay,
        'windowStart': windowStart,
        'windowEnd': windowEnd,
        'grace': grace,
        'kind': kind,
        'order': order,
        'addedBy': addedBy,
        'addedAt': addedAt.isEmpty ? nowIso() : addedAt,
        'targets': [for (final t in sortedTargets) t.toMap()],
      }..remove('id');

  bool get isAvoid => kind == ItemKind.avoid;

  bool get hasTargets => targets.isNotEmpty;

  List<TargetStep> get sortedTargets =>
      [...targets]..sort((a, b) => a.from.compareTo(b.from));

  /// The target in force on [day]: the latest step that starts on or before
  /// it. Null before the first step begins, so a target added today does not
  /// retroactively claim the days before it.
  TargetStep? targetOn(DateTime day) {
    TargetStep? found;
    for (final t in sortedTargets) {
      final d = t.day;
      if (d == null || d.isAfter(day)) break;
      found = t;
    }
    return found;
  }

  /// What you are aiming at right now.
  TargetStep? get currentTarget => targetOn(todayDate());

  /// The last target of all, which is the one in force on the final day —
  /// including a step you have dated into the future.
  TargetStep? get latestTarget =>
      sortedTargets.isEmpty ? null : sortedTargets.last;

  /// Name with the target in force on [day], for a column header or a row:
  /// "Pushups · 40".
  String labelOn(DateTime day) {
    final t = targetOn(day);
    return t == null ? name : '$name · ${t.label}';
  }

  /// Replaces the target starting on [from], or adds one. Keeps the list
  /// sorted and never leaves two steps on the same day.
  void setTarget(DateTime from, double value, {String unit = ''}) {
    final key = dayKey(from);
    targets.removeWhere((t) => t.from == key);
    targets.add(TargetStep(from: key, value: value, unit: unit));
    targets.sort((a, b) => a.from.compareTo(b.from));
  }

  void removeTarget(String from) => targets.removeWhere((t) => t.from == from);

  DateTime? get start => parseDay(startDay);

  bool get hasWindow => parseHm(windowStart) != null || parseHm(windowEnd) != null;

  /// "5:22 AM – 6:00 AM", or just one side when only one is set.
  String windowLabel(String Function(String hm) fmt) {
    final a = parseHm(windowStart) == null ? '' : fmt(windowStart);
    final b = parseHm(windowEnd) == null ? '' : fmt(windowEnd);
    if (a.isEmpty && b.isEmpty) return '';
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a – $b';
  }

  /// Whether this item is expected on [day] — i.e. day is on or after its own
  /// start day.
  bool runsOn(DateTime day) {
    final s = start;
    return s != null && !day.isBefore(s);
  }

  /// This item's own 1-based day number on [day], or null before it started.
  int? dayNumber(DateTime day) {
    final s = start;
    if (s == null || day.isBefore(s)) return null;
    return daysBetween(s, day) + 1;
  }

  /// The moment the window closes on [day], grace included. Null when the
  /// item has no end time, which means it can be ticked any time that day.
  DateTime? deadlineOn(DateTime day) {
    final e = parseHm(windowEnd);
    if (e == null) return null;
    return DateTime(day.year, day.month, day.day, e.hour, e.minute)
        .add(Duration(minutes: grace));
  }

  /// The moment the window opens on [day]. Null when no start time is set.
  DateTime? opensOn(DateTime day) {
    final s = parseHm(windowStart);
    if (s == null) return null;
    return DateTime(day.year, day.month, day.day, s.hour, s.minute);
  }

  /// Judges a completion time against this item's window.
  ///
  /// [doneAt] is when the person says they did it, not when they tapped. A
  /// habit with no closing time can never be late, so it is always on time.
  ({TickStatus status, int lateBy}) evaluate(DateTime doneAt) {
    final deadline = deadlineOn(doneAt);
    if (deadline == null || !doneAt.isAfter(deadline)) {
      return (status: TickStatus.onTime, lateBy: 0);
    }
    return (status: TickStatus.overdue, lateBy: doneAt.difference(deadline).inMinutes);
  }

  /// The time to offer when someone ticks this habit for [day].
  ///
  /// Ticking in the moment should need no thought, so it offers now. Once the
  /// window has shut — or the day is already past — now is almost certainly
  /// wrong, and the window's opening time is the better guess.
  DateTime suggestedTimeFor(DateTime day) {
    final now = DateTime.now();
    final opens = opensOn(day);
    final deadline = deadlineOn(day);
    if (sameDay(day, now)) {
      if (deadline == null || !now.isAfter(deadline)) return now;
      return opens ?? DateTime(day.year, day.month, day.day, now.hour, now.minute);
    }
    return opens ?? DateTime(day.year, day.month, day.day, 9, 0);
  }
}

// ----------------------------------------------------------------------- log

/// One tick. The id is derived from challenge + item + day, so ticking the
/// same box twice overwrites rather than piling up duplicate rows.
class TrackerLog {
  final String id;
  final Map<String, dynamic> raw;
  String challengeId;
  String itemId;

  /// Day key this tick is *for*.
  String forDay;

  /// When the box was ticked — stamped by the app, never editable. This is
  /// what makes a late entry visible rather than deniable.
  String at;

  /// When the person says they actually did it. Decides on time vs late.
  /// Empty on rows written before the two were separated, in which case
  /// [completedAt] falls back to [at].
  String doneAt;
  String status;

  /// Minutes past the deadline. 0 unless [status] is late.
  int lateBy;

  /// Uid that logged it — the student, or a mentor marking on their behalf.
  String by;
  String note;

  TrackerLog({
    this.id = '',
    Map<String, dynamic>? raw,
    this.challengeId = '',
    this.itemId = '',
    this.forDay = '',
    this.at = '',
    this.doneAt = '',
    this.status = 'ontime',
    this.lateBy = 0,
    this.by = '',
    this.note = '',
  }) : raw = raw ?? {};

  factory TrackerLog.fromMap(Map<String, dynamic> m) => TrackerLog(
        id: str(m['id']),
        raw: m,
        challengeId: str(m['challengeId']),
        itemId: str(m['itemId']),
        forDay: str(m['forDay']),
        at: str(m['at']),
        doneAt: str(m['doneAt']),
        status: str(m['status']).isEmpty ? 'ontime' : str(m['status']),
        lateBy: toI(m['lateBy']),
        by: str(m['by']),
        note: str(m['note']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'challengeId': challengeId,
        'itemId': itemId,
        'forDay': forDay,
        'at': at,
        'doneAt': doneAt,
        'status': status,
        'lateBy': lateBy,
        'by': by,
        'note': note,
      }..remove('id');

  /// Stable key so one item on one day can only ever have one row.
  static String keyFor(String challengeId, String itemId, DateTime day) =>
      '${challengeId}_${itemId}_${dayKey(day)}';

  DateTime? get day => parseDay(forDay);

  /// When the box was tapped.
  DateTime? get recordedAt => DateTime.tryParse(at);

  /// When it was actually done. Falls back to the tap time for rows written
  /// before the two were separated.
  DateTime? get completedAt => DateTime.tryParse(doneAt.isEmpty ? at : doneAt);

  /// How long after doing it the box was ticked. Negative values (a clock
  /// change, or a time typed slightly ahead) clamp to zero.
  int get lagMinutes {
    final done = completedAt;
    final rec = recordedAt;
    if (done == null || rec == null) return 0;
    final m = rec.difference(done).inMinutes;
    return m < 0 ? 0 : m;
  }

  /// True when this was typed in well after the fact. Twenty minutes is the
  /// line: long enough that normal "tick it once you are done" never trips
  /// it, short enough that an evening catch-up always does.
  bool get recordedLater => lagMinutes > 20;

  /// Recorded on a later calendar day than it happened.
  bool get recordedAnotherDay {
    final done = completedAt;
    final rec = recordedAt;
    if (done == null || rec == null) return false;
    return !sameDay(done, rec);
  }

  TickStatus get tickStatus => tickStatusFromName(status);

  bool get wasOnTime => tickStatus == TickStatus.onTime;
  bool get wasLate => tickStatus == TickStatus.overdue;
}

// --------------------------------------------------------------------- tally

/// Counts across a run (or a slice of one). The dashboard, the header and the
/// mentor report are all built from this, so they can never disagree.
///
/// Field is `lateTicks`, not `late` — `late` is a Dart modifier and cannot be
/// an identifier here.
class TrackerTally {
  /// Done inside the window.
  final int onTime;

  /// Done after the window closed.
  final int lateTicks;

  final int missed;

  /// Every (day, item) pair the run expected over the period measured.
  final int expected;

  /// How many of the done ones were typed in well after the fact. This does
  /// NOT reduce [done] or [onTime] — something done at 5:30 and ticked at 8
  /// was still done at 5:30. It is counted separately so a mentor can tell
  /// live ticking from an evening catch-up.
  final int recordedLate;

  const TrackerTally({
    this.onTime = 0,
    this.lateTicks = 0,
    this.missed = 0,
    this.expected = 0,
    this.recordedLate = 0,
  });

  /// Ticked at all, however late.
  int get done => onTime + lateTicks;

  /// Share of expected boxes that got ticked, 0..1.
  double get rate => expected == 0 ? 0 : done / expected;

  /// Share that were done inside their window — the stricter number, and
  /// the one worth showing a mentor.
  double get onTimeRate => expected == 0 ? 0 : onTime / expected;

  bool get isEmpty => expected == 0;
}

// -------------------------------------------------------------------- entry

/// One cell of the sheet, resolved: which habit, which day, and the row
/// behind it if there is one. [log] is null for a missed day, which is the
/// whole point — a miss is the absence of a row, not a row of its own.
class TrackerEntry {
  final DateTime day;
  final TrackerItem item;
  final TrackerLog? log;
  final TickStatus status;
  const TrackerEntry({
    required this.day,
    required this.item,
    required this.log,
    required this.status,
  });
}

// ---------------------------------------------------------------------- icons

/// Icon for a status chip or grid cell. The matching colours live in the UI
/// layer (features/tracker/tracker_ui.dart) — this file stays theme-free, the
/// same way models.dart does.
IconData tickIcon(TickStatus s) => switch (s) {
      TickStatus.onTime => Icons.check_rounded,
      TickStatus.overdue => Icons.schedule_rounded,
      TickStatus.missed => Icons.close_rounded,
      TickStatus.pending => Icons.circle_outlined,
    };

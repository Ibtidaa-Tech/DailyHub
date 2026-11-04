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

/// What a log row means. Stored on the row except for [missed] and [pending],
/// which are worked out from the calendar.
enum TickStatus {
  /// Logged within the window (or no window set), on the day itself.
  onTime,

  /// Logged on the day, but after the window closed.
  overdue,

  /// Logged for an earlier day than the one it was ticked on.
  backfilled,

  /// The day has passed with no log at all. Never stored.
  missed,

  /// Today or later, not logged yet. Never stored.
  pending,
}

String tickStatusKey(TickStatus s) => switch (s) {
      TickStatus.onTime => 'tr_on_time',
      TickStatus.overdue => 'tr_late',
      TickStatus.backfilled => 'tr_backfilled',
      TickStatus.missed => 'tr_missed',
      TickStatus.pending => 'tr_pending',
    };

TickStatus tickStatusFromName(String s) => switch (s) {
      'late' => TickStatus.overdue,
      'backfill' => TickStatus.backfilled,
      'missed' => TickStatus.missed,
      'pending' => TickStatus.pending,
      _ => TickStatus.onTime,
    };

String tickStatusName(TickStatus s) => switch (s) {
      TickStatus.onTime => 'ontime',
      TickStatus.overdue => 'late',
      TickStatus.backfilled => 'backfill',
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
  }) : raw = raw ?? {};

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
      );

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
      }..remove('id');

  bool get isAvoid => kind == ItemKind.avoid;

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

  /// Works out what ticking this item at [at], for [day], means.
  ///
  /// A tick for an earlier day is always [TickStatus.backfilled] whatever the
  /// clock says — it was not done at the time, and the mentor should see that
  /// rather than a clean "on time".
  ({TickStatus status, int lateBy}) evaluate(DateTime day, DateTime at) {
    if (!sameDay(day, at)) {
      return (status: TickStatus.backfilled, lateBy: 0);
    }
    final deadline = deadlineOn(day);
    if (deadline == null || !at.isAfter(deadline)) {
      return (status: TickStatus.onTime, lateBy: 0);
    }
    return (status: TickStatus.overdue, lateBy: at.difference(deadline).inMinutes);
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

  /// Exact moment the box was ticked, ISO 8601 with the device's offset.
  String at;
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
        'status': status,
        'lateBy': lateBy,
        'by': by,
        'note': note,
      }..remove('id');

  /// Stable key so one item on one day can only ever have one row.
  static String keyFor(String challengeId, String itemId, DateTime day) =>
      '${challengeId}_${itemId}_${dayKey(day)}';

  DateTime? get day => parseDay(forDay);
  DateTime? get tickedAt => DateTime.tryParse(at);

  TickStatus get tickStatus => tickStatusFromName(status);

  bool get wasOnTime => tickStatus == TickStatus.onTime;
  bool get wasLate => tickStatus == TickStatus.overdue;
  bool get wasBackfilled => tickStatus == TickStatus.backfilled;
}

// --------------------------------------------------------------------- tally

/// Counts across a run (or a slice of one). The dashboard, the header and the
/// mentor report are all built from this, so they can never disagree.
///
/// Field is `lateTicks`, not `late` — `late` is a Dart modifier and cannot be
/// an identifier here.
class TrackerTally {
  final int onTime;
  final int lateTicks;
  final int backfilled;
  final int missed;

  /// Every (day, item) pair the run expected over the period measured.
  final int expected;

  const TrackerTally({
    this.onTime = 0,
    this.lateTicks = 0,
    this.backfilled = 0,
    this.missed = 0,
    this.expected = 0,
  });

  /// Ticked at all, however late.
  int get done => onTime + lateTicks + backfilled;

  /// Share of expected boxes that got ticked, 0..1.
  double get rate => expected == 0 ? 0 : done / expected;

  /// Share that were ticked inside their window — the stricter number, and
  /// the one worth showing a mentor.
  double get onTimeRate => expected == 0 ? 0 : onTime / expected;

  bool get isEmpty => expected == 0;
}

// ---------------------------------------------------------------------- icons

/// Icon for a status chip or grid cell. The matching colours live in the UI
/// layer (features/tracker/tracker_ui.dart) — this file stays theme-free, the
/// same way models.dart does.
IconData tickIcon(TickStatus s) => switch (s) {
      TickStatus.onTime => Icons.check_rounded,
      TickStatus.overdue => Icons.schedule_rounded,
      TickStatus.backfilled => Icons.history_rounded,
      TickStatus.missed => Icons.close_rounded,
      TickStatus.pending => Icons.circle_outlined,
    };

import 'package:firebase_auth/firebase_auth.dart';

import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';
import 'tracker_models.dart';

/// Live store for the habit tracker.
///
/// Three collections, all flat and all personal (never workspace-shared — a
/// mentor reaches them through the mentor link in phase 3, not through
/// workspace sharing, so sharing a workspace never exposes your tracker):
///
///   challenges     the runs themselves
///   trackerItems   the columns of each run
///   trackerLogs    one row per tick, keyed {challenge}_{item}_{day}
///
/// Derived values go through [memo] so the grid can ask for a cell's state
/// hundreds of times per frame without recomputing anything.
class TrackerStore extends LiveStore {
  /// [forUid] binds the store to someone else's tracker — a mentor looking
  /// at a student. Left null it is your own, which is every normal use.
  TrackerStore({this.forUid}) {
    bind();
  }

  /// Whose tracker this store reads. Null means the signed-in account.
  final String? forUid;

  /// True when this store is pointed at another account, which the UI uses
  /// to stay out of the way: a mentor assigns and reads, the student ticks.
  bool get isForeign => forUid != null && forUid != DbService.instance.uid;

  final DbService _db = DbService.instance;

  /// The account whose rows this store reads and writes.
  String get _owner => forUid ?? (_db.uid ?? '');

  List<Challenge> challenges = [];
  List<TrackerItem> items = [];
  List<TrackerLog> logs = [];

  /// logId -> log, rebuilt whenever data changes.
  Map<String, TrackerLog> _byKey = {};

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void bind() {
    cancelAll();
    final owner = _owner;
    watch('challenges', _db.streamFor(owner, 'challenges'), (List<Map<String, dynamic>> v) {
      challenges = v.map(Challenge.fromMap).toList()
        ..sort((a, b) => b.startDay.compareTo(a.startDay));
    });
    watch('trackerItems', _db.streamFor(owner, 'trackerItems'), (List<Map<String, dynamic>> v) {
      items = v.map(TrackerItem.fromMap).toList()
        ..sort((a, b) {
          final o = a.order.compareTo(b.order);
          return o != 0 ? o : a.addedAt.compareTo(b.addedAt);
        });
    });
    watch('trackerLogs', _db.streamFor(owner, 'trackerLogs'), (List<Map<String, dynamic>> v) {
      logs = v.map(TrackerLog.fromMap).toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      _byKey = {for (final l in logs) l.id: l};
    });
  }

  // ------------------------------------------------------------- challenges

  /// The run to show by default: an active one, else the most recent.
  Challenge? get active {
    for (final c in challenges) {
      if (c.isActive) return c;
    }
    return challenges.isEmpty ? null : challenges.first;
  }

  Challenge? byId(String id) {
    for (final c in challenges) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Challenge> get running => challenges.where((c) => c.isActive).toList();
  List<Challenge> get finished => challenges.where((c) => !c.isActive).toList();

  String saveChallenge(Challenge c) {
    // The run belongs to whoever's tracker it lands in, not to whoever
    // pressed save — a mentor assigning one is not its owner.
    if (c.ownerUid.isEmpty) c.ownerUid = _owner;
    if (isForeign && c.mentorUid.isEmpty) {
      final me = FirebaseAuth.instance.currentUser;
      c.mentorUid = me?.uid ?? '';
      c.mentorName = me?.displayName ?? me?.email ?? '';
    }
    if (c.id.isEmpty) {
      return _db.addNowIn(_owner, 'challenges', c.toMap());
    }
    _db.setIn(_owner, 'challenges', c.id, c.toMap());
    return c.id;
  }

  void setChallengeStatus(Challenge c, String status) =>
      _db.updateIn(_owner, 'challenges', c.id, {'status': status});

  /// Removes a run and everything under it. Only offered before day 1, when
  /// nothing has been logged yet.
  void deleteChallenge(Challenge c) {
    for (final i in itemsOf(c.id)) {
      _db.removeIn(_owner, 'trackerItems', i.id);
    }
    for (final l in logs.where((l) => l.challengeId == c.id)) {
      _db.removeIn(_owner, 'trackerLogs', l.id);
    }
    _db.removeIn(_owner, 'challenges', c.id);
  }

  // ------------------------------------------------------------------ items

  List<TrackerItem> itemsOf(String challengeId) =>
      memo('items:$challengeId', () => items.where((i) => i.challengeId == challengeId).toList());

  /// Items expected on [day] — those whose own start day has arrived.
  List<TrackerItem> itemsOn(String challengeId, DateTime day) => memo(
      'itemsOn:$challengeId:${dayKey(day)}',
      () => itemsOf(challengeId).where((i) => i.runsOn(day)).toList());

  TrackerItem? itemById(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  String saveItem(TrackerItem i) {
    if (i.addedBy.isEmpty) i.addedBy = _uid;
    if (i.id.isEmpty) {
      if (i.order == 0) {
        final siblings = itemsOf(i.challengeId);
        i.order = siblings.isEmpty ? 0 : siblings.map((e) => e.order).reduce((a, b) => a > b ? a : b) + 1;
      }
      return _db.addNowIn(_owner, 'trackerItems', i.toMap());
    }
    _db.setIn(_owner, 'trackerItems', i.id, i.toMap());
    return i.id;
  }

  /// An item can only be removed while it has never been ticked. Once a run
  /// is under way the columns are fixed — you can add, never take away.
  bool canDeleteItem(TrackerItem i) =>
      logs.where((l) => l.itemId == i.id).isEmpty;

  bool deleteItem(TrackerItem i) {
    if (!canDeleteItem(i)) return false;
    _db.removeIn(_owner, 'trackerItems', i.id);
    return true;
  }

  void reorderItems(List<TrackerItem> ordered) {
    for (var n = 0; n < ordered.length; n++) {
      if (ordered[n].order == n) continue;
      _db.updateIn(_owner, 'trackerItems', ordered[n].id, {'order': n});
    }
  }

  // ------------------------------------------------------------------- logs

  TrackerLog? logFor(String challengeId, String itemId, DateTime day) =>
      _byKey[TrackerLog.keyFor(challengeId, itemId, day)];

  bool isTicked(String challengeId, String itemId, DateTime day) =>
      _byKey.containsKey(TrackerLog.keyFor(challengeId, itemId, day));

  /// What a cell should show. Combines the stored row with the calendar, so
  /// an untouched day in the past reads as missed and today reads as pending.
  TickStatus statusOf(Challenge c, TrackerItem i, DateTime day) {
    final log = logFor(c.id, i.id, day);
    if (log != null) return log.tickStatus;
    if (!i.runsOn(day)) return TickStatus.pending;
    return day.isBefore(todayDate()) ? TickStatus.missed : TickStatus.pending;
  }

  /// Ticks a box, stamping the exact moment and working out whether that was
  /// on time, late or a backfill. Returns the row that was written.
  TrackerLog tick(Challenge c, TrackerItem i, DateTime day, {String note = ''}) {
    final at = DateTime.now();
    final verdict = i.evaluate(day, at);
    final log = TrackerLog(
      id: TrackerLog.keyFor(c.id, i.id, day),
      challengeId: c.id,
      itemId: i.id,
      forDay: dayKey(day),
      at: at.toIso8601String(),
      status: tickStatusName(verdict.status),
      lateBy: verdict.lateBy,
      by: _uid,
      note: note,
    );
    _db.setIn(_owner, 'trackerLogs', log.id, log.toMap());
    return log;
  }

  void untick(Challenge c, TrackerItem i, DateTime day) =>
      _db.removeIn(_owner, 'trackerLogs', TrackerLog.keyFor(c.id, i.id, day));

  /// Ticks if clear, clears if ticked. Returns the new row, or null when the
  /// box was cleared.
  TrackerLog? toggle(Challenge c, TrackerItem i, DateTime day) {
    if (isTicked(c.id, i.id, day)) {
      untick(c, i, day);
      return null;
    }
    return tick(c, i, day);
  }

  void restoreLog(String id, Map<String, dynamic> data) => _db.setIn(_owner, 'trackerLogs', id, data);

  // ------------------------------------------------------------- the day

  /// Items still to tick today, soonest deadline first. Drives the today view
  /// and the home-screen summary.
  List<TrackerItem> dueToday(Challenge c) => memo('dueToday:${c.id}', () {
        final t = todayDate();
        final out = itemsOn(c.id, t).where((i) => !isTicked(c.id, i.id, t)).toList();
        out.sort((a, b) {
          final first = a.deadlineOn(t);
          final second = b.deadlineOn(t);
          // No deadline means no urgency, so those sink to the bottom.
          if (first == null && second == null) return a.order.compareTo(b.order);
          if (first == null) return 1;
          if (second == null) return -1;
          return first.compareTo(second);
        });
        return out;
      });

  int doneOn(Challenge c, DateTime day) => memo('doneOn:${c.id}:${dayKey(day)}',
      () => itemsOn(c.id, day).where((i) => isTicked(c.id, i.id, day)).length);

  int expectedOn(Challenge c, DateTime day) => itemsOn(c.id, day).length;

  /// Share of today's items already ticked, 0..1.
  double progressOn(Challenge c, DateTime day) {
    final total = expectedOn(c, day);
    return total == 0 ? 0 : doneOn(c, day) / total;
  }

  // -------------------------------------------------------------- totals

  /// Every (day, item) the challenge expected from day 1 up to [upTo],
  /// defaulting to today. Future days are never counted as missed.
  int expectedTotal(Challenge c, {DateTime? upTo}) {
    final end = upTo ?? todayDate();
    var n = 0;
    for (final d in c.allDays()) {
      if (d.isAfter(end)) break;
      n += itemsOn(c.id, d).length;
    }
    return n;
  }

  int tickedTotal(Challenge c, {DateTime? upTo}) {
    final end = upTo ?? todayDate();
    return logs
        .where((l) => l.challengeId == c.id)
        .where((l) {
          final d = l.day;
          return d != null && !d.isAfter(end) && c.dayNumber(d) != null;
        })
        .length;
  }

  /// Counts by status across the run so far — the number the dashboard and
  /// the mentor report are both built on.
  ///
  /// [where] narrows it to a slice: a week, a month, or every Monday.
  TrackerTally tally(
    Challenge c, {
    DateTime? upTo,
    String? itemId,
    bool Function(DateTime day)? where,
  }) {
    final end = upTo ?? todayDate();
    var onTime = 0, overdue = 0, back = 0, expected = 0;
    for (final d in c.allDays()) {
      if (d.isAfter(end)) break;
      if (where != null && !where(d)) continue;
      for (final i in itemsOn(c.id, d)) {
        if (itemId != null && i.id != itemId) continue;
        expected++;
        final log = logFor(c.id, i.id, d);
        if (log == null) continue;
        switch (log.tickStatus) {
          case TickStatus.onTime:
            onTime++;
            break;
          case TickStatus.overdue:
            overdue++;
            break;
          case TickStatus.backfilled:
            back++;
            break;
          default:
            break;
        }
      }
    }
    return TrackerTally(
      onTime: onTime,
      lateTicks: overdue,
      backfilled: back,
      missed: expected - (onTime + overdue + back),
      expected: expected,
    );
  }

  // ------------------------------------------------------ breakdowns

  /// One tally per week of the run: week 1, week 2, and so on. Weeks are
  /// counted from day 1 of the challenge, not from Monday, because "week 2 of
  /// my 21 days" is what you actually want to compare.
  List<(int week, TrackerTally tally)> byWeek(Challenge c) => memo('byWeek:${c.id}', () {
        final today = todayDate();
        final out = <(int, TrackerTally)>[];
        for (var w = 1; w <= c.weekCount; w++) {
          final t = tally(c, where: (d) => c.weekNumber(d) == w);
          // Drop weeks that have not begun — an empty row reads as a failure.
          final starts = addDays(c.start ?? today, (w - 1) * 7);
          if (starts.isAfter(today)) continue;
          out.add((w, t));
        }
        return out;
      });

  /// One tally per calendar month the run touches.
  List<(DateTime month, TrackerTally tally)> byMonth(Challenge c) => memo('byMonth:${c.id}', () {
        final today = todayDate();
        final months = <DateTime>[];
        for (final d in c.allDays()) {
          if (d.isAfter(today)) break;
          final m = DateTime(d.year, d.month);
          if (!months.any((e) => e.year == m.year && e.month == m.month)) months.add(m);
        }
        return [
          for (final m in months)
            (m, tally(c, where: (d) => d.year == m.year && d.month == m.month)),
        ];
      });

  /// One tally per weekday, so "I always slip on Sundays" becomes visible.
  /// [weekStart] decides the order rows come back in.
  List<(int weekday, TrackerTally tally)> byWeekday(Challenge c, {int weekStart = DateTime.monday}) =>
      memo('byWeekday:${c.id}:$weekStart', () {
        final order = [for (var i = 0; i < 7; i++) ((weekStart - 1 + i) % 7) + 1];
        return [
          for (final wd in order) (wd, tally(c, where: (d) => d.weekday == wd)),
        ];
      });

  /// Completion rate for each day of the run so far, oldest first — the
  /// series behind the daily trend chart.
  List<(DateTime day, double rate)> byDay(Challenge c) => memo('byDay:${c.id}', () {
        final today = todayDate();
        final out = <(DateTime, double)>[];
        for (final d in c.allDays()) {
          if (d.isAfter(today)) break;
          out.add((d, progressOn(c, d)));
        }
        return out;
      });

  /// One tally per habit, in sheet order — the per-column report.
  List<(TrackerItem item, TrackerTally tally)> byItem(Challenge c) => memo('byItem:${c.id}', () {
        return [
          for (final i in itemsOf(c.id)) (i, tally(c, itemId: i.id)),
        ];
      });

  /// Consecutive days, ending at the most recent completed day, on which an
  /// item was ticked. Today still being open never breaks it.
  int streakOf(Challenge c, TrackerItem i) => memo('streak:${c.id}:${i.id}', () {
        final t = todayDate();
        var day = t;
        if (!isTicked(c.id, i.id, day)) day = addDays(day, -1);
        var n = 0;
        final from = i.start;
        while (from != null && !day.isBefore(from) && c.dayNumber(day) != null) {
          if (!isTicked(c.id, i.id, day)) break;
          n++;
          day = addDays(day, -1);
        }
        return n;
      });

  int bestStreakOf(Challenge c, TrackerItem i) => memo('best:${c.id}:${i.id}', () {
        var best = 0, cur = 0;
        final t = todayDate();
        for (final d in c.allDays()) {
          if (d.isAfter(t)) break;
          if (!i.runsOn(d)) continue;
          if (isTicked(c.id, i.id, d)) {
            cur++;
            if (cur > best) best = cur;
          } else if (!sameDay(d, t)) {
            cur = 0;
          }
        }
        return best;
      });

  /// Days where every expected item was ticked — the "perfect day" count.
  int perfectDays(Challenge c) => memo('perfect:${c.id}', () {
        final t = todayDate();
        var n = 0;
        for (final d in c.allDays()) {
          if (d.isAfter(t)) break;
          final total = itemsOn(c.id, d).length;
          if (total > 0 && doneOn(c, d) == total) n++;
        }
        return n;
      });
}

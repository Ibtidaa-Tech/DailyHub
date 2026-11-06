import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/currencies.dart';
import '../core/localization.dart';
import '../core/settings.dart';
import '../data/models.dart';
import '../data/plan_store.dart';
import '../data/tracker_models.dart';
import 'db_service.dart';
import 'notification_service.dart';

class _Plan {
  final String title;
  final String body;
  final DateTime when;
  final String channel;
  final DateTimeComponents? match;
  final bool actions;
  final Map<String, dynamic> payload;
  _Plan(this.title, this.body, this.when,
      {this.channel = NotifChannel.reminders, this.match, this.actions = false, this.payload = const {}});

  String get sig => '$title|$body|${when.toIso8601String()}|$channel|${match?.name}|$actions';
}

/// Keeps OS notifications in sync with your data.
///
/// Rather than every screen scheduling alerts itself, the planner watches
/// your tasks, reminders, bills, lend/borrow dues and habits, works out the
/// full set of notifications that *should* exist, and applies only the
/// difference. So edits made on another device, or data restored from a
/// backup, get the right alerts automatically.
class NotificationPlanner {
  NotificationPlanner._();
  static final NotificationPlanner instance = NotificationPlanner._();

  static const _stateKey = 'dh_planner_state_v2';

  final DbService _db = DbService.instance;
  final List<StreamSubscription<dynamic>> _subs = [];
  AppSettings? _settings;
  Timer? _debounce;
  bool _running = false;

  List<Task> _tasks = [];
  List<Reminder> _reminders = [];
  List<Bill> _bills = [];
  List<Debt> _debts = [];
  List<Habit> _habits = [];
  List<Challenge> _challenges = [];
  List<TrackerItem> _trItems = [];
  List<TrackerLog> _trLogs = [];
  final Set<String> _loaded = {};

  /// Every source the planner waits for before it touches a single alarm.
  /// Syncing on a half-loaded picture would cancel alarms that are real.
  static const int _sourceCount = 8;

  String _t(String k) => AppStrings.of(_settings?.lang ?? 'en', k);
  String _tr(String k, Map<String, Object?> a) => AppStrings.fill(_t(k), a);

  void start(AppSettings settings) {
    if (kIsWeb) return;
    stop();
    _settings = settings;
    _running = true;
    void on(String name, Stream<List<Map<String, dynamic>>> s, void Function(List<Map<String, dynamic>>) set) {
      _subs.add(s.listen((v) {
        set(v);
        _loaded.add(name);
        schedule();
      }));
    }

    on('todos', _db.stream('todos'), (v) => _tasks = v.map(Task.fromMap).toList());
    on('reminders', _db.stream('reminders'), (v) => _reminders = v.map(Reminder.fromMap).toList());
    on('bills', _db.stream('bills'), (v) => _bills = v.map(Bill.fromMap).toList());
    on('debts', _db.stream('debts'), (v) => _debts = v.map(Debt.fromMap).toList());
    on('habits', _db.stream('habits'), (v) => _habits = v.map(Habit.fromMap).toList());
    on('challenges', _db.stream('challenges'), (v) => _challenges = v.map(Challenge.fromMap).toList());
    on('trackerItems', _db.stream('trackerItems'), (v) => _trItems = v.map(TrackerItem.fromMap).toList());
    on('trackerLogs', _db.stream('trackerLogs'), (v) => _trLogs = v.map(TrackerLog.fromMap).toList());
    settings.addListener(schedule);
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _settings?.removeListener(schedule);
    _debounce?.cancel();
    _loaded.clear();
    _running = false;
  }

  /// Cancels everything the planner scheduled (used on sign-out).
  Future<void> clearAll() async {
    stop();
    if (kIsWeb) return;
    final state = await _loadState();
    for (final k in state.keys) {
      await NotificationService.instance.cancel(k);
    }
    await _saveState({});
  }

  void schedule() {
    if (!_running) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), _sync);
  }

  Future<Map<String, String>> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stateKey);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveState(Map<String, String> s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stateKey, jsonEncode(s));
    } catch (_) {}
  }

  bool _syncing = false;

  Future<void> _sync() async {
    if (!_running || _syncing) return;
    // Wait until every source has loaded, so a half-loaded state never
    // cancels real alarms.
    if (_loaded.length < _sourceCount) return;
    _syncing = true;
    try {
      final settings = _settings!;
      NotificationService.lang = settings.lang;
      if (!settings.notifMigrated) {
        await NotificationService.instance.cancelAll();
        settings.markNotifMigrated();
      }
      final desired = _desired(settings);
      final old = await _loadState();
      final next = <String, String>{};
      for (final k in old.keys) {
        if (!desired.containsKey(k)) {
          await NotificationService.instance.cancel(k);
        }
      }
      for (final e in desired.entries) {
        final sig = e.value.sig;
        next[e.key] = sig;
        if (old[e.key] == sig) continue;
        final p = e.value;
        final payload = jsonEncode({...p.payload, 'k': e.key, 'ti': p.title, 'b': p.body});
        if (p.match != null) {
          await NotificationService.instance.scheduleRepeating(
            key: e.key,
            title: p.title,
            body: p.body,
            first: p.when,
            match: p.match!,
            channel: p.channel,
            actions: p.actions,
            payload: payload,
          );
        } else {
          await NotificationService.instance.scheduleAt(
            key: e.key,
            title: p.title,
            body: p.body,
            when: p.when,
            channel: p.channel,
            actions: p.actions,
            payload: payload,
          );
        }
      }
      await _saveState(next);
    } catch (e) {
      debugPrint('Planner sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  /// Clock time for notification text. The planner has no BuildContext, so it
  /// cannot use the formatting extensions the UI uses.
  String _clock(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (_settings?.use24h ?? false) return '${two(d.hour)}:${two(d.minute)}';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  DateTime _at(DateTime day, String hm, {int fallbackHour = 9}) {
    final t = parseHm(hm);
    return DateTime(day.year, day.month, day.day, t?.hour ?? fallbackHour, t?.minute ?? 0);
  }

  Map<String, _Plan> _desired(AppSettings s) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));
    final out = <String, _Plan>{};

    // Tasks with a time and a reminder offset.
    final taskPlans = <MapEntry<String, _Plan>>[];
    for (final t in _tasks) {
      if (!t.isOpen) continue;
      final at = t.remindAt;
      if (at == null || !at.isAfter(now) || at.isAfter(horizon)) continue;
      final body = t.remind > 0
          ? _tr('notif_task_in', {'m': t.remind})
          : (t.desc.isNotEmpty ? t.desc : _t('notif_task_now'));
      taskPlans.add(MapEntry(
          'task_${t.id}',
          _Plan('✅ ${t.title}', body, at,
              actions: true, payload: {'t': 'task', 'id': t.id})));
    }
    taskPlans.sort((a, b) => a.value.when.compareTo(b.value.when));
    for (final e in taskPlans.take(150)) {
      out[e.key] = e.value;
    }

    // Reminders.
    for (final r in _reminders) {
      if (r.done || r.when == null) continue;
      final title = '⏰ ${r.title}';
      final body = r.notes.isNotEmpty ? r.notes : _t('notif_reminder');
      final pay = {'t': 'rem', 'id': r.id};
      final w = r.when!;
      switch (r.repeat) {
        case 'daily':
          out['rem_${r.id}'] = _Plan(title, body, rollForward(w, 'daily'),
              match: DateTimeComponents.time, actions: true, payload: pay);
          break;
        case 'weekly':
          out['rem_${r.id}'] = _Plan(title, body, rollForward(w, 'weekly'),
              match: DateTimeComponents.dayOfWeekAndTime, actions: true, payload: pay);
          break;
        case 'weekdays':
          for (var wd = 1; wd <= 5; wd++) {
            var d = DateTime(now.year, now.month, now.day, w.hour, w.minute);
            while (d.weekday != wd || !d.isAfter(now)) {
              d = DateTime(d.year, d.month, d.day + 1, w.hour, w.minute);
            }
            out['rem_${r.id}_w$wd'] = _Plan(title, body, d,
                match: DateTimeComponents.dayOfWeekAndTime, actions: true, payload: pay);
          }
          break;
        case 'monthly':
          final anchor = r.anchor > 0 ? r.anchor : w.day;
          final next = w.isAfter(now) ? w : rollForward(w, 'monthly', anchorDay: anchor);
          out['rem_${r.id}'] = _Plan(title, body, next,
              match: anchor <= 28 ? DateTimeComponents.dayOfMonthAndTime : null,
              actions: true,
              payload: pay);
          break;
        case 'yearly':
          final next = w.isAfter(now) ? w : rollForward(w, 'yearly', anchorDay: r.anchor > 0 ? r.anchor : w.day);
          out['rem_${r.id}'] = _Plan(title, body, next,
              match: DateTimeComponents.dateAndTime, actions: true, payload: pay);
          break;
        default:
          if (w.isAfter(now)) {
            out['rem_${r.id}'] = _Plan(title, body, w, actions: true, payload: pay);
          }
      }
    }

    // Bills: a heads-up before and a nudge on the day.
    for (final b in _bills) {
      if (!b.active) continue;
      final due = b.dueDate;
      if (due == null) continue;
      final amt = Money.format(b.amount);
      final pay = {'t': 'bill', 'id': b.id};
      if (b.remindDays > 0) {
        final pre = _at(DateTime(due.year, due.month, due.day - b.remindDays), '09:00');
        if (pre.isAfter(now) && pre.isBefore(horizon)) {
          out['bill_${b.id}_pre'] = _Plan('${b.emoji} ${b.name}',
              _tr(b.type == 'income' ? 'notif_income_soon' : 'notif_bill_soon', {'n': b.remindDays, 'a': amt}), pre,
              payload: pay);
        }
      }
      final onDay = _at(due, '09:00');
      if (onDay.isAfter(now) && onDay.isBefore(horizon)) {
        out['bill_${b.id}_due'] = _Plan('${b.emoji} ${b.name}',
            _tr(b.type == 'income' ? 'notif_income_today' : 'notif_bill_today', {'a': amt}), onDay,
            payload: pay);
      }
    }

    // Lend / borrow due dates.
    for (final d in _debts) {
      if (d.settled || d.remaining <= 0) continue;
      final due = parseDay(d.due);
      if (due == null) continue;
      final at = _at(due, '10:00');
      if (!at.isAfter(now)) continue;
      out['debt_${d.id}'] = _Plan(
          d.isLent ? '🤝 ${_tr('notif_owes_you', {'p': d.person})}' : '🤝 ${_tr('notif_you_owe', {'p': d.person})}',
          Money.format(d.remaining), at,
          payload: {'t': 'debt', 'id': d.id});
    }

    // Habit nudges.
    for (final h in _habits) {
      if (h.archived) continue;
      final t = parseHm(h.remind);
      if (t == null) continue;
      final title = '${h.emoji} ${h.name}';
      final body = h.kind == 'count'
          ? _tr('notif_habit_count', {'n': h.target, 'u': h.unit})
          : _t('notif_habit_body');
      final pay = {'t': 'habit', 'id': h.id};
      if (h.days.isEmpty || h.days.length == 7) {
        var d = DateTime(now.year, now.month, now.day, t.hour, t.minute);
        if (!d.isAfter(now)) d = DateTime(d.year, d.month, d.day + 1, t.hour, t.minute);
        out['habit_${h.id}'] = _Plan(title, body, d,
            channel: NotifChannel.habits, match: DateTimeComponents.time, payload: pay);
      } else {
        for (final wd in h.days) {
          var d = DateTime(now.year, now.month, now.day, t.hour, t.minute);
          while (d.weekday != wd || !d.isAfter(now)) {
            d = DateTime(d.year, d.month, d.day + 1, t.hour, t.minute);
          }
          out['habit_${h.id}_d$wd'] = _Plan(title, body, d,
              channel: NotifChannel.habits, match: DateTimeComponents.dayOfWeekAndTime, payload: pay);
        }
      }
    }

    // Habit tracker: a nudge when each window opens, and a last call shortly
    // before it closes. Both disappear the moment the box is ticked, because
    // ticking changes trackerLogs and the planner re-runs against the new set.
    //
    // These are one-offs over a short horizon rather than daily repeats: a
    // repeat would keep firing after the run ends if the app were never
    // reopened, and a tracker that nags you about a finished challenge is
    // worse than one that goes quiet.
    final trackerPlans = <MapEntry<String, _Plan>>[];
    final ticked = {for (final l in _trLogs) l.id};
    for (final c in _challenges) {
      if (!c.isActive) continue;
      final items = _trItems.where((i) => i.challengeId == c.id).toList();
      for (var ahead = 0; ahead < 3; ahead++) {
        final day = DateTime(now.year, now.month, now.day + ahead);
        if (c.dayNumber(day) == null) continue;
        for (final i in items) {
          if (!i.runsOn(day)) continue;
          if (ticked.contains(TrackerLog.keyFor(c.id, i.id, day))) continue;
          final title = '${i.emoji} ${i.name}';
          final pay = {'t': 'tr', 'id': i.id, 'c': c.id};
          final opens = i.opensOn(day);
          final deadline = i.deadlineOn(day);
          if (opens != null && opens.isAfter(now) && opens.isBefore(horizon)) {
            trackerPlans.add(MapEntry(
              'tr_${i.id}_${dayKey(day)}',
              _Plan(
                title,
                deadline == null
                    ? _t('tr_notif_due_open')
                    : _tr('tr_notif_due', {'t': _clock(deadline)}),
                opens,
                channel: NotifChannel.tracker,
                actions: true,
                payload: pay,
              ),
            ));
          }
          if (deadline != null) {
            final lastCall = deadline.subtract(const Duration(minutes: 10));
            // Only worth a second alert if the window is wider than the nudge.
            if (lastCall.isAfter(now) &&
                lastCall.isBefore(horizon) &&
                (opens == null || lastCall.isAfter(opens))) {
              trackerPlans.add(MapEntry(
                'tr_${i.id}_${dayKey(day)}_end',
                _Plan(
                  title,
                  _tr('tr_notif_closing', {'n': 10}),
                  lastCall,
                  channel: NotifChannel.tracker,
                  actions: true,
                  payload: pay,
                ),
              ));
            }
          }
        }
      }
    }
    trackerPlans.sort((a, b) => a.value.when.compareTo(b.value.when));
    for (final e in trackerPlans.take(80)) {
      out[e.key] = e.value;
    }

    // Morning briefing & evening review for the coming week.
    for (var i = 0; i < 7; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      if (s.morningBriefing) {
        final at = _at(day, s.morningTime, fallbackHour: 8);
        if (at.isAfter(now)) {
          out['brief_m_${dayKey(day)}'] = _Plan(_t('notif_morning_title'), _morningBody(day), at,
              channel: NotifChannel.briefing, payload: {'t': 'brief_m'});
        }
      }
      if (s.eveningReview) {
        final at = _at(day, s.eveningTime, fallbackHour: 21);
        if (at.isAfter(now)) {
          out['brief_e_${dayKey(day)}'] = _Plan(_t('notif_evening_title'), _eveningBody(day, i == 0), at,
              channel: NotifChannel.briefing, payload: {'t': 'brief_e'});
        }
      }
    }
    return out;
  }

  String _morningBody(DateTime day) {
    final isToday = sameDay(day, DateTime.now());
    final tasks = _tasks.where((t) => t.isOpen && (t.isDueOn(day) || (isToday && t.isOverdue()))).length;
    final rems = _reminders.where((r) {
      if (r.done || r.when == null) return false;
      if (r.repeat == 'daily') return true;
      if (r.repeat == 'weekdays') return day.weekday <= 5;
      if (r.repeat == 'weekly') return r.when!.weekday == day.weekday;
      return sameDay(r.when!, day);
    }).length;
    final bills = _bills.where((b) => b.active && b.dueDate != null && sameDay(b.dueDate!, day)).length;
    final habits = _habits.where((h) => !h.archived && h.isScheduled(day)).length;
    final parts = <String>[];
    if (tasks > 0) parts.add(_tr(tasks == 1 ? 'n_tasks_one' : 'n_tasks_other', {'n': tasks}));
    if (rems > 0) parts.add(_tr(rems == 1 ? 'n_reminders_one' : 'n_reminders_other', {'n': rems}));
    if (bills > 0) parts.add(_tr(bills == 1 ? 'n_bills_one' : 'n_bills_other', {'n': bills}));
    if (habits > 0) parts.add(_tr(habits == 1 ? 'n_habits_one' : 'n_habits_other', {'n': habits}));
    if (parts.isEmpty) return _t('notif_morning_empty');
    return '${parts.join(' · ')}. ${_t('notif_morning_tail')}';
  }

  String _eveningBody(DateTime day, bool isToday) {
    if (!isToday) return _t('notif_evening_generic');
    final due = _tasks.where((t) => t.isDueOn(day) && t.status != 'cancelled').toList();
    final done = due.where((t) => t.isDone).length +
        _tasks.where((t) => t.isOpen && t.raw['lastDone'] != null && sameDay(DateTime.tryParse('${t.raw['lastDone']}') ?? DateTime(2000), day)).length;
    final left = due.where((t) => t.isOpen).length;
    if (due.isEmpty && done == 0) return _t('notif_evening_generic');
    return _tr('notif_evening_body', {'d': done, 'l': left});
  }

  /// "Done" tapped on a notification.
  ///
  /// For a tracker item this logs it for today at the current moment, which
  /// is the same path the UI takes — so tapping Done at 7am is on time and
  /// tapping it at midnight is recorded as late, exactly as it should be.
  void completeFromNotification(String type, String id) {
    if (type == 'tr') {
      TrackerItem? item;
      for (final i in _trItems) {
        if (i.id == id) {
          item = i;
          break;
        }
      }
      if (item == null) return;
      Challenge? challenge;
      for (final c in _challenges) {
        if (c.id == item.challengeId) {
          challenge = c;
          break;
        }
      }
      if (challenge == null || !challenge.isActive) return;
      final day = todayDate();
      if (challenge.dayNumber(day) == null || !item.runsOn(day)) return;
      // Tapping Done on the notification means "I have just done it", so the
      // completion time and the record time are the same moment here.
      final at = DateTime.now();
      final verdict = item.evaluate(at);
      final key = TrackerLog.keyFor(challenge.id, item.id, day);
      _db.set(
        'trackerLogs',
        key,
        TrackerLog(
          id: key,
          challengeId: challenge.id,
          itemId: item.id,
          forDay: dayKey(day),
          at: at.toIso8601String(),
          doneAt: at.toIso8601String(),
          status: tickStatusName(verdict.status),
          lateBy: verdict.lateBy,
          by: _db.uid ?? '',
        ).toMap(),
      );
      return;
    }
    if (type == 'task') {
      for (final t in _tasks) {
        if (t.id == id) {
          final c = PlanStore.toggled(t);
          _db.set('todos', t.id, c.toMap());
          return;
        }
      }
    } else if (type == 'rem') {
      for (final r in _reminders) {
        if (r.id == id) {
          if (r.repeats && r.when != null) {
            final next = rollForward(r.when!, r.repeat, anchorDay: r.anchor > 0 ? r.anchor : null);
            _db.update('reminders', r.id, {'when': next.toIso8601String()});
          } else {
            _db.update('reminders', r.id, {'done': true});
          }
          return;
        }
      }
    }
  }
}

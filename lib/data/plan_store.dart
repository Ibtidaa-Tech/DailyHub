import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Tasks, task lists and reminders.
///
/// Tasks and lists belong to the active workspace (so shared workspaces
/// work); reminders are always personal.
class PlanStore extends LiveStore {
  PlanStore() {
    bind();
  }

  final DbService _db = DbService.instance;

  List<Task> tasks = [];
  List<TaskList> lists = [];
  List<Reminder> reminders = [];

  /// (Re)subscribe — called at start and whenever the workspace changes.
  void bind() {
    cancelAll();
    tasks = [];
    lists = [];
    watch('todos', _db.stream('todos', workspace: true), (List<Map<String, dynamic>> v) {
      tasks = v.map(Task.fromMap).where((t) => t.title.isNotEmpty || t.id.isNotEmpty).toList();
    });
    watch('lists', _db.stream('lists', workspace: true), (List<Map<String, dynamic>> v) {
      lists = v.map(TaskList.fromMap).toList()..sort((a, b) => a.order.compareTo(b.order));
    });
    watch('reminders', _db.stream('reminders'), (List<Map<String, dynamic>> v) {
      reminders = v.map(Reminder.fromMap).toList();
    });
  }

  // ----------------------------------------------------------- queries

  static int _cmp(Task a, Task b) {
    final da = a.due, db = b.due;
    if (da != null && db != null) {
      final c = da.compareTo(db);
      if (c != 0) return c;
    } else if (da != null) {
      return -1;
    } else if (db != null) {
      return 1;
    }
    final p = Prio.rank(b.priority).compareTo(Prio.rank(a.priority));
    if (p != 0) return p;
    return a.createdAt.compareTo(b.createdAt);
  }

  List<Task> get open => memo('open', () => tasks.where((t) => t.isOpen).toList()..sort(_cmp));

  List<Task> get overdue => memo('overdue', () {
        final now = DateTime.now();
        return open.where((t) => t.isOverdue(now)).toList();
      });

  List<Task> dueOn(DateTime day, {bool includeDone = false}) => tasks
      .where((t) => t.isDueOn(day) && (includeDone ? t.status != 'cancelled' : t.isOpen))
      .toList()
    ..sort(_cmp);

  /// Tasks due today that are still open and not overdue-by-time.
  List<Task> get today => memo('today', () {
        final now = DateTime.now();
        return open.where((t) => t.isDueOn(now) && !t.isOverdue(now)).toList();
      });

  List<Task> get completedToday => memo('doneToday', () {
        final t = todayDate();
        return tasks.where((x) {
          if (!x.isDone) return false;
          final d = DateTime.tryParse(x.doneAt);
          return d != null && sameDay(d, t);
        }).toList();
      });

  List<Task> get noDate => memo('noDate', () => open.where((t) => t.dueDate == null).toList());

  List<Task> inList(String listId) =>
      open.where((t) => listId == 'inbox' ? t.list.isEmpty : t.list == listId).toList();

  List<Task> withTag(String tag) => open.where((t) => t.tags.contains(tag)).toList();

  List<String> get tags => memo('tags', () {
        final s = <String>{};
        for (final t in tasks) {
          s.addAll(t.tags);
        }
        return s.toList()..sort();
      });

  TaskList? listById(String id) {
    for (final l in lists) {
      if (l.id == id) return l;
    }
    return null;
  }

  Task? taskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<Reminder> get activeReminders => memo('remActive', () =>
      reminders.where((r) => !r.done && r.when != null).toList()
        ..sort((a, b) => a.when!.compareTo(b.when!)));

  List<Reminder> remindersOn(DateTime day) =>
      activeReminders.where((r) => sameDay(r.when!, day)).toList();

  List<Reminder> get overdueReminders => memo('remOverdue', () {
        final now = DateTime.now();
        return activeReminders.where((r) => !r.repeats && r.when!.isBefore(now) && !sameDay(r.when!, now)).toList();
      });

  Reminder? reminderById(String id) {
    for (final r in reminders) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Open tasks grouped by date for the next [days] days (today first).
  Map<DateTime, List<Task>> upcoming(int days, {String? listId}) {
    final out = <DateTime, List<Task>>{};
    final t0 = todayDate();
    for (var i = 0; i < days; i++) {
      final d = addDays(t0, i);
      final items = dueOn(d).where((t) => listId == null || t.list == listId).toList();
      if (items.isNotEmpty) out[d] = items;
    }
    return out;
  }

  int countOpenIn(String listId) => inList(listId).length;

  // ----------------------------------------------------------- tasks

  /// Adds or updates a task. Returns its id.
  String saveTask(Task t) {
    if (t.repeat == 'monthly' || t.repeat == 'yearly') {
      t.anchor = t.dueDate?.day ?? t.anchor;
    }
    if (t.id.isEmpty) {
      return _db.addNow('todos', t.toMap(), workspace: true);
    }
    _db.set('todos', t.id, t.toMap(), workspace: true);
    return t.id;
  }

  /// Completes (or re-opens) a task. Repeating tasks roll to their next date.
  /// Returns the previous state for undo.
  Map<String, dynamic> toggleTask(Task t) {
    final before = t.toMap();
    final c = toggled(t);
    _db.set('todos', c.id, c.toMap(), workspace: true);
    return before;
  }

  /// The task as it should look after tapping its checkbox.
  static Task toggled(Task t) {
    final c = t.copy();
    if (c.isDone) {
      c.status = 'upcoming';
      c.doneAt = '';
    } else if (c.repeat != 'none' && c.dueDate != null) {
      final tm = parseHm(c.time);
      final base = c.dueDate!;
      final anchor = c.anchor > 0 ? c.anchor : null;
      var next = nextOccurrence(
          DateTime(base.year, base.month, base.day, tm?.hour ?? 0, tm?.minute ?? 0), c.repeat,
          anchorDay: anchor);
      final t0 = todayDate();
      var guard = 0;
      while (dateOnly(next).isBefore(t0) && guard < 1000) {
        next = nextOccurrence(next, c.repeat, anchorDay: anchor);
        guard++;
      }
      c.date = dayKey(next);
      for (final s in c.subtasks) {
        s.done = false;
      }
      c.raw['lastDone'] = nowIso();
      c.raw['doneCount'] = toI(c.raw['doneCount']) + 1;
    } else {
      c.status = 'completed';
      c.doneAt = nowIso();
    }
    return c;
  }

  void setStatus(Task t, String status) {
    final c = t.copy()
      ..status = status
      ..doneAt = status == 'completed' ? nowIso() : '';
    saveTask(c);
  }

  void reschedule(Task t, DateTime? day, {String? time}) {
    final c = t.copy()
      ..date = day == null ? '' : dayKey(day)
      ..time = day == null ? '' : (time ?? t.time);
    saveTask(c);
  }

  void rescheduleAll(List<Task> list, DateTime day) {
    for (final t in list) {
      reschedule(t, day);
    }
  }

  void toggleSubtask(Task t, int i) {
    if (i < 0 || i >= t.subtasks.length) return;
    final c = t.copy();
    c.subtasks[i].done = !c.subtasks[i].done;
    saveTask(c);
  }

  void addFocus(Task t, int minutes) {
    _db.update('todos', t.id, {'focus': t.focus + minutes}, workspace: true);
  }

  /// Returns the removed data so the caller can offer undo.
  Map<String, dynamic> deleteTask(Task t) {
    final data = t.toMap();
    _db.remove('todos', t.id, workspace: true);
    return data;
  }

  void restoreTask(String id, Map<String, dynamic> data) =>
      _db.set('todos', id, data, workspace: true);

  // ----------------------------------------------------------- lists

  String saveList(TaskList l) {
    if (l.id.isEmpty) {
      l.order = lists.length;
      return _db.addNow('lists', l.toMap(), workspace: true);
    }
    _db.set('lists', l.id, l.toMap(), workspace: true);
    return l.id;
  }

  void deleteList(TaskList l) {
    for (final t in tasks.where((t) => t.list == l.id)) {
      _db.update('todos', t.id, {'list': ''}, workspace: true);
    }
    _db.remove('lists', l.id, workspace: true);
  }

  // ------------------------------------------------------- reminders

  String saveReminder(Reminder r) {
    if (r.repeat == 'monthly' || r.repeat == 'yearly') {
      r.anchor = r.when?.day ?? r.anchor;
    }
    if (r.id.isEmpty) return _db.addNow('reminders', r.toMap());
    _db.set('reminders', r.id, r.toMap());
    return r.id;
  }

  /// Marks done; repeating reminders jump to the next occurrence instead.
  Map<String, dynamic> completeReminder(Reminder r) {
    final before = r.toMap();
    if (r.repeats && r.when != null) {
      final next = rollForward(r.when!, r.repeat, anchorDay: r.anchor > 0 ? r.anchor : null);
      _db.update('reminders', r.id, {'when': next.toIso8601String()});
    } else {
      _db.update('reminders', r.id, {'done': !r.done});
    }
    return before;
  }

  void snoozeReminder(Reminder r, Duration by) {
    final base = DateTime.now().add(by);
    _db.update('reminders', r.id, {'when': base.toIso8601String(), 'done': false});
  }

  Map<String, dynamic> deleteReminder(Reminder r) {
    final data = r.toMap();
    _db.remove('reminders', r.id);
    return data;
  }

  void restoreReminder(String id, Map<String, dynamic> data) => _db.set('reminders', id, data);
}

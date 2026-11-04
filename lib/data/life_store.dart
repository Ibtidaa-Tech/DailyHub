import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Notes (Keep-style) — personal.
class NotesStore extends LiveStore {
  NotesStore() {
    watch('notes', _db.stream('notes'), (List<Map<String, dynamic>> v) {
      notes = v.map(Note.fromMap).toList()
        ..sort((a, b) {
          final ua = a.updatedAt.isEmpty ? a.createdAt : a.updatedAt;
          final ub = b.updatedAt.isEmpty ? b.createdAt : b.updatedAt;
          return ub.compareTo(ua);
        });
    });
  }

  final DbService _db = DbService.instance;
  List<Note> notes = [];

  List<Note> get active => notes.where((n) => !n.archived).toList();
  List<Note> get archived => notes.where((n) => n.archived).toList();

  List<String> get labels => memo('labels', () {
        final s = <String>{};
        for (final n in notes) {
          s.addAll(n.labels);
        }
        return s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });

  Note? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  String save(Note n) {
    if (n.id.isEmpty) return _db.addNow('notes', n.toMap());
    _db.set('notes', n.id, n.toMap());
    return n.id;
  }

  void update(Note n, Map<String, dynamic> fields) =>
      _db.update('notes', n.id, {...fields, 'updatedAt': nowIso()});

  Map<String, dynamic> delete(Note n) {
    final data = n.toMap();
    _db.remove('notes', n.id);
    return data;
  }

  void restore(String id, Map<String, dynamic> data) => _db.set('notes', id, data);
}

/// Habits — personal.
class HabitsStore extends LiveStore {
  HabitsStore() {
    watch('habits', _db.stream('habits'), (List<Map<String, dynamic>> v) {
      habits = v.map(Habit.fromMap).toList()
        ..sort((a, b) {
          final o = a.order.compareTo(b.order);
          return o != 0 ? o : a.createdAt.compareTo(b.createdAt);
        });
    });
  }

  final DbService _db = DbService.instance;
  List<Habit> habits = [];

  List<Habit> get active => habits.where((h) => !h.archived).toList();

  List<Habit> scheduledOn(DateTime d) => active.where((h) => h.isScheduled(d)).toList();

  Habit? byId(String id) {
    for (final h in habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// Today's progress across scheduled habits: (done, total).
  (int, int) progressOn(DateTime d) {
    final list = scheduledOn(d);
    return (list.where((h) => h.doneOn(d)).length, list.length);
  }

  String save(Habit h) {
    if (h.id.isEmpty) {
      h.order = habits.length;
      return _db.addNow('habits', h.toMap());
    }
    _db.set('habits', h.id, h.toMap());
    return h.id;
  }

  /// Check-habits toggle; count-habits add one (and wrap to 0 after target).
  void tap(Habit h, DateTime day) {
    final k = dayKey(day);
    if (h.kind == 'count') {
      final v = h.valueOn(day);
      final next = v >= h.target ? 0 : v + 1;
      _setDay(h, k, next == 0 ? null : next);
    } else {
      _setDay(h, k, h.doneOn(day) ? null : true);
    }
  }

  void setCount(Habit h, DateTime day, int value) =>
      _setDay(h, dayKey(day), value <= 0 ? null : value);

  void _setDay(Habit h, String k, Object? value) {
    // Optimistic local update so rapid taps feel instant.
    if (value == null) {
      h.history.remove(k);
    } else {
      h.history[k] = value;
    }
    invalidate();
    if (value == null) {
      _db.remove('habits/${h.id}/history', k);
    } else {
      _db.updateNode('habits/${h.id}/history', {k: value});
    }
  }

  void archive(Habit h, bool v) => _db.update('habits', h.id, {'archived': v});

  Map<String, dynamic> delete(Habit h) {
    final data = h.toMap();
    _db.remove('habits', h.id);
    return data;
  }

  void restore(String id, Map<String, dynamic> data) => _db.set('habits', id, data);
}

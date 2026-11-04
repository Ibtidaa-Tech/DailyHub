import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Something somebody agreed to do in a meeting.
class ActionItem {
  String title;
  bool done;
  String taskId; // set once it's been pushed into Plan
  String owner;

  ActionItem({this.title = '', this.done = false, this.taskId = '', this.owner = ''});

  factory ActionItem.from(Object? v) {
    if (v is Map) {
      return ActionItem(
        title: str(v['title']),
        done: toB(v['done']),
        taskId: str(v['taskId']),
        owner: str(v['owner']),
      );
    }
    return ActionItem(title: str(v));
  }

  Map<String, dynamic> toMap() => {'title': title, 'done': done, 'taskId': taskId, 'owner': owner};
}

/// A meeting, with its agenda, notes and the actions that came out of it.
class Meeting {
  final String id;
  final Map<String, dynamic> raw;
  String title;
  DateTime? at;
  int minutes;
  String place;
  String attendees;
  String agenda;
  String notes;
  bool done;
  List<ActionItem> actions;

  Meeting({
    this.id = '',
    Map<String, dynamic>? raw,
    this.title = '',
    this.at,
    this.minutes = 30,
    this.place = '',
    this.attendees = '',
    this.agenda = '',
    this.notes = '',
    this.done = false,
    List<ActionItem>? actions,
  })  : raw = raw ?? {},
        actions = actions ?? [];

  factory Meeting.from(Map<String, dynamic> m) {
    final acts = <ActionItem>[];
    final a = m['actions'];
    if (a is List) {
      for (final e in a) {
        final item = ActionItem.from(e);
        if (item.title.isNotEmpty) acts.add(item);
      }
    } else if (a is Map) {
      a.forEach((_, v) {
        final item = ActionItem.from(v);
        if (item.title.isNotEmpty) acts.add(item);
      });
    }
    final mins = toI(m['minutes']);
    return Meeting(
      id: str(m['id']),
      raw: m,
      title: str(m['title']),
      at: DateTime.tryParse(str(m['at'])),
      minutes: mins <= 0 ? 30 : mins,
      place: str(m['place']),
      attendees: str(m['attendees']),
      agenda: str(m['agenda']),
      notes: str(m['notes']),
      done: toB(m['done']),
      actions: acts,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'at': at?.toIso8601String() ?? '',
        'minutes': minutes,
        'place': place,
        'attendees': attendees,
        'agenda': agenda,
        'notes': notes,
        'done': done,
        'actions': actions.map((e) => e.toMap()).toList(),
      };

  DateTime? get endsAt => at?.add(Duration(minutes: minutes));

  bool get isPast {
    final e = endsAt;
    return done || (e != null && e.isBefore(DateTime.now()));
  }

  bool get isNow {
    final s = at, e = endsAt;
    if (s == null || e == null) return false;
    final now = DateTime.now();
    return !now.isBefore(s) && now.isBefore(e);
  }

  int get openActions => actions.where((a) => !a.done).length;

  /// Names as a list, for chips.
  List<String> get attendeeList => attendees
      .split(RegExp(r'[,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// Meetings and what came out of them.
class WorkStore extends LiveStore {
  WorkStore() {
    bind();
  }

  final DbService _db = DbService.instance;
  List<Meeting> meetings = [];

  void bind() {
    cancelAll();
    watch('meetings', _db.stream('meetings'), (List<Map<String, dynamic>> v) {
      meetings = v.map(Meeting.from).toList()
        ..sort((a, b) {
          final x = a.at, y = b.at;
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return x.compareTo(y);
        });
    });
    invalidate();
  }

  List<Meeting> get upcoming => meetings.where((m) => !m.isPast).toList();

  List<Meeting> get past => meetings.where((m) => m.isPast).toList().reversed.toList();

  List<Meeting> on(DateTime day) =>
      meetings.where((m) => m.at != null && sameDay(m.at!, day)).toList();

  Meeting? byId(String id) {
    for (final m in meetings) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Every open action item across all meetings.
  List<(Meeting, ActionItem)> get openActions {
    final out = <(Meeting, ActionItem)>[];
    for (final m in meetings) {
      for (final a in m.actions) {
        if (!a.done) out.add((m, a));
      }
    }
    return out;
  }

  /// Names seen before, so attendees autocomplete.
  List<String> get knownAttendees {
    final counts = <String, int>{};
    for (final m in meetings) {
      for (final n in m.attendeeList) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final names = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return names;
  }

  // -------------------------------------------------------------- writes

  String save(Meeting m) {
    if (m.id.isEmpty) {
      final id = _db.newId('meetings');
      _db.set('meetings', id, m.toMap());
      return id;
    }
    _db.set('meetings', m.id, m.toMap());
    return m.id;
  }

  void setActions(Meeting m, List<ActionItem> actions) {
    m.actions
      ..clear()
      ..addAll(actions);
    invalidate();
    _db.update('meetings', m.id, {'actions': actions.map((e) => e.toMap()).toList()});
  }

  void toggleAction(Meeting m, int index) {
    if (index < 0 || index >= m.actions.length) return;
    final items = List<ActionItem>.from(m.actions);
    final a = items[index];
    items[index] = ActionItem(title: a.title, done: !a.done, taskId: a.taskId, owner: a.owner);
    setActions(m, items);
  }

  void setDone(Meeting m, bool done) {
    m.done = done;
    invalidate();
    _db.update('meetings', m.id, {'done': done});
  }

  void setNotes(Meeting m, String notes) {
    m.notes = notes;
    _db.update('meetings', m.id, {'notes': notes});
  }

  Map<String, dynamic> delete(Meeting m) {
    final data = Map<String, dynamic>.from(m.raw)..remove('id');
    _db.remove('meetings', m.id);
    return data;
  }

  void restore(String id, Map<String, dynamic> data) => _db.set('meetings', id, data);
}

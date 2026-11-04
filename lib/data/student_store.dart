import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Days as stored in the timetable. Kept as short English keys so the data is
/// stable across languages; the UI translates them.
const List<String> kDayKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String dayKeyOfWeekday(int weekday) => kDayKeys[(weekday - 1).clamp(0, 6)];

/// One slot in the weekly timetable.
class Klass {
  final String id;
  final Map<String, dynamic> raw;
  String subject;
  String room;
  String teacher;
  String day; // Mon..Sun
  String start; // HH:mm
  String end; // HH:mm

  Klass({
    this.id = '',
    Map<String, dynamic>? raw,
    this.subject = '',
    this.room = '',
    this.teacher = '',
    this.day = 'Mon',
    this.start = '09:00',
    this.end = '10:00',
  }) : raw = raw ?? {};

  factory Klass.from(Map<String, dynamic> m) => Klass(
        id: str(m['id']),
        raw: m,
        subject: str(m['subject']),
        room: str(m['room']),
        teacher: str(m['teacher']),
        day: kDayKeys.contains(str(m['day'])) ? str(m['day']) : 'Mon',
        start: str(m['start']).isEmpty ? '09:00' : str(m['start']),
        end: str(m['end']).isEmpty ? '10:00' : str(m['end']),
      );

  Map<String, dynamic> toMap() => {
        'subject': subject,
        'room': room,
        'teacher': teacher,
        'day': day,
        'start': start,
        'end': end,
      };

  /// Sort key inside a day.
  int get startMinutes {
    final t = parseHm(start);
    return t == null ? 0 : t.hour * 60 + t.minute;
  }

  int get endMinutes {
    final t = parseHm(end);
    return t == null ? startMinutes + 60 : t.hour * 60 + t.minute;
  }

  /// A stable id for one occurrence of this class on a given day.
  String slotKey(DateTime day) => '${dayKey(day)}_$id';
}

/// A piece of work with a due date.
class Assignment {
  final String id;
  final Map<String, dynamic> raw;
  String title;
  String subject;
  String due; // day key, may be empty
  String notes;
  bool done;

  Assignment({
    this.id = '',
    Map<String, dynamic>? raw,
    this.title = '',
    this.subject = '',
    this.due = '',
    this.notes = '',
    this.done = false,
  }) : raw = raw ?? {};

  factory Assignment.from(Map<String, dynamic> m) => Assignment(
        id: str(m['id']),
        raw: m,
        title: str(m['title']),
        subject: str(m['subject']),
        due: str(m['due']),
        notes: str(m['notes']),
        done: toB(m['done']),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'subject': subject,
        'due': due,
        'notes': notes,
        'done': done,
      };

  DateTime? get dueDate => parseDay(due);

  bool get isOverdue {
    final d = dueDate;
    return !done && d != null && d.isBefore(todayDate());
  }

  int? get daysLeft {
    final d = dueDate;
    return d == null ? null : daysBetween(todayDate(), d);
  }
}

/// A subject, with the credits and grade used for the CGPA.
class SubjectInfo {
  final String id;
  final Map<String, dynamic> raw;
  String name;
  String code;
  double credits;
  String grade; // '' when not graded yet
  int color;

  SubjectInfo({
    this.id = '',
    Map<String, dynamic>? raw,
    this.name = '',
    this.code = '',
    this.credits = 3,
    this.grade = '',
    this.color = 0,
  }) : raw = raw ?? {};

  factory SubjectInfo.from(Map<String, dynamic> m) {
    final c = toD(m['credits']);
    return SubjectInfo(
      id: str(m['id']),
      raw: m,
      name: str(m['name']),
      code: str(m['code']),
      credits: c <= 0 ? 3 : c,
      grade: str(m['grade']),
      color: toI(m['color']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'code': code,
        'credits': credits,
        'grade': grade,
        'color': color,
      };
}

/// India's common 10-point scale. Points are what the CGPA is computed from.
const Map<String, double> kGradePoints = {
  'O': 10, 'A+': 9, 'A': 8, 'B+': 7, 'B': 6, 'C': 5, 'P': 4, 'F': 0,
};

/// Attendance for one subject.
///
/// `base*` is what you'd already attended before starting to use the app, so
/// nobody has to back-fill a whole semester. `log` holds one entry per class
/// you mark from the timetable. Totals are the two added together, which keeps
/// daily marking a single tap without losing the history.
class Attendance {
  final String id;
  final Map<String, dynamic> raw;
  String subject;
  int baseAttended;
  int baseTotal;
  Map<String, String> log; // slotKey -> present | absent | cancelled

  Attendance({
    this.id = '',
    Map<String, dynamic>? raw,
    this.subject = '',
    this.baseAttended = 0,
    this.baseTotal = 0,
    Map<String, String>? log,
  })  : raw = raw ?? {},
        log = log ?? {};

  factory Attendance.from(Map<String, dynamic> m) {
    final l = <String, String>{};
    final rawLog = m['log'];
    if (rawLog is Map) {
      rawLog.forEach((k, v) => l['$k'] = '$v');
    }
    return Attendance(
      id: str(m['id']),
      raw: m,
      subject: str(m['subject']),
      // Older records stored plain attended/total counters.
      baseAttended: toI(m['baseAttended'] ?? m['attended']),
      baseTotal: toI(m['baseTotal'] ?? m['total']),
      log: l,
    );
  }

  Map<String, dynamic> toMap() => {
        'subject': subject,
        'baseAttended': baseAttended,
        'baseTotal': baseTotal,
        'log': log,
      };

  int get loggedPresent => log.values.where((v) => v == 'present').length;
  int get loggedAbsent => log.values.where((v) => v == 'absent').length;

  int get attended => baseAttended + loggedPresent;

  /// Cancelled classes don't count against you.
  int get total => baseTotal + loggedPresent + loggedAbsent;

  double get rate => total == 0 ? 0 : attended / total;
  int get percent => total == 0 ? 0 : (rate * 100).round();

  /// How many more classes you may miss and still sit on [target] (0–1).
  int canSkip(double target) {
    if (target <= 0) return 999;
    if (total == 0) return 0;
    final k = attended / target - total;
    return k <= 0 ? 0 : k.floor();
  }

  /// How many in a row you must attend to climb back to [target].
  int mustAttend(double target) {
    if (target >= 1) return 999;
    if (rate >= target) return 0;
    final k = (target * total - attended) / (1 - target);
    return k <= 0 ? 0 : k.ceil();
  }
}

/// Timetable, assignments, attendance and grades.
class StudentStore extends LiveStore {
  StudentStore() {
    bind();
  }

  final DbService _db = DbService.instance;

  List<Klass> classes = [];
  List<Assignment> assignments = [];
  List<SubjectInfo> subjects = [];
  List<Attendance> attendance = [];

  void bind() {
    cancelAll();
    watch('timetable', _db.stream('timetable'), (List<Map<String, dynamic>> v) {
      classes = v.map(Klass.from).toList()
        ..sort((a, b) {
          final d = kDayKeys.indexOf(a.day).compareTo(kDayKeys.indexOf(b.day));
          return d != 0 ? d : a.startMinutes.compareTo(b.startMinutes);
        });
    });
    watch('assignments', _db.stream('assignments'), (List<Map<String, dynamic>> v) {
      assignments = v.map(Assignment.from).toList()
        ..sort((a, b) {
          if (a.done != b.done) return a.done ? 1 : -1;
          final x = a.dueDate, y = b.dueDate;
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return x.compareTo(y);
        });
    });
    watch('subjects', _db.stream('subjects'), (List<Map<String, dynamic>> v) {
      subjects = v.map(SubjectInfo.from).toList()..sort((a, b) => a.name.compareTo(b.name));
    });
    watch('attendance', _db.stream('attendance'), (List<Map<String, dynamic>> v) {
      attendance = v.map(Attendance.from).toList()..sort((a, b) => a.subject.compareTo(b.subject));
    });
    invalidate();
  }

  // ------------------------------------------------------------- lookups

  List<Klass> classesOn(DateTime day) {
    final k = dayKeyOfWeekday(day.weekday);
    return classes.where((c) => c.day == k).toList();
  }

  Klass? classById(String id) {
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Every subject name known to the app, from subjects, timetable and marks.
  List<String> get subjectNames {
    final out = <String>{};
    for (final s in subjects) {
      if (s.name.isNotEmpty) out.add(s.name);
    }
    for (final c in classes) {
      if (c.subject.isNotEmpty) out.add(c.subject);
    }
    for (final a in attendance) {
      if (a.subject.isNotEmpty) out.add(a.subject);
    }
    final list = out.toList()..sort();
    return list;
  }

  SubjectInfo? subjectByName(String name) {
    for (final s in subjects) {
      if (s.name.toLowerCase() == name.toLowerCase()) return s;
    }
    return null;
  }

  Attendance? attendanceFor(String subject) {
    for (final a in attendance) {
      if (a.subject.toLowerCase() == subject.toLowerCase()) return a;
    }
    return null;
  }

  List<Assignment> get openAssignments => assignments.where((a) => !a.done).toList();

  List<Assignment> assignmentsDueOn(DateTime day) =>
      assignments.where((a) => !a.done && a.dueDate != null && sameDay(a.dueDate!, day)).toList();

  List<Assignment> get overdueAssignments => assignments.where((a) => a.isOverdue).toList();

  // ------------------------------------------------------------- totals

  /// Attendance across every subject.
  (int attended, int total) get overall {
    var a = 0, t = 0;
    for (final x in attendance) {
      a += x.attended;
      t += x.total;
    }
    return (a, t);
  }

  double get overallRate {
    final (a, t) = overall;
    return t == 0 ? 0 : a / t;
  }

  /// Credit-weighted average on the 10-point scale, and the credits counted.
  (double cgpa, double credits) get cgpa {
    var points = 0.0, credits = 0.0;
    for (final s in subjects) {
      final g = kGradePoints[s.grade];
      if (g == null || s.credits <= 0) continue;
      points += g * s.credits;
      credits += s.credits;
    }
    return (credits == 0 ? 0 : points / credits, credits);
  }

  // ------------------------------------------------------------- writes

  String saveClass(Klass k) {
    if (k.id.isEmpty) {
      final id = _db.newId('timetable');
      _db.set('timetable', id, k.toMap());
      return id;
    }
    _db.set('timetable', k.id, k.toMap());
    return k.id;
  }

  Map<String, dynamic> deleteClass(Klass k) {
    final data = Map<String, dynamic>.from(k.raw)..remove('id');
    _db.remove('timetable', k.id);
    return data;
  }

  String saveAssignment(Assignment a) {
    if (a.id.isEmpty) {
      final id = _db.newId('assignments');
      _db.set('assignments', id, a.toMap());
      return id;
    }
    _db.set('assignments', a.id, a.toMap());
    return a.id;
  }

  void toggleAssignment(Assignment a) => _db.update('assignments', a.id, {'done': !a.done});

  Map<String, dynamic> deleteAssignment(Assignment a) {
    final data = Map<String, dynamic>.from(a.raw)..remove('id');
    _db.remove('assignments', a.id);
    return data;
  }

  String saveSubject(SubjectInfo s) {
    if (s.id.isEmpty) {
      final id = _db.newId('subjects');
      _db.set('subjects', id, s.toMap());
      return id;
    }
    _db.set('subjects', s.id, s.toMap());
    return s.id;
  }

  Map<String, dynamic> deleteSubject(SubjectInfo s) {
    final data = Map<String, dynamic>.from(s.raw)..remove('id');
    _db.remove('subjects', s.id);
    return data;
  }

  /// Returns the attendance record for [subject], creating it if needed.
  Attendance _ensure(String subject) {
    final found = attendanceFor(subject);
    if (found != null) return found;
    final rec = Attendance(subject: subject);
    final id = _db.newId('attendance');
    _db.set('attendance', id, rec.toMap());
    final created = Attendance(id: id, subject: subject, raw: {'id': id, ...rec.toMap()});
    attendance = [...attendance, created]..sort((a, b) => a.subject.compareTo(b.subject));
    invalidate();
    return created;
  }

  /// Marks one timetable slot present / absent / cancelled. Passing the status
  /// it already has clears it, so tapping twice undoes the mark.
  void markClass(Klass k, DateTime day, String status) {
    final rec = _ensure(k.subject);
    final key = k.slotKey(day);
    final log = Map<String, String>.from(rec.log);
    if (log[key] == status) {
      log.remove(key);
    } else {
      log[key] = status;
    }
    rec.log
      ..clear()
      ..addAll(log);
    invalidate();
    _db.update('attendance', rec.id, {'log': log});
  }

  String statusOf(Klass k, DateTime day) => attendanceFor(k.subject)?.log[k.slotKey(day)] ?? '';

  /// Manual counters, for a subject with no timetable slot.
  void bumpAttendance(String subject, {required bool present}) {
    final rec = _ensure(subject);
    final a = rec.baseAttended + (present ? 1 : 0);
    final t = rec.baseTotal + 1;
    rec.baseAttended = a;
    rec.baseTotal = t;
    invalidate();
    _db.update('attendance', rec.id, {'baseAttended': a, 'baseTotal': t});
  }

  void setAttendanceBase(String subject, int attended, int total) {
    final rec = _ensure(subject);
    rec.baseAttended = attended;
    rec.baseTotal = total;
    invalidate();
    _db.update('attendance', rec.id, {'baseAttended': attended, 'baseTotal': total});
  }

  Map<String, dynamic> deleteAttendance(Attendance a) {
    final data = Map<String, dynamic>.from(a.raw)..remove('id');
    _db.remove('attendance', a.id);
    return data;
  }

  void restore(String collection, String id, Map<String, dynamic> data) =>
      _db.set(collection, id, data);
}

import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Typed models over the raw Firebase maps. Each keeps the original map in
/// [raw] and merges into it on save, so fields written by other screens
/// (links, attachments…) are never lost.
/// ---------------------------------------------------------------------------

// ------------------------------------------------------------------ helpers

String _two(int n) => n.toString().padLeft(2, '0');

String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String hmKey(int h, int m) => '${_two(h)}:${_two(m)}';

String hmOf(DateTime d) => hmKey(d.hour, d.minute);

DateTime? parseDay(String? s) {
  if (s == null || s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

TimeOfDay? parseHm(String? s) {
  if (s == null || !s.contains(':')) return null;
  final p = s.split(':');
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null || h > 23 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime todayDate() => dateOnly(DateTime.now());
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
/// Whole calendar days from [from] to [to] (DST-safe).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Calendar-day arithmetic (never skips a day across DST changes).
DateTime addDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n, d.hour, d.minute);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Adds months without spilling into the next month (Jan 31 + 1 = Feb 28/29).
DateTime addMonths(DateTime d, int months, {int? anchorDay}) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final day = (anchorDay ?? d.day).clamp(1, daysInMonth(y, m));
  return DateTime(y, m, day, d.hour, d.minute);
}

/// Next occurrence after [from] for a repeat rule.
DateTime nextOccurrence(DateTime from, String repeat, {int? anchorDay}) {
  switch (repeat) {
    case 'daily':
      return DateTime(from.year, from.month, from.day + 1, from.hour, from.minute);
    case 'weekdays':
      var n = DateTime(from.year, from.month, from.day + 1, from.hour, from.minute);
      while (n.weekday == DateTime.saturday || n.weekday == DateTime.sunday) {
        n = DateTime(n.year, n.month, n.day + 1, n.hour, n.minute);
      }
      return n;
    case 'weekly':
      return DateTime(from.year, from.month, from.day + 7, from.hour, from.minute);
    case 'monthly':
      return addMonths(from, 1, anchorDay: anchorDay);
    case 'quarterly':
      return addMonths(from, 3, anchorDay: anchorDay);
    case 'yearly':
      return addMonths(from, 12, anchorDay: anchorDay);
    default:
      return from;
  }
}

/// Rolls [start] forward until it is after [now].
DateTime rollForward(DateTime start, String repeat, {DateTime? now, int? anchorDay}) {
  final limit = now ?? DateTime.now();
  var n = start;
  var guard = 0;
  while (!n.isAfter(limit) && guard < 5000) {
    final next = nextOccurrence(n, repeat, anchorDay: anchorDay);
    if (next == n) break;
    n = next;
    guard++;
  }
  return n;
}

double toD(Object? v) {
  final double d = v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);
  return d.isFinite ? d : 0.0;
}

int toI(Object? v) {
  if (v is num) return v.isFinite ? v.toInt() : 0;
  final t = '${v ?? ''}';
  final i = int.tryParse(t);
  if (i != null) return i;
  final d = double.tryParse(t);
  return d != null && d.isFinite ? d.toInt() : 0;
}

String str(Object? v) => v == null ? '' : '$v';
bool toB(Object? v) => v == true || v == 'true';

List<String> strList(Object? v) {
  if (v is List) return v.where((e) => e != null).map((e) => '$e').where((e) => e.isNotEmpty).toList();
  if (v is String && v.trim().isNotEmpty) {
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return [];
}

List<Map<String, dynamic>> mapList(Object? v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (v is Map) {
    return v.values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return [];
}

String nowIso() => DateTime.now().toIso8601String();

// -------------------------------------------------------------- sub items

class SubItem {
  String title;
  bool done;
  SubItem(this.title, {this.done = false});
  factory SubItem.fromMap(Map<String, dynamic> m) =>
      SubItem(str(m['title'] ?? m['text']), done: toB(m['done']));
  Map<String, dynamic> toMap() => {'title': title, 'done': done};
}

// ------------------------------------------------------------------ tasks

class Prio {
  static const none = 'none', low = 'low', medium = 'medium', high = 'high';
  static const all = [high, medium, low, none];
  static int rank(String p) => switch (p) { high => 3, medium => 2, low => 1, _ => 0 };
  static Color color(String p) => switch (p) {
        high => const Color(0xFFE5484D),
        medium => const Color(0xFFF59E0B),
        low => const Color(0xFF3B82F6),
        _ => const Color(0xFF9CA3AF),
      };
}

class Task {
  final String id;
  final Map<String, dynamic> raw;
  String title;
  String desc;
  String date; // yyyy-MM-dd or ''
  String time; // HH:mm or ''
  String priority;
  String repeat;
  String status; // upcoming | completed | cancelled
  List<SubItem> subtasks;
  String list;
  List<String> tags;
  int remind; // minutes before due; -1 = off
  String createdAt;
  String doneAt;
  int anchor;
  int focus; // total focus minutes

  Task({
    this.id = '',
    Map<String, dynamic>? raw,
    this.title = '',
    this.desc = '',
    this.date = '',
    this.time = '',
    this.priority = Prio.none,
    this.repeat = 'none',
    this.status = 'upcoming',
    List<SubItem>? subtasks,
    this.list = '',
    List<String>? tags,
    this.remind = 0,
    this.createdAt = '',
    this.doneAt = '',
    this.anchor = 0,
    this.focus = 0,
  })  : raw = raw ?? {},
        subtasks = subtasks ?? [],
        tags = tags ?? [];

  factory Task.fromMap(Map<String, dynamic> m) => Task(
        id: str(m['id']),
        raw: m,
        title: str(m['title']),
        desc: str(m['desc']),
        date: str(m['date']),
        time: str(m['time']),
        priority: str(m['priority']).toLowerCase().isEmpty ? Prio.none : str(m['priority']).toLowerCase(),
        repeat: str(m['repeat']).isEmpty ? 'none' : str(m['repeat']),
        status: str(m['status']).isEmpty ? 'upcoming' : str(m['status']),
        subtasks: mapList(m['subtasks']).map(SubItem.fromMap).toList(),
        list: str(m['list']),
        tags: strList(m['tags']),
        remind: m['remind'] == null ? 0 : toI(m['remind']),
        createdAt: str(m['createdAt']),
        doneAt: str(m['doneAt']),
        anchor: toI(m['anchor']),
        focus: toI(m['focus']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'title': title,
        'desc': desc,
        'date': date,
        'time': time,
        'priority': priority,
        'repeat': repeat,
        'status': status,
        'subtasks': subtasks.map((s) => s.toMap()).toList(),
        'list': list,
        'tags': tags,
        'remind': remind,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
        'doneAt': doneAt,
        'anchor': anchor,
        'focus': focus,
      }..remove('id');

  Task copy() => Task.fromMap({...toMap(), 'id': id});

  bool get isDone => status == 'completed';
  bool get isOpen => status == 'upcoming';
  bool get hasTime => parseHm(time) != null;
  DateTime? get dueDate => parseDay(date);

  /// Due moment; untimed tasks count as due at the end of their day.
  DateTime? get due {
    final d = dueDate;
    if (d == null) return null;
    final t = parseHm(time);
    return t == null
        ? DateTime(d.year, d.month, d.day, 23, 59)
        : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  DateTime? get remindAt {
    final d = dueDate;
    final t = parseHm(time);
    if (d == null || t == null || remind < 0) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute)
        .subtract(Duration(minutes: remind));
  }

  bool isOverdue([DateTime? now]) {
    if (!isOpen) return false;
    final n = now ?? DateTime.now();
    final d = dueDate;
    if (d == null) return false;
    if (hasTime) return due!.isBefore(n);
    return d.isBefore(dateOnly(n));
  }

  bool isDueOn(DateTime day) {
    final d = dueDate;
    return d != null && sameDay(d, day);
  }

  int get subDone => subtasks.where((s) => s.done).length;
}

class TaskList {
  final String id;
  String name;
  String emoji;
  int color;
  int order;
  TaskList({this.id = '', this.name = '', this.emoji = '📁', this.color = 0, this.order = 0});
  factory TaskList.fromMap(Map<String, dynamic> m) => TaskList(
        id: str(m['id']),
        name: str(m['name']),
        emoji: str(m['emoji']).isEmpty ? '📁' : str(m['emoji']),
        color: toI(m['color']),
        order: toI(m['order']),
      );
  Map<String, dynamic> toMap() => {'name': name, 'emoji': emoji, 'color': color, 'order': order};
}

// -------------------------------------------------------------- reminders

class Reminder {
  final String id;
  final Map<String, dynamic> raw;
  String title;
  DateTime? when;
  String repeat; // once | daily | weekdays | weekly | monthly | yearly
  String notes;
  bool done;
  String createdAt;
  int anchor;

  Reminder({
    this.id = '',
    Map<String, dynamic>? raw,
    this.title = '',
    this.when,
    this.repeat = 'once',
    this.notes = '',
    this.done = false,
    this.createdAt = '',
    this.anchor = 0,
  }) : raw = raw ?? {};

  factory Reminder.fromMap(Map<String, dynamic> m) => Reminder(
        id: str(m['id']),
        raw: m,
        title: str(m['title']),
        when: DateTime.tryParse(str(m['when'])),
        repeat: str(m['repeat']).isEmpty || m['repeat'] == 'none' ? 'once' : str(m['repeat']),
        notes: str(m['notes']),
        done: toB(m['done']),
        createdAt: str(m['createdAt']),
        anchor: toI(m['anchor']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'title': title,
        'when': when?.toIso8601String() ?? '',
        'repeat': repeat,
        'notes': notes,
        'done': done,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
        'anchor': anchor,
      }..remove('id');

  bool get repeats => repeat != 'once';
  bool isOverdue([DateTime? now]) =>
      !done && when != null && when!.isBefore(now ?? DateTime.now());
}

// ------------------------------------------------------------------ money

class TxnType {
  static const expense = 'expense', income = 'income', transfer = 'transfer';
}

class Txn {
  final String id;
  final Map<String, dynamic> raw;
  String type;
  double amount;
  String category;
  String note;
  String date;
  String time;
  String account;
  String toAccount;
  List<String> photos;
  Map<String, dynamic>? split;
  String billId;
  String createdAt;

  Txn({
    this.id = '',
    Map<String, dynamic>? raw,
    this.type = TxnType.expense,
    this.amount = 0,
    this.category = '',
    this.note = '',
    this.date = '',
    this.time = '',
    this.account = '',
    this.toAccount = '',
    List<String>? photos,
    this.split,
    this.billId = '',
    this.createdAt = '',
  })  : raw = raw ?? {},
        photos = photos ?? [];

  factory Txn.fromMap(Map<String, dynamic> m) => Txn(
        id: str(m['id']),
        raw: m,
        type: str(m['type']).isEmpty ? TxnType.expense : str(m['type']),
        amount: toD(m['amount']).abs(),
        category: str(m['category']),
        note: str(m['note']),
        date: str(m['date']),
        time: str(m['time']),
        account: str(m['account']),
        toAccount: str(m['toAccount']),
        photos: strList(m['photos']),
        split: m['split'] is Map ? Map<String, dynamic>.from(m['split']) : null,
        billId: str(m['billId']),
        createdAt: str(m['createdAt']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'type': type,
        'amount': amount,
        'category': category,
        'note': note,
        'date': date,
        'time': time,
        'account': account,
        'toAccount': toAccount,
        'photos': photos,
        'split': split,
        'billId': billId,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
      }..remove('id');

  DateTime get day => parseDay(date) ?? todayDate();
  bool get isExpense => type == TxnType.expense;
  bool get isIncome => type == TxnType.income;
  bool get isTransfer => type == TxnType.transfer;
  String get monthKey => date.length >= 7 ? date.substring(0, 7) : '';

  DateTime get sortKey {
    final d = day;
    final t = parseHm(time);
    return t == null ? d : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }
}

class Account {
  final String id;
  String name;
  String kind; // cash | bank | upi | card | wallet | other
  String emoji;
  int color;
  double opening;
  bool archived;
  int order;
  Account({
    this.id = '',
    this.name = '',
    this.kind = 'cash',
    this.emoji = '💵',
    this.color = 1,
    this.opening = 0,
    this.archived = false,
    this.order = 0,
  });
  factory Account.fromMap(Map<String, dynamic> m) => Account(
        id: str(m['id']),
        name: str(m['name']),
        kind: str(m['kind']).isEmpty ? 'other' : str(m['kind']),
        emoji: str(m['emoji']).isEmpty ? '💳' : str(m['emoji']),
        color: toI(m['color']),
        opening: toD(m['opening']),
        archived: toB(m['archived']),
        order: toI(m['order']),
      );
  Map<String, dynamic> toMap() => {
        'name': name,
        'kind': kind,
        'emoji': emoji,
        'color': color,
        'opening': opening,
        'archived': archived,
        'order': order,
      };
}

class Category {
  final String id;
  String name;
  String key; // built-in translation key, cleared when renamed
  String kind; // expense | income
  String emoji;
  int color;
  int order;
  bool archived;
  Category({
    this.id = '',
    this.name = '',
    this.key = '',
    this.kind = 'expense',
    this.emoji = '📦',
    this.color = 0,
    this.order = 0,
    this.archived = false,
  });
  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: str(m['id']),
        name: str(m['name']),
        key: str(m['key']),
        kind: str(m['kind']).isEmpty ? 'expense' : str(m['kind']),
        emoji: str(m['emoji']).isEmpty ? '📦' : str(m['emoji']),
        color: toI(m['color']),
        order: toI(m['order']),
        archived: toB(m['archived']),
      );
  Map<String, dynamic> toMap() => {
        'name': name,
        'key': key,
        'kind': kind,
        'emoji': emoji,
        'color': color,
        'order': order,
        'archived': archived,
      };
}

class Budget {
  final String id;
  String category; // '_total' or category id
  double limit;
  Budget({this.id = '', this.category = '_total', this.limit = 0});
  factory Budget.fromMap(Map<String, dynamic> m) =>
      Budget(id: str(m['id']), category: str(m['category']), limit: toD(m['limit']));
  Map<String, dynamic> toMap() => {'category': category, 'limit': limit};
}

class Bill {
  final String id;
  String name;
  double amount;
  String type; // expense | income
  String category;
  String account;
  String freq; // weekly | monthly | quarterly | yearly
  String due; // next due date
  int remindDays;
  String emoji;
  bool active;
  String lastPaid;
  int anchor;
  Bill({
    this.id = '',
    this.name = '',
    this.amount = 0,
    this.type = TxnType.expense,
    this.category = '',
    this.account = '',
    this.freq = 'monthly',
    this.due = '',
    this.remindDays = 2,
    this.emoji = '🧾',
    this.active = true,
    this.lastPaid = '',
    this.anchor = 0,
  });
  factory Bill.fromMap(Map<String, dynamic> m) => Bill(
        id: str(m['id']),
        name: str(m['name']),
        amount: toD(m['amount']),
        type: str(m['type']).isEmpty ? TxnType.expense : str(m['type']),
        category: str(m['category']),
        account: str(m['account']),
        freq: str(m['freq']).isEmpty ? 'monthly' : str(m['freq']),
        due: str(m['due']),
        remindDays: m['remindDays'] == null ? 2 : toI(m['remindDays']),
        emoji: str(m['emoji']).isEmpty ? '🧾' : str(m['emoji']),
        active: m['active'] == null ? true : toB(m['active']),
        lastPaid: str(m['lastPaid']),
        anchor: toI(m['anchor']),
      );
  Map<String, dynamic> toMap() => {
        'name': name,
        'amount': amount,
        'type': type,
        'category': category,
        'account': account,
        'freq': freq,
        'due': due,
        'remindDays': remindDays,
        'emoji': emoji,
        'active': active,
        'lastPaid': lastPaid,
        'anchor': anchor,
      };
  DateTime? get dueDate => parseDay(due);
  int daysLeft([DateTime? from]) {
    final d = dueDate;
    if (d == null) return 9999;
    return daysBetween(from ?? DateTime.now(), d);
  }
}

class Debt {
  final String id;
  String person;
  String phone;
  String kind; // lent (they owe you) | borrowed (you owe them)
  double amount;
  String note;
  String date;
  String due;
  bool settled;
  List<Map<String, dynamic>> payments;
  Debt({
    this.id = '',
    this.person = '',
    this.phone = '',
    this.kind = 'lent',
    this.amount = 0,
    this.note = '',
    this.date = '',
    this.due = '',
    this.settled = false,
    List<Map<String, dynamic>>? payments,
  }) : payments = payments ?? [];
  factory Debt.fromMap(Map<String, dynamic> m) => Debt(
        id: str(m['id']),
        person: str(m['person']),
        phone: str(m['phone']),
        kind: str(m['kind']) == 'borrowed' ? 'borrowed' : 'lent',
        amount: toD(m['amount']),
        note: str(m['note']),
        date: str(m['date']),
        due: str(m['due']),
        settled: toB(m['settled']),
        payments: mapList(m['payments']),
      );
  Map<String, dynamic> toMap() => {
        'person': person,
        'phone': phone,
        'kind': kind,
        'amount': amount,
        'note': note,
        'date': date,
        'due': due,
        'settled': settled,
        'payments': payments,
      };
  double get paid => payments.fold(0.0, (s, p) => s + toD(p['amount']));
  double get remaining => settled ? 0 : (amount - paid).clamp(0, double.infinity).toDouble();
  bool get isLent => kind == 'lent';
}

class SavingsGoal {
  final String id;
  String name;
  double target;
  String emoji;
  int color;
  String deadline;
  List<Map<String, dynamic>> entries;
  String createdAt;
  SavingsGoal({
    this.id = '',
    this.name = '',
    this.target = 0,
    this.emoji = '🎯',
    this.color = 0,
    this.deadline = '',
    List<Map<String, dynamic>>? entries,
    this.createdAt = '',
  }) : entries = entries ?? [];
  factory SavingsGoal.fromMap(Map<String, dynamic> m) => SavingsGoal(
        id: str(m['id']),
        name: str(m['name']),
        target: toD(m['target']),
        emoji: str(m['emoji']).isEmpty ? '🎯' : str(m['emoji']),
        color: toI(m['color']),
        deadline: str(m['deadline']),
        entries: mapList(m['entries']),
        createdAt: str(m['createdAt']),
      );
  Map<String, dynamic> toMap() => {
        'name': name,
        'target': target,
        'emoji': emoji,
        'color': color,
        'deadline': deadline,
        'entries': entries,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
      };
  double get saved => entries.fold(0.0, (s, e) => s + toD(e['amount']));
  double get progress => target <= 0 ? 0 : (saved / target).clamp(0, 1).toDouble();
}

// ------------------------------------------------------------------ notes

class Note {
  final String id;
  final Map<String, dynamic> raw;
  String title;
  String body;
  int color;
  bool pinned;
  bool archived;
  List<String> labels;
  List<String> photos;
  List<String> voice;
  List<SubItem> checklist;
  bool isChecklist;
  String createdAt;
  String updatedAt;

  Note({
    this.id = '',
    Map<String, dynamic>? raw,
    this.title = '',
    this.body = '',
    this.color = 0,
    this.pinned = false,
    this.archived = false,
    List<String>? labels,
    List<String>? photos,
    List<String>? voice,
    List<SubItem>? checklist,
    this.isChecklist = false,
    this.createdAt = '',
    this.updatedAt = '',
  })  : raw = raw ?? {},
        labels = labels ?? [],
        photos = photos ?? [],
        voice = voice ?? [],
        checklist = checklist ?? [];

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: str(m['id']),
        raw: m,
        title: str(m['title']),
        body: str(m['body']),
        color: toI(m['color']),
        pinned: toB(m['pinned']),
        archived: toB(m['archived']),
        labels: strList(m['labels'] ?? m['tags']),
        photos: strList(m['photos']),
        voice: strList(m['voice']),
        checklist: mapList(m['checklist']).map(SubItem.fromMap).toList(),
        isChecklist: toB(m['isChecklist']),
        createdAt: str(m['createdAt']),
        updatedAt: str(m['updatedAt']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'title': title,
        'body': body,
        'color': color,
        'pinned': pinned,
        'archived': archived,
        'labels': labels,
        'photos': photos,
        'voice': voice,
        'checklist': checklist.map((c) => c.toMap()).toList(),
        'isChecklist': isChecklist,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
        'updatedAt': nowIso(),
      }
        ..remove('id')
        ..remove('tags');

  bool get isEmpty =>
      title.trim().isEmpty &&
      body.trim().isEmpty &&
      checklist.every((c) => c.title.trim().isEmpty) &&
      photos.isEmpty &&
      voice.isEmpty;

  String get preview {
    if (isChecklist && checklist.isNotEmpty) {
      return checklist.take(6).map((c) => '${c.done ? '☑' : '☐'} ${c.title}').join('\n');
    }
    return body;
  }
}

// ----------------------------------------------------------------- habits

class Habit {
  final String id;
  final Map<String, dynamic> raw;
  String name;
  String emoji;
  int color;
  String kind; // check | count
  int target;
  String unit;
  List<int> days; // 1=Mon..7=Sun; empty = every day
  String remind; // HH:mm or ''
  Map<String, dynamic> history;
  String createdAt;
  bool archived;
  int order;

  Habit({
    this.id = '',
    Map<String, dynamic>? raw,
    this.name = '',
    this.emoji = '✅',
    this.color = 0,
    this.kind = 'check',
    this.target = 1,
    this.unit = '',
    List<int>? days,
    this.remind = '',
    Map<String, dynamic>? history,
    this.createdAt = '',
    this.archived = false,
    this.order = 0,
  })  : raw = raw ?? {},
        days = days ?? [],
        history = history ?? {};

  factory Habit.fromMap(Map<String, dynamic> m) => Habit(
        id: str(m['id']),
        raw: m,
        name: str(m['name']),
        emoji: str(m['emoji']).isEmpty ? '✅' : str(m['emoji']),
        color: toI(m['color']),
        kind: str(m['kind']) == 'count' ? 'count' : 'check',
        target: toI(m['target']) < 1 ? 1 : toI(m['target']),
        unit: str(m['unit']),
        days: (m['days'] is List)
            ? (m['days'] as List).map(toI).where((d) => d >= 1 && d <= 7).toList()
            : [],
        remind: str(m['remind']),
        history: m['history'] is Map ? Map<String, dynamic>.from(m['history']) : {},
        createdAt: str(m['createdAt']),
        archived: toB(m['archived']),
        order: toI(m['order']),
      );

  Map<String, dynamic> toMap() => {
        ...raw,
        'name': name,
        'emoji': emoji,
        'color': color,
        'kind': kind,
        'target': target,
        'unit': unit,
        'days': days,
        'remind': remind,
        'history': history,
        'createdAt': createdAt.isEmpty ? nowIso() : createdAt,
        'archived': archived,
        'order': order,
      }..remove('id');

  bool isScheduled(DateTime d) => days.isEmpty || days.contains(d.weekday);

  int valueOn(DateTime d) {
    final v = history[dayKey(d)];
    if (v == true) return target;
    if (v is num) return v.toInt();
    return 0;
  }

  bool doneOn(DateTime d) => valueOn(d) >= target;

  DateTime? get createdDay => parseDay(createdAt);

  /// Consecutive scheduled days completed. Today only counts once done, but
  /// an unfinished today never breaks the streak.
  int streak([DateTime? ref]) {
    var day = dateOnly(ref ?? DateTime.now());
    var count = 0;
    if (!doneOn(day)) day = addDays(day, -1);
    final start = createdDay ?? DateTime(2000);
    var guard = 0;
    while (guard < 3660 && !day.isBefore(addDays(start, -1))) {
      if (isScheduled(day)) {
        if (doneOn(day)) {
          count++;
        } else {
          break;
        }
      }
      day = addDays(day, -1);
      guard++;
    }
    return count;
  }

  int bestStreak() {
    final keys = history.keys.map(parseDay).whereType<DateTime>().toList()..sort();
    if (keys.isEmpty) return 0;
    var best = 0, cur = 0;
    var day = keys.first;
    final end = todayDate();
    var guard = 0;
    while (!day.isAfter(end) && guard < 3660) {
      if (isScheduled(day)) {
        if (doneOn(day)) {
          cur++;
          if (cur > best) best = cur;
        } else if (!sameDay(day, end)) {
          cur = 0;
        }
      }
      day = addDays(day, 1);
      guard++;
    }
    return best;
  }

  /// Share of scheduled days completed over the last [days] days.
  double rate(int daysBack) {
    var sched = 0, done = 0;
    final t = todayDate();
    final start = createdDay;
    for (var i = 0; i < daysBack; i++) {
      final d = addDays(t, -i);
      if (start != null && d.isBefore(start)) break;
      if (!isScheduled(d)) continue;
      if (i == 0 && !doneOn(d)) continue; // today still open
      sched++;
      if (doneOn(d)) done++;
    }
    return sched == 0 ? 0 : done / sched;
  }

  int totalDone() => history.keys
      .map(parseDay)
      .whereType<DateTime>()
      .where(doneOn)
      .length;
}

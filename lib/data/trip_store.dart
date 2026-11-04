import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// How you're travelling. Stored as a stable key.
class TripMode {
  static const flight = 'flight';
  static const train = 'train';
  static const bus = 'bus';
  static const car = 'car';
  static const other = 'other';
  static const all = [flight, train, bus, car, other];
}

/// One thing to pack.
class PackItem {
  String title;
  bool done;
  PackItem({this.title = '', this.done = false});

  factory PackItem.from(Object? v) {
    if (v is Map) {
      return PackItem(title: str(v['title']), done: toB(v['done']));
    }
    return PackItem(title: str(v));
  }

  Map<String, dynamic> toMap() => {'title': title, 'done': done};
}

/// A journey, with its travel details and packing list.
class Trip {
  final String id;
  final Map<String, dynamic> raw;
  String mode;
  String from;
  String to;
  String depDate; // day key
  String depTime; // HH:mm, may be empty
  String arrDate;
  String arrTime;
  String pnr;
  String operator; // airline / train name / bus operator
  String seat;
  String notes;
  double cost;
  String status; // upcoming | done | cancelled
  List<PackItem> packing;

  Trip({
    this.id = '',
    Map<String, dynamic>? raw,
    this.mode = TripMode.flight,
    this.from = '',
    this.to = '',
    this.depDate = '',
    this.depTime = '',
    this.arrDate = '',
    this.arrTime = '',
    this.pnr = '',
    this.operator = '',
    this.seat = '',
    this.notes = '',
    this.cost = 0,
    this.status = 'upcoming',
    List<PackItem>? packing,
  })  : raw = raw ?? {},
        packing = packing ?? [];

  factory Trip.from(Map<String, dynamic> m) {
    final pack = <PackItem>[];
    final p = m['packing'];
    if (p is List) {
      for (final e in p) {
        final item = PackItem.from(e);
        if (item.title.isNotEmpty) pack.add(item);
      }
    } else if (p is Map) {
      p.forEach((_, v) {
        final item = PackItem.from(v);
        if (item.title.isNotEmpty) pack.add(item);
      });
    }
    // 1.x stored the operator under a per-mode key.
    final mode = TripMode.all.contains(str(m['type'])) ? str(m['type']) : TripMode.flight;
    var op = str(m['operator']);
    if (op.isEmpty) {
      op = str(m['airline']).isNotEmpty ? str(m['airline']) : str(m['trainName']);
    }
    return Trip(
      id: str(m['id']),
      raw: m,
      mode: mode,
      from: str(m['from']),
      to: str(m['to']),
      depDate: str(m['depDate']),
      depTime: str(m['depTime']),
      arrDate: str(m['arrDate']),
      arrTime: str(m['arrTime']),
      pnr: str(m['pnr']),
      operator: op,
      seat: str(m['seat']),
      notes: str(m['notes']),
      cost: toD(m['cost']),
      status: str(m['status']).isEmpty ? 'upcoming' : str(m['status']),
      packing: pack,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': mode,
        'from': from,
        'to': to,
        'depDate': depDate,
        'depTime': depTime,
        'arrDate': arrDate,
        'arrTime': arrTime,
        'pnr': pnr,
        'operator': operator,
        'seat': seat,
        'notes': notes,
        'cost': cost,
        'status': status,
        'packing': packing.map((e) => e.toMap()).toList(),
      };

  DateTime? get departure {
    final d = parseDay(depDate);
    if (d == null) return null;
    final t = parseHm(depTime);
    return t == null ? d : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  DateTime? get arrival {
    final d = parseDay(arrDate);
    if (d == null) return null;
    final t = parseHm(arrTime);
    return t == null ? d : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  String get route => [from, to].where((e) => e.isNotEmpty).join(' → ');

  bool get isCancelled => status == 'cancelled';
  bool get isDone => status == 'done';

  /// Days until departure; negative once it's in the past.
  int? get daysAway {
    final d = parseDay(depDate);
    return d == null ? null : daysBetween(todayDate(), d);
  }

  bool get isUpcoming {
    if (isCancelled || isDone) return false;
    final d = parseDay(arrDate) ?? parseDay(depDate);
    return d == null || !d.isBefore(todayDate());
  }

  int get packed => packing.where((e) => e.done).length;

  double get packProgress => packing.isEmpty ? 0 : packed / packing.length;
}

/// Trips live in the shared workspace, so a family or team plans together.
class TripStore extends LiveStore {
  TripStore() {
    bind();
  }

  final DbService _db = DbService.instance;
  List<Trip> trips = [];

  void bind() {
    cancelAll();
    watch('trips', _db.stream('trips', workspace: true), (List<Map<String, dynamic>> v) {
      trips = v.map(Trip.from).toList()
        ..sort((a, b) {
          final x = a.departure, y = b.departure;
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return x.compareTo(y);
        });
    });
    invalidate();
  }

  List<Trip> get upcoming => trips.where((t) => t.isUpcoming).toList();

  List<Trip> get past => trips.where((t) => !t.isUpcoming).toList().reversed.toList();

  Trip? byId(String id) {
    for (final t in trips) {
      if (t.id == id) return t;
    }
    return null;
  }

  Trip? get next {
    final list = upcoming;
    return list.isEmpty ? null : list.first;
  }

  String save(Trip t) {
    if (t.id.isEmpty) {
      final id = _db.newId('trips', workspace: true);
      _db.set('trips', id, t.toMap(), workspace: true);
      return id;
    }
    _db.set('trips', t.id, t.toMap(), workspace: true);
    return t.id;
  }

  void setStatus(Trip t, String status) {
    t.status = status;
    invalidate();
    _db.update('trips', t.id, {'status': status}, workspace: true);
  }

  void setPacking(Trip t, List<PackItem> items) {
    t.packing
      ..clear()
      ..addAll(items);
    invalidate();
    _db.update('trips', t.id, {'packing': items.map((e) => e.toMap()).toList()}, workspace: true);
  }

  void togglePackItem(Trip t, int index) {
    if (index < 0 || index >= t.packing.length) return;
    final items = List<PackItem>.from(t.packing);
    items[index] = PackItem(title: items[index].title, done: !items[index].done);
    setPacking(t, items);
  }

  Map<String, dynamic> delete(Trip t) {
    final data = Map<String, dynamic>.from(t.raw)..remove('id');
    _db.remove('trips', t.id, workspace: true);
    return data;
  }

  void restore(String id, Map<String, dynamic> data) =>
      _db.set('trips', id, data, workspace: true);
}

/// Starter packing lists, so nobody stares at an empty checklist.
const Map<String, List<String>> kPackingTemplates = {
  'essentials': [
    'pk_tickets', 'pk_id', 'pk_wallet', 'pk_phone', 'pk_charger',
    'pk_powerbank', 'pk_earphones', 'pk_meds', 'pk_water',
  ],
  'clothes': [
    'pk_shirts', 'pk_trousers', 'pk_innerwear', 'pk_socks',
    'pk_jacket', 'pk_nightwear', 'pk_shoes', 'pk_slippers',
  ],
  'toiletries': [
    'pk_toothbrush', 'pk_toothpaste', 'pk_soap', 'pk_shampoo',
    'pk_towel', 'pk_comb', 'pk_sunscreen', 'pk_sanitizer',
  ],
};

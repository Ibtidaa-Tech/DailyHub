import '../services/db_service.dart';
import '../services/geocode_service.dart';
import '../services/location_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Where you were, day by day.
///
/// One row per day, keyed by the date itself:
///
///   whereabouts/{YYYY-MM-DD} = { lat, lng, place, area, label, note, at }
///
/// `place` and `area` are the reverse-geocoded name, resolved once and then
/// stored, so the history reads as place names on every later visit without
/// re-querying anything.
///
/// Deliberately coarse. There is NO background tracking — the app records a
/// fix when you open it and not otherwise, which is also why there is one
/// row per day rather than a trail of points. A location history is the most
/// sensitive thing in this app, so it only ever holds what you would have
/// been able to write down yourself.
///
/// It stays in your own data. Mentors cannot reach it: the database rules
/// grant them the tracker collections and nothing else.
class WhereaboutsStore extends LiveStore {
  WhereaboutsStore() {
    bind();
  }

  final DbService _db = DbService.instance;

  /// dayKey -> row, newest first when listed.
  List<Map<String, dynamic>> days = [];
  Map<String, Map<String, dynamic>> _byDay = {};

  void bind() {
    cancelAll();
    watch('whereabouts', _db.stream('whereabouts'), (List<Map<String, dynamic>> v) {
      days = v.toList()..sort((a, b) => str(b['id']).compareTo(str(a['id'])));
      _byDay = {for (final m in v) str(m['id']): m};
    });
  }

  Map<String, dynamic>? forDay(DateTime day) => _byDay[dayKey(day)];

  bool hasToday() => forDay(todayDate()) != null;

  /// Records a fix for [day], keeping any label or note already written.
  void save(DateTime day,
      {double? lat,
      double? lng,
      String? label,
      String? note,
      String? place,
      String? area}) {
    final id = dayKey(day);
    final existing = _byDay[id];
    _db.set('whereabouts', id, {
      'lat': lat ?? (existing?['lat'] as num?)?.toDouble(),
      'lng': lng ?? (existing?['lng'] as num?)?.toDouble(),
      'place': place ?? str(existing?['place']),
      'area': area ?? str(existing?['area']),
      'label': label ?? str(existing?['label']),
      'note': note ?? str(existing?['note']),
      'day': id,
      'at': nowIso(),
    });
  }

  /// Looks up the name for a fix and writes it back. Runs after the fix is
  /// already saved, so a failed or slow lookup never costs you the location —
  /// you just see coordinates until the next time it resolves.
  Future<void> _nameIt(DateTime day, double lat, double lng) async {
    final found = await GeocodeService.describe(lat, lng);
    if (found == null) return;
    save(day, place: found.short, area: found.full);
  }

  /// The best name available for a row: the one you typed beats the one the
  /// lookup found, which beats raw coordinates.
  static String labelFor(Map<String, dynamic> row) {
    for (final k in ['label', 'place', 'area']) {
      final v = str(row[k]);
      if (v.isNotEmpty) return v;
    }
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return GeocodeService.coords(lat, lng);
    return '';
  }

  /// Fills in a missing name for a day already logged — used by rows saved
  /// before the lookup existed, or saved while offline.
  Future<void> resolveMissing(DateTime day) async {
    final row = forDay(day);
    if (row == null) return;
    if (str(row['place']).isNotEmpty) return;
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    await _nameIt(day, lat, lng);
  }

  void remove(DateTime day) => _db.remove('whereabouts', dayKey(day));

  /// Takes today's fix if there isn't one yet.
  ///
  /// Uses the coarse, never-prompting fix on purpose: opening the app should
  /// not throw a permission dialog at you. Until permission is granted
  /// elsewhere this quietly does nothing, and the screen offers the button.
  Future<bool> captureToday() async {
    if (hasToday()) return false;
    final pos = await LocationService.instance.coarse();
    if (pos == null) return false;
    final day = todayDate();
    save(day, lat: pos.latitude, lng: pos.longitude);
    await _nameIt(day, pos.latitude, pos.longitude);
    return true;
  }

  /// Explicit "log where I am now", which may prompt for permission.
  Future<String?> logNow({DateTime? day}) async {
    final res = await LocationService.instance.current();
    final pos = res.position;
    if (pos == null) return res.error ?? 'Could not get a location fix';
    final d = day ?? todayDate();
    save(d, lat: pos.latitude, lng: pos.longitude);
    await _nameIt(d, pos.latitude, pos.longitude);
    return null;
  }
}

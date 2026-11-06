import '../core/settings.dart';
import '../services/db_service.dart';
import '../services/prayer_times.dart';
import 'models.dart';
import 'store_base.dart';

/// Prayer times for any day, with your corrections layered on top.
///
/// The times are computed from the sun rather than fetched, so this works
/// offline and follows you when you travel. What is stored is only the
/// difference between the calculation and what your mosque actually uses:
///
///   prayerEdits/{YYYY-MM-DD}_{prayer} = { hm: '05:22' }
///
/// One row per prayer per day, because that is the scope you asked for — an
/// edit to Fajr on 6 November changes 6 November and nothing else. A pinned
/// time would quietly go wrong as the season moves; a per-day correction
/// cannot.
class PrayerStore extends LiveStore {
  PrayerStore(this._settings) {
    bind();
  }

  final AppSettings _settings;
  final DbService _db = DbService.instance;

  /// '{dayKey}_{prayer}' -> 'HH:mm'
  Map<String, String> _edits = {};

  void bind() {
    cancelAll();
    watch('prayerEdits', _db.stream('prayerEdits'), (List<Map<String, dynamic>> v) {
      _edits = {
        for (final m in v)
          if (str(m['hm']).isNotEmpty) str(m['id']): str(m['hm']),
      };
    });
  }

  static String editKey(DateTime day, String prayer) => '${dayKey(day)}_$prayer';

  bool get hasLocation => _settings.prayerLat != null && _settings.prayerLng != null;

  double get lat => _settings.prayerLat ?? 0;
  double get lng => _settings.prayerLng ?? 0;

  PrayerMethod get method => PrayerMethod.byId(_settings.prayerMethod);
  String get madhabId => _settings.asrMadhab;

  /// Calculated times for [day], before any corrections. Null until a
  /// location is known — the app never guesses one.
  DailyPrayers? computed(DateTime day) {
    if (!hasLocation) return null;
    return memo('calc:${dayKey(day)}:${_settings.prayerMethod}:$lat:$lng',
        () => PrayerTimes.forDay(day: day, lat: lat, lng: lng, method: method));
  }

  /// Your correction for one prayer on one day, if you made one.
  String? editFor(DateTime day, String prayer) => _edits[editKey(day, prayer)];

  bool isEdited(DateTime day, String prayer) => editFor(day, prayer) != null;

  /// The time to actually use: your correction when there is one, otherwise
  /// the calculation.
  DateTime? timeOf(DateTime day, String prayer, {String? madhab}) {
    final edit = editFor(day, prayer);
    if (edit != null) {
      final hm = parseHm(edit);
      if (hm != null) {
        return DateTime(day.year, day.month, day.day, hm.hour, hm.minute);
      }
    }
    return computed(day)?.of(prayer, madhabId: madhab ?? madhabId);
  }

  /// 'HH:mm' for a prayer on a day, or empty when unknown.
  String hmOf(DateTime day, String prayer, {String? madhab}) {
    final t = timeOf(day, prayer, madhab: madhab);
    return t == null ? '' : hmKey(t.hour, t.minute);
  }

  /// Records a correction for one prayer on one day only.
  void setEdit(DateTime day, String prayer, String hm) {
    final id = editKey(day, prayer);
    _db.set('prayerEdits', id, {
      'hm': hm,
      'day': dayKey(day),
      'prayer': prayer,
      'at': nowIso(),
    });
  }

  /// Drops a correction, so that day goes back to the calculation.
  void clearEdit(DateTime day, String prayer) =>
      _db.remove('prayerEdits', editKey(day, prayer));

  /// Every correction on a day, for showing "edited" markers at a glance.
  int editCountOn(DateTime day) {
    final prefix = '${dayKey(day)}_';
    return _edits.keys.where((k) => k.startsWith(prefix)).length;
  }
}

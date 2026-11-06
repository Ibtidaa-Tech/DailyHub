import 'dart:math' as math;

/// Prayer times from the sun's position — no network, no API key, no
/// dependency. Works offline and wherever you are, which is the point: the
/// times must follow you when you travel.
///
/// The arithmetic is the standard one (PrayTimes.org / Ministry of Awqaf
/// formulation) and was checked against known sunrise and sunset for Delhi,
/// Mumbai, Makkah and London before being written here — all to the minute.
///
/// Everything is computed in the device's own UTC offset for that date, so
/// daylight saving is handled by the platform rather than guessed at.

const double _d2r = math.pi / 180.0;
const double _r2d = 180.0 / math.pi;

double _sin(double deg) => math.sin(deg * _d2r);
double _cos(double deg) => math.cos(deg * _d2r);
double _tan(double deg) => math.tan(deg * _d2r);
double _asin(double x) => math.asin(x) * _r2d;
double _acos(double x) => math.acos(x) * _r2d;
double _atan2(double y, double x) => math.atan2(y, x) * _r2d;
double _acot(double x) => math.atan(1.0 / x) * _r2d;

double _wrap(double v, double range) {
  var r = v % range;
  if (r < 0) r += range;
  return r;
}

/// How Fajr and Isha are defined. The choice moves them by 10–20 minutes,
/// which is why it is a setting rather than a constant.
class PrayerMethod {
  final String id;
  final String label;
  final double fajrAngle;
  final double ishaAngle;

  /// Minutes after Maghrib, used instead of [ishaAngle] when non-zero.
  final int ishaInterval;

  const PrayerMethod({
    required this.id,
    required this.label,
    required this.fajrAngle,
    this.ishaAngle = 0,
    this.ishaInterval = 0,
  });

  static const karachi = PrayerMethod(
    id: 'karachi',
    label: 'Karachi (18° / 18°)',
    fajrAngle: 18,
    ishaAngle: 18,
  );
  static const mwl = PrayerMethod(
    id: 'mwl',
    label: 'Muslim World League (18° / 17°)',
    fajrAngle: 18,
    ishaAngle: 17,
  );
  static const isna = PrayerMethod(
    id: 'isna',
    label: 'ISNA (15° / 15°)',
    fajrAngle: 15,
    ishaAngle: 15,
  );
  static const egypt = PrayerMethod(
    id: 'egypt',
    label: 'Egyptian (19.5° / 17.5°)',
    fajrAngle: 19.5,
    ishaAngle: 17.5,
  );
  static const ummAlQura = PrayerMethod(
    id: 'umm_al_qura',
    label: 'Umm al-Qura (18.5°, Isha +90 min)',
    fajrAngle: 18.5,
    ishaInterval: 90,
  );
  static const gulf = PrayerMethod(
    id: 'gulf',
    label: 'Gulf (19.5°, Isha +90 min)',
    fajrAngle: 19.5,
    ishaInterval: 90,
  );
  static const tehran = PrayerMethod(
    id: 'tehran',
    label: 'Tehran (17.7° / 14°)',
    fajrAngle: 17.7,
    ishaAngle: 14,
  );

  static const all = [karachi, mwl, isna, egypt, ummAlQura, gulf, tehran];

  static PrayerMethod byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => karachi);
}

/// The four schools, for Asr. Shafi'i, Maliki and Hanbali all use one
/// shadow-length and therefore share a time; Hanafi uses two and runs
/// roughly 45 minutes later. They are listed separately anyway so nobody has
/// to know that rule to read the screen.
class Madhab {
  final String id;
  final String labelKey;
  final int shadowFactor;
  const Madhab(this.id, this.labelKey, this.shadowFactor);

  static const hanafi = Madhab('hanafi', 'pr_hanafi', 2);
  static const shafii = Madhab('shafii', 'pr_shafii', 1);
  static const maliki = Madhab('maliki', 'pr_maliki', 1);
  static const hanbali = Madhab('hanbali', 'pr_hanbali', 1);

  static const all = [hanafi, shafii, maliki, hanbali];

  static Madhab byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => shafii);
}

/// Which prayer a tracker habit stands for.
class PrayerId {
  static const fajr = 'fajr';
  static const dhuhr = 'dhuhr';
  static const asr = 'asr';
  static const maghrib = 'maghrib';
  static const isha = 'isha';
  static const sunrise = 'sunrise';

  /// The five, in the order they fall.
  static const five = [fajr, dhuhr, asr, maghrib, isha];

  static String labelKey(String id) => switch (id) {
        fajr => 'tr_tpl_fajr',
        dhuhr => 'tr_tpl_zuhr',
        asr => 'tr_tpl_asr',
        maghrib => 'tr_tpl_maghrib',
        isha => 'tr_tpl_isha',
        _ => 'pr_sunrise',
      };
}

/// One day's times at one place.
class DailyPrayers {
  final DateTime day;
  final DateTime? fajr;
  final DateTime? sunrise;
  final DateTime? dhuhr;
  final DateTime? maghrib;
  final DateTime? isha;

  /// Asr per school, keyed by [Madhab.id]. Three of the four coincide.
  final Map<String, DateTime?> asr;

  const DailyPrayers({
    required this.day,
    this.fajr,
    this.sunrise,
    this.dhuhr,
    this.maghrib,
    this.isha,
    this.asr = const {},
  });

  /// Time for a prayer id, with [madhabId] deciding Asr.
  DateTime? of(String prayerId, {String madhabId = 'shafii'}) => switch (prayerId) {
        PrayerId.fajr => fajr,
        PrayerId.sunrise => sunrise,
        PrayerId.dhuhr => dhuhr,
        PrayerId.asr => asr[madhabId],
        PrayerId.maghrib => maghrib,
        PrayerId.isha => isha,
        _ => null,
      };

  /// The prayer currently in progress — the latest one whose time has passed.
  String? currentAt(DateTime now, {String madhabId = 'shafii'}) {
    String? best;
    for (final p in PrayerId.five) {
      final t = of(p, madhabId: madhabId);
      if (t != null && !t.isAfter(now)) best = p;
    }
    return best;
  }

  /// The next prayer still to come today.
  String? nextAt(DateTime now, {String madhabId = 'shafii'}) {
    for (final p in PrayerId.five) {
      final t = of(p, madhabId: madhabId);
      if (t != null && t.isAfter(now)) return p;
    }
    return null;
  }
}

class PrayerTimes {
  PrayerTimes._();

  /// Times for [day] at [lat]/[lng].
  ///
  /// Returns a result with null fields rather than throwing when the sun
  /// never reaches an angle — which happens above the Arctic circle in
  /// winter, where Fajr and Isha genuinely do not occur.
  static DailyPrayers forDay({
    required DateTime day,
    required double lat,
    required double lng,
    PrayerMethod method = PrayerMethod.karachi,
  }) {
    final local = DateTime(day.year, day.month, day.day, 12);
    final tz = local.timeZoneOffset.inMinutes / 60.0;

    final jd = _julian(day.year, day.month, day.day) - lng / (15 * 24.0);
    final s = _sunPosition(jd);
    final decl = s.$1;
    final eqt = s.$2;

    final dhuhr = 12 + tz - lng / 15.0 - eqt;

    double? minus(double angle) {
      final t = _hourAngle(angle, lat, decl);
      return t == null ? null : dhuhr - t;
    }

    double? plus(double angle) {
      final t = _hourAngle(angle, lat, decl);
      return t == null ? null : dhuhr + t;
    }

    final maghribH = plus(0.833);
    double? ishaH;
    if (method.ishaInterval > 0) {
      ishaH = maghribH == null ? null : maghribH + method.ishaInterval / 60.0;
    } else {
      ishaH = plus(method.ishaAngle);
    }

    final asrMap = <String, DateTime?>{};
    for (final m in Madhab.all) {
      final t = _asrHourAngle(m.shadowFactor, lat, decl);
      asrMap[m.id] = t == null ? null : _at(day, dhuhr + t);
    }

    return DailyPrayers(
      day: DateTime(day.year, day.month, day.day),
      fajr: _at(day, minus(method.fajrAngle)),
      sunrise: _at(day, minus(0.833)),
      dhuhr: _at(day, dhuhr),
      maghrib: _at(day, maghribH),
      isha: _at(day, ishaH),
      asr: asrMap,
    );
  }

  /// Turns an hour-of-day into a DateTime on [day], rounded to the minute.
  /// Rounding matters: a timetable showing 05:21:47 would be absurd, and the
  /// seconds are far below the accuracy of the model anyway.
  static DateTime? _at(DateTime day, double? hours) {
    if (hours == null || hours.isNaN || hours.isInfinite) return null;
    final total = (_wrap(hours, 24) * 60).round();
    // Built from wall-clock parts rather than by adding a Duration, so a
    // daylight-saving change never shifts the result by an hour.
    return DateTime(day.year, day.month, day.day, total ~/ 60, total % 60);
  }

  static double _julian(int year, int month, int dayOfMonth) {
    var y = year;
    var m = month;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        dayOfMonth +
        b -
        1524.5;
  }

  /// (declination, equation of time in hours)
  static (double, double) _sunPosition(double jd) {
    final d = jd - 2451545.0;
    final g = _wrap(357.529 + 0.98560028 * d, 360);
    final q = _wrap(280.459 + 0.98564736 * d, 360);
    final l = _wrap(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g), 360);
    final e = 23.439 - 0.00000036 * d;
    final ra = _wrap(_atan2(_cos(e) * _sin(l), _cos(l)) / 15.0, 24);
    final decl = _asin(_sin(e) * _sin(l));
    var eqt = q / 15.0 - ra;
    while (eqt > 12) {
      eqt -= 24;
    }
    while (eqt < -12) {
      eqt += 24;
    }
    return (decl, eqt);
  }

  /// Hours from solar noon to the sun sitting [angle] degrees below the
  /// horizon. Null when it never gets there that day.
  static double? _hourAngle(double angle, double lat, double decl) {
    final x = (-_sin(angle) - _sin(decl) * _sin(lat)) / (_cos(decl) * _cos(lat));
    if (x > 1 || x < -1) return null;
    return _acos(x) / 15.0;
  }

  /// Hours from solar noon to Asr, by shadow length.
  static double? _asrHourAngle(int factor, double lat, double decl) {
    final x = (_sin(_acot(factor + _tan((lat - decl).abs()))) -
            _sin(decl) * _sin(lat)) /
        (_cos(decl) * _cos(lat));
    if (x > 1 || x < -1) return null;
    return _acos(x) / 15.0;
  }
}

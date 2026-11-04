import '../core/settings.dart';
import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Read-only view of the other modules (meetings, classes, assignments,
/// trips, deliveries, countdowns) so Home, Plan and the calendar can show
/// everything on one timeline. Only enabled modules are subscribed.
class ExtrasStore extends LiveStore {
  ExtrasStore(this.settings) {
    settings.addListener(_onSettings);
    bind();
  }

  final AppSettings settings;
  final DbService _db = DbService.instance;
  String _sig = '';

  List<Map<String, dynamic>> meetings = [];
  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> assignments = [];
  List<Map<String, dynamic>> trips = [];
  List<Map<String, dynamic>> packages = [];
  List<Map<String, dynamic>> countdowns = [];

  String _signature() => [
        settings.isOn('work'),
        settings.isOn('student'),
        settings.isOn('trips'),
        settings.isOn('packages'),
        settings.isOn('countdowns'),
        _db.wsUid,
      ].join('|');

  void _onSettings() {
    if (_signature() != _sig) bind();
  }

  void bind() {
    cancelAll();
    _sig = _signature();
    meetings = [];
    classes = [];
    assignments = [];
    trips = [];
    packages = [];
    countdowns = [];
    if (settings.isOn('work')) {
      watch('meetings', _db.stream('meetings'), (List<Map<String, dynamic>> v) => meetings = v);
    }
    if (settings.isOn('student')) {
      watch('timetable', _db.stream('timetable'), (List<Map<String, dynamic>> v) => classes = v);
      watch('assignments', _db.stream('assignments'), (List<Map<String, dynamic>> v) => assignments = v);
    }
    if (settings.isOn('trips')) {
      watch('trips', _db.stream('trips', workspace: true), (List<Map<String, dynamic>> v) => trips = v);
    }
    if (settings.isOn('packages')) {
      watch('packages', _db.stream('packages'), (List<Map<String, dynamic>> v) => packages = v);
    }
    if (settings.isOn('countdowns')) {
      watch('countdowns', _db.stream('countdowns'), (List<Map<String, dynamic>> v) => countdowns = v);
    }
    invalidate();
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  List<Map<String, dynamic>> classesOn(DateTime day) {
    final name = _dayNames[day.weekday - 1];
    return classes.where((c) => c['day'] == name).toList()
      ..sort((a, b) => str(a['start']).compareTo(str(b['start'])));
  }

  List<Map<String, dynamic>> meetingsOn(DateTime day) => meetings.where((m) {
        final d = DateTime.tryParse(str(m['at']));
        return d != null && sameDay(d, day);
      }).toList();

  List<Map<String, dynamic>> assignmentsDue(DateTime day) => assignments.where((a) {
        final d = parseDay(str(a['due']));
        return d != null && sameDay(d, day) && a['done'] != true;
      }).toList();

  List<Map<String, dynamic>> tripsOn(DateTime day) => trips.where((t) {
        final d = parseDay(str(t['depDate']));
        return d != null && sameDay(d, day) && (t['status'] ?? 'upcoming') == 'upcoming';
      }).toList();

  List<Map<String, dynamic>> packagesOn(DateTime day) => packages.where((p) {
        final d = parseDay(str(p['expected']));
        return d != null && sameDay(d, day) && p['delivered'] != true;
      }).toList();

  List<Map<String, dynamic>> countdownsOn(DateTime day) => countdowns.where((c) {
        final d = parseDay(str(c['date']));
        return d != null && sameDay(d, day);
      }).toList();

  /// Upcoming trips and countdowns within [days], soonest first.
  List<(DateTime, Map<String, dynamic>, String)> upcomingHighlights(int days) {
    final t0 = todayDate();
    final end = addDays(t0, days);
    final out = <(DateTime, Map<String, dynamic>, String)>[];
    for (final t in trips) {
      final d = parseDay(str(t['depDate']));
      if (d == null || d.isBefore(t0) || d.isAfter(end)) continue;
      if ((t['status'] ?? 'upcoming') != 'upcoming') continue;
      out.add((d, t, 'trip'));
    }
    for (final c in countdowns) {
      final d = parseDay(str(c['date']));
      if (d == null || d.isBefore(t0) || d.isAfter(end)) continue;
      out.add((d, c, 'countdown'));
    }
    for (final a in assignments) {
      final d = parseDay(str(a['due']));
      if (d == null || d.isBefore(t0) || d.isAfter(end) || a['done'] == true) continue;
      out.add((d, a, 'assignment'));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    super.dispose();
  }
}

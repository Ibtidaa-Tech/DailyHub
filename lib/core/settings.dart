import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'currencies.dart';

/// Every user preference in one place.
///
/// Stored locally (instant startup, works offline). The account-level
/// choices — modules, home layout, currency, week start, onboarding — are
/// also mirrored to Firebase under users/{uid}/prefs so a second phone or
/// the web app opens already set up. See [AppSettings.applyRemote].
class AppSettings extends ChangeNotifier {
  static const _key = 'dh_settings_v2';

  // Appearance
  ThemeMode themeMode = ThemeMode.system;
  String accent = 'indigo';
  String lang = 'en';

  // Account-level (synced)
  String currency = 'INR';
  Set<String> modules = {...ModuleDefaults.core};
  /// Which batch of shipped modules this account has already been shown.
  /// Without it an upgrade is invisible: the saved module list always beat the
  /// new defaults, so a module added in an update never appeared in the Hub.
  int moduleRev = ModuleDefaults.rev;
  List<String> homeOrder = List.of(HomeSections.defaults);
  Set<String> homeHidden = {};
  int weekStart = DateTime.monday;
  /// Attendance you're required to keep, as a percentage. 75 in most of India,
  /// but some colleges set 80 or 85, so it's adjustable.
  int attendanceTarget = 75;
  bool onboarded = false;

  // Device-level
  bool morningBriefing = true;
  String morningTime = '08:00';
  bool eveningReview = true;
  String eveningTime = '21:00';
  bool appLock = false;
  bool weatherUseLocation = true;
  String weatherCity = '';
  double? weatherLat;
  double? weatherLng;
  String notesLayout = 'grid';
  String defaultAccount = '';
  bool notifMigrated = false;
  bool use24h = false;

  // Prayer times. Location is kept separately from the weather one: weather
  // is happy with a coarse fix, prayer times move by a minute per 15 km of
  // longitude, and the two get refreshed at different moments.
  String prayerMethod = 'karachi';
  String asrMadhab = 'shafii';
  double? prayerLat;
  double? prayerLng;
  String prayerPlace = '';

  /// Re-read the device's position each time prayer times are needed, so
  /// they follow you when you travel. Off pins them to [prayerLat]/[prayerLng].
  bool prayerFollowLocation = true;

  /// Called whenever a synced value changes; wired to Firebase in app.dart.
  void Function(Map<String, dynamic> synced)? onSyncedChange;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) {
        currency = Currencies.detect();
        final sys = WidgetsBinding.instance.platformDispatcher.locale;
        if (sys.languageCode == 'hi') lang = 'hi';
      } else {
        _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      currency = Currencies.detect();
    }
    Money.current = Currencies.byCode(currency);
    notifyListeners();
  }

  Timer? _saveDebounce;
  void _save({bool synced = false}) {
    Money.current = Currencies.byCode(currency);
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, jsonEncode(_toJson()));
      } catch (_) {}
    });
    if (synced) onSyncedChange?.call(syncedJson());
  }

  Map<String, dynamic> syncedJson() => {
        'currency': currency,
        'modules': modules.toList(),
        'moduleRev': moduleRev,
        'homeOrder': homeOrder,
        'homeHidden': homeHidden.toList(),
        'weekStart': weekStart,
        'attendanceTarget': attendanceTarget,
        'onboarded': onboarded,
      };

  /// Merge account-level prefs pulled from Firebase.
  void applyRemote(Map<String, dynamic>? r) {
    if (r == null) return;
    var changed = false;
    if (r['currency'] is String && r['currency'] != currency) {
      currency = r['currency'];
      changed = true;
    }
    if (r['modules'] is List) {
      final m = (r['modules'] as List).map((e) => '$e').toSet();
      if (m.isNotEmpty) {
        modules = {...m, ...ModuleDefaults.alwaysOn};
        if (_migrateModules(r['moduleRev'] is int ? r['moduleRev'] as int : 0)) {
          onSyncedChange?.call(syncedJson());
        }
        changed = true;
      }
    }
    if (r['homeOrder'] is List) {
      final o = (r['homeOrder'] as List).map((e) => '$e').toList();
      homeOrder = HomeSections.normalize(o);
      changed = true;
    }
    if (r['homeHidden'] is List) {
      homeHidden = (r['homeHidden'] as List).map((e) => '$e').toSet();
      changed = true;
    }
    if (r['weekStart'] is int) {
      weekStart = r['weekStart'];
      changed = true;
    }
    if (r['attendanceTarget'] is int) {
      attendanceTarget = r['attendanceTarget'];
      changed = true;
    }
    if (r['onboarded'] == true && !onboarded) {
      onboarded = true;
      changed = true;
    }
    if (changed) _save();
  }

  Map<String, dynamic> _toJson() => {
        ...syncedJson(),
        'themeMode': themeMode.name,
        'accent': accent,
        'lang': lang,
        'morningBriefing': morningBriefing,
        'morningTime': morningTime,
        'eveningReview': eveningReview,
        'eveningTime': eveningTime,
        'appLock': appLock,
        'weatherUseLocation': weatherUseLocation,
        'weatherCity': weatherCity,
        'weatherLat': weatherLat,
        'weatherLng': weatherLng,
        'notesLayout': notesLayout,
        'defaultAccount': defaultAccount,
        'notifMigrated': notifMigrated,
        'use24h': use24h,
        'prayerMethod': prayerMethod,
        'asrMadhab': asrMadhab,
        'prayerLat': prayerLat,
        'prayerLng': prayerLng,
        'prayerPlace': prayerPlace,
        'prayerFollowLocation': prayerFollowLocation,
      };

  void _fromJson(Map<String, dynamic> j) {
    themeMode = ThemeMode.values.firstWhere((m) => m.name == j['themeMode'],
        orElse: () => ThemeMode.system);
    accent = j['accent'] ?? accent;
    lang = j['lang'] ?? lang;
    currency = j['currency'] ?? Currencies.detect();
    if (j['modules'] is List) {
      modules = {...(j['modules'] as List).map((e) => '$e'), ...ModuleDefaults.alwaysOn};
      // A stored list with no revision is from a build before revisions
      // existed, so start the migration from zero.
      _migrateModules(j['moduleRev'] is int ? j['moduleRev'] as int : 0);
    }
    if (j['homeOrder'] is List) {
      homeOrder = HomeSections.normalize((j['homeOrder'] as List).map((e) => '$e').toList());
    }
    if (j['homeHidden'] is List) {
      homeHidden = (j['homeHidden'] as List).map((e) => '$e').toSet();
    }
    weekStart = j['weekStart'] is int ? j['weekStart'] : weekStart;
    attendanceTarget = j['attendanceTarget'] is int ? j['attendanceTarget'] : attendanceTarget;
    onboarded = j['onboarded'] == true;
    morningBriefing = j['morningBriefing'] ?? morningBriefing;
    morningTime = j['morningTime'] ?? morningTime;
    eveningReview = j['eveningReview'] ?? eveningReview;
    eveningTime = j['eveningTime'] ?? eveningTime;
    appLock = j['appLock'] ?? false;
    weatherUseLocation = j['weatherUseLocation'] ?? true;
    weatherCity = j['weatherCity'] ?? '';
    weatherLat = (j['weatherLat'] as num?)?.toDouble();
    weatherLng = (j['weatherLng'] as num?)?.toDouble();
    notesLayout = j['notesLayout'] ?? 'grid';
    defaultAccount = j['defaultAccount'] ?? '';
    notifMigrated = j['notifMigrated'] == true;
    use24h = j['use24h'] == true;
    prayerMethod = j['prayerMethod'] ?? 'karachi';
    asrMadhab = j['asrMadhab'] ?? 'shafii';
    prayerLat = (j['prayerLat'] as num?)?.toDouble();
    prayerLng = (j['prayerLng'] as num?)?.toDouble();
    prayerPlace = j['prayerPlace'] ?? '';
    prayerFollowLocation = j['prayerFollowLocation'] != false;
  }

  // ------------------------------------------------------------ setters
  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _save();
  }

  void setAccent(String id) {
    accent = id;
    _save();
  }

  void setLang(String l) {
    lang = l;
    _save();
  }

  void setCurrency(String code) {
    currency = code;
    _save(synced: true);
  }

  bool isOn(String module) => modules.contains(module) || ModuleDefaults.alwaysOn.contains(module);

  void setModule(String id, bool on) {
    if (ModuleDefaults.alwaysOn.contains(id)) return;
    on ? modules.add(id) : modules.remove(id);
    modules = {...modules};
    _save(synced: true);
  }

  void setModules(Set<String> ids) {
    modules = {...ids, ...ModuleDefaults.alwaysOn};
    _save(synced: true);
  }

  void setHomeOrder(List<String> order) {
    homeOrder = HomeSections.normalize(order);
    _save(synced: true);
  }

  void setHomeVisible(String id, bool visible) {
    visible ? homeHidden.remove(id) : homeHidden.add(id);
    homeHidden = {...homeHidden};
    _save(synced: true);
  }

  void setWeekStart(int d) {
    weekStart = d;
    _save(synced: true);
  }

  void setAttendanceTarget(int pct) {
    attendanceTarget = pct.clamp(50, 100);
    _save(synced: true);
  }

  void setOnboarded(bool v) {
    onboarded = v;
    _save(synced: true);
  }

  void setBriefing({bool? morning, String? mTime, bool? evening, String? eTime}) {
    if (morning != null) morningBriefing = morning;
    if (mTime != null) morningTime = mTime;
    if (evening != null) eveningReview = evening;
    if (eTime != null) eveningTime = eTime;
    _save();
  }

  void setAppLock(bool v) {
    appLock = v;
    _save();
  }

  void setWeather({bool? useLocation, String? city, double? lat, double? lng}) {
    if (useLocation != null) weatherUseLocation = useLocation;
    if (city != null) weatherCity = city;
    if (lat != null) weatherLat = lat;
    if (lng != null) weatherLng = lng;
    _save();
  }

  void setNotesLayout(String l) {
    notesLayout = l;
    _save();
  }

  void setDefaultAccount(String id) {
    defaultAccount = id;
    _save();
  }

  void setUse24h(bool v) {
    use24h = v;
    _save();
  }

  void setPrayerMethod(String id) {
    prayerMethod = id;
    _save();
  }

  void setAsrMadhab(String id) {
    asrMadhab = id;
    _save();
  }

  void setPrayerFollowLocation(bool v) {
    prayerFollowLocation = v;
    _save();
  }

  void setPrayerLocation(double lat, double lng, {String place = ''}) {
    prayerLat = lat;
    prayerLng = lng;
    if (place.isNotEmpty) prayerPlace = place;
    _save();
  }

  void markNotifMigrated() {
    notifMigrated = true;
    _save();
  }

  /// Switch on the modules shipped since this account last saw the defaults.
  /// Only ever adds: a module the user deliberately switched off after seeing
  /// it stays off, because the revision is bumped and saved either way.
  bool _migrateModules(int storedRev) {
    if (storedRev >= ModuleDefaults.rev) {
      moduleRev = ModuleDefaults.rev;
      return false;
    }
    for (var r = storedRev + 1; r <= ModuleDefaults.rev; r++) {
      final add = ModuleDefaults.addedAtRev[r];
      if (add != null) modules.addAll(add);
    }
    moduleRev = ModuleDefaults.rev;
    return true;
  }

  /// Local reset on sign-out so the next account starts clean.
  void resetAccountState() {
    onboarded = false;
    moduleRev = ModuleDefaults.rev;
    modules = {...ModuleDefaults.core};
    homeOrder = List.of(HomeSections.defaults);
    homeHidden = {};
    defaultAccount = '';
    _save();
  }
}

class ModuleDefaults {
  /// Can't be switched off — the app's backbone.
  static const Set<String> alwaysOn = {'tasks', 'settings'};

  /// On for everyone after onboarding.
  static const Set<String> core = {
    'tasks', 'reminders', 'calendar', 'notes', 'habits', 'money',
    'tracker', 'prayer', 'whereabouts', 'settings',
  };

  /// Bump this whenever a module is added that existing accounts should get,
  /// and list the new ids under the matching revision below.
  static const int rev = 2;

  static const Map<int, Set<String>> addedAtRev = {
    1: {'tracker'},
    2: {'prayer', 'whereabouts'},
  };
}

class HomeSections {
  static const String greeting = 'greeting';
  static const String capture = 'capture';
  static const String agenda = 'agenda';
  static const String habits = 'habits';
  static const String money = 'money';
  static const String upcoming = 'upcoming';

  static const List<String> defaults = [capture, agenda, habits, money, upcoming];

  static List<String> normalize(List<String> order) {
    final out = order.where(defaults.contains).toList();
    for (final d in defaults) {
      if (!out.contains(d)) out.add(d);
    }
    return out;
  }
}

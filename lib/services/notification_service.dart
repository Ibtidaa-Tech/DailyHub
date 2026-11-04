import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/localization.dart';

/// Channel ids.
class NotifChannel {
  static const reminders = 'dh_reminders';
  static const briefing = 'dh_briefing';
  static const habits = 'dh_habits';
  static const tracker = 'dh_tracker';
}

/// Stable 31-bit id from a string key (FNV-1a). Unlike String.hashCode this is
/// identical across app versions, so an alarm set by an older build can
/// always be cancelled by a newer one.
int notifIdFor(String key) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(key)) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7fffffff;
}

/// Runs in a background isolate when "Snooze" is tapped on a notification.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) {
  NotificationService.handleSnooze(r);
}

/// Real OS notifications that fire even when the app is closed (Android/iOS).
/// Every method is a no-op on web.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _exactAllowed = true;

  bool get supported => !kIsWeb;

  final StreamController<NotificationResponse> _taps =
      StreamController<NotificationResponse>.broadcast();

  /// Taps and action buttons (Done / Open) while the app runs.
  Stream<NotificationResponse> get taps => _taps.stream;

  /// The notification that cold-started the app, if any.
  NotificationResponse? launchResponse;

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone));
    } catch (_) {
      tz.setLocalLocation(_guessLocation());
    }

    const android = AndroidInitializationSettings('@drawable/ic_stat_dailyhub');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (r) {
          if (r.actionId == 'snooze') {
            handleSnooze(r);
          } else {
            _taps.add(r);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        launchResponse = launch?.notificationResponse;
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  static tz.Location _guessLocation() {
    final offset = DateTime.now().timeZoneOffset;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (tz.TZDateTime.now(loc).timeZoneOffset == offset) return loc;
    }
    return tz.UTC;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Ask for notification permission (Android 13+, iOS). Returns whether granted.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    if (!_ready) await init();
    bool granted = true;
    try {
      final a = _android;
      if (a != null) {
        granted = await a.requestNotificationsPermission() ?? true;
        final exact = await a.canScheduleExactNotifications() ?? true;
        if (!exact) {
          await a.requestExactAlarmsPermission();
        }
        _exactAllowed = await a.canScheduleExactNotifications() ?? true;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        granted = await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
    return granted;
  }

  Future<bool> areEnabled() async {
    if (kIsWeb) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Language for notification buttons and channel names (set by the planner).
  static String lang = 'en';

  static NotificationDetails details(String channel, {bool actions = false, String? body}) {
    String t(String k) => AppStrings.of(lang, k);
    final name = switch (channel) {
      NotifChannel.briefing => t('ch_briefing'),
      NotifChannel.habits => t('ch_habits'),
      NotifChannel.tracker => t('ch_tracker'),
      _ => t('ch_reminders'),
    };
    final desc = switch (channel) {
      NotifChannel.briefing => t('ch_briefing_desc'),
      NotifChannel.habits => t('ch_habits_desc'),
      NotifChannel.tracker => t('ch_tracker_desc'),
      _ => t('ch_reminders_desc'),
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        name,
        channelDescription: desc,
        importance: channel == NotifChannel.briefing ? Importance.defaultImportance : Importance.max,
        priority: channel == NotifChannel.briefing ? Priority.defaultPriority : Priority.high,
        icon: 'ic_stat_dailyhub',
        color: const Color(0xFF4F46E5),
        styleInformation: body == null || body.length < 40 ? null : BigTextStyleInformation(body),
        category: channel == NotifChannel.reminders ? AndroidNotificationCategory.reminder : null,
        actions: actions
            ? <AndroidNotificationAction>[
                AndroidNotificationAction('snooze', t('notif_snooze')),
                AndroidNotificationAction('done', t('notif_done'), showsUserInterface: true),
              ]
            : null,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  Future<void> _zoned({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required NotificationDetails details,
    String? payload,
    DateTimeComponents? match,
  }) async {
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          at,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          matchDateTimeComponents: match,
        );
    try {
      await go(_exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (e) {
      // Android 14+ without the exact-alarm grant: fall back to inexact.
      _exactAllowed = false;
      try {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e2) {
        debugPrint('schedule failed: $e2');
      }
    }
  }

  /// One-shot notification at [when].
  Future<void> scheduleAt({
    required String key,
    required String title,
    required String body,
    required DateTime when,
    String channel = NotifChannel.reminders,
    bool actions = false,
    String? payload,
  }) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    if (!_ready || when.isBefore(DateTime.now())) return;
    await _zoned(
      id: notifIdFor(key),
      title: title,
      body: body,
      at: tz.TZDateTime.from(when, tz.local),
      details: details(channel, actions: actions, body: body),
      payload: payload ?? jsonEncode({'k': key, 'ti': title, 'b': body, 'c': channel}),
    );
  }

  /// Repeating notification using the OS's own recurrence, so it keeps firing
  /// without the app being opened. [match] decides the repeat period.
  Future<void> scheduleRepeating({
    required String key,
    required String title,
    required String body,
    required DateTime first,
    required DateTimeComponents match,
    String channel = NotifChannel.reminders,
    bool actions = false,
    String? payload,
  }) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    if (!_ready) return;
    await _zoned(
      id: notifIdFor(key),
      title: title,
      body: body,
      at: tz.TZDateTime.from(first, tz.local),
      details: details(channel, actions: actions, body: body),
      payload: payload ?? jsonEncode({'k': key, 'ti': title, 'b': body, 'c': channel}),
      match: match,
    );
  }

  /// Legacy helper kept for older screens (trips, meetings, packages…).
  Future<void> scheduleRecurring({
    required String key,
    required String title,
    required String body,
    required DateTime when,
    required String repeat,
  }) async {
    if (repeat == 'daily') {
      return scheduleRepeating(key: key, title: title, body: body, first: when, match: DateTimeComponents.time);
    }
    if (repeat == 'weekly') {
      return scheduleRepeating(key: key, title: title, body: body, first: when, match: DateTimeComponents.dayOfWeekAndTime);
    }
    return scheduleAt(key: key, title: title, body: body, when: when);
  }

  Future<void> cancel(String key) => cancelId(notifIdFor(key));

  Future<void> cancelId(int id) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> showNow(String title, String body, {String channel = NotifChannel.reminders}) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    try {
      await _plugin.show(DateTime.now().millisecondsSinceEpoch & 0x7fffffff, title, body,
          details(channel, body: body));
    } catch (_) {}
  }

  /// Re-posts a notification 10 minutes later. Works in a background isolate:
  /// it only needs the plugin and UTC time, not Firebase.
  static Future<void> handleSnooze(NotificationResponse r) async {
    try {
      final p = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
      tzdata.initializeTimeZones();
      final plugin = FlutterLocalNotificationsPlugin();
      final at = tz.TZDateTime.now(tz.UTC).add(const Duration(minutes: 10));
      final title = (p['ti'] ?? 'Reminder').toString();
      final body = (p['b'] ?? '').toString();
      final key = '${p['k'] ?? 'snooze'}_snz';
      Future<void> go(AndroidScheduleMode m) => plugin.zonedSchedule(
            notifIdFor(key),
            title,
            body,
            at,
            details(NotifChannel.reminders, actions: true, body: body),
            androidScheduleMode: m,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: jsonEncode({...p, 'k': key}),
          );
      try {
        await go(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    } catch (e) {
      debugPrint('Snooze failed: $e');
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/currencies.dart';
import '../core/localization.dart';
import '../data/agenda.dart';
import '../data/extras_store.dart';
import '../data/life_store.dart';
import '../data/models.dart';
import '../data/money_store.dart';
import '../data/plan_store.dart';

/// Feeds the Android home-screen widget.
///
/// Everything the widget shows is written into the same SharedPreferences file
/// Flutter already uses, so the native side can read it without a plugin and
/// without starting a Flutter engine. A tiny method channel then nudges the
/// widget to redraw; if that fails (no widget on the home screen yet) it's a
/// no-op, and Android's own update interval catches up later.
class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  static const _channel = MethodChannel('com.khurram.dailyhub/widget');

  /// Keys the native provider reads. Keep in sync with DailyHubWidgetProvider.
  static const kDate = 'widget_date';
  static const kItems = 'widget_items';
  static const kOpen = 'widget_open';
  static const kDone = 'widget_done';
  static const kMoney = 'widget_money';
  static const kHabits = 'widget_habits';
  static const kUpdated = 'widget_updated';

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String _lastPayload = '';

  /// Writes today's summary. Cheap to call often — it only touches disk and
  /// pokes the widget when something actually changed.
  Future<void> push({
    required String lang,
    required PlanStore plan,
    MoneyStore? money,
    HabitsStore? habits,
    ExtrasStore? extras,
    bool moneyOn = true,
    bool habitsOn = true,
  }) async {
    if (!supported) return;
    try {
      final today = todayDate();
      final agenda = Agenda.forDay(today, plan: plan, money: money, extras: extras, includeDone: false);
      // Joined by hand rather than via setStringList: the native side reads
      // this file directly, and the list encoding shared_preferences uses has
      // changed between versions. A plain delimited string is unambiguous.
      final items = <String>[];
      for (final a in agenda.take(4)) {
        final time = a.time == null ? '' : hmKey(a.time!.hour, a.time!.minute);
        items.add('$time\u0001${a.title.replaceAll(RegExp(r'[\u0001\u0002]'), ' ')}');
      }
      final itemsLine = items.join('\u0002');

      final open = plan.today.where((t) => t.isOpen).length + plan.overdue.length;
      final done = plan.completedToday.length;

      var moneyLine = '';
      if (moneyOn && money != null) {
        final spent = money.rangeTotals(today, today).expense;
        moneyLine = Money.format(spent);
      }

      var habitLine = '';
      if (habitsOn && habits != null) {
        final (hDone, hTotal) = habits.progressOn(today);
        if (hTotal > 0) habitLine = '$hDone/$hTotal';
      }

      final payload = jsonEncode({
        kDate: AppStrings.of(lang, 'today'),
        kItems: itemsLine,
        kOpen: open,
        kDone: done,
        kMoney: moneyLine,
        kHabits: habitLine,
      });
      if (payload == _lastPayload) return;
      _lastPayload = payload;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDate, AppStrings.of(lang, 'today'));
      await prefs.setString(kItems, itemsLine);
      await prefs.setString(kOpen, '$open');
      await prefs.setString(kDone, '$done');
      await prefs.setString(kMoney, moneyLine);
      await prefs.setString(kHabits, habitLine);
      await prefs.setString(kUpdated, DateTime.now().toIso8601String());
      // Labels, so the widget stays in the user's language without a Flutter engine.
      await prefs.setString('widget_l_left', AppStrings.of(lang, 'widget_left'));
      await prefs.setString('widget_l_done', AppStrings.of(lang, 'done'));
      await prefs.setString('widget_l_spent', AppStrings.of(lang, 'spent'));
      await prefs.setString('widget_l_habits', AppStrings.of(lang, 'm_habits'));
      await prefs.setString('widget_l_empty', AppStrings.of(lang, 'widget_all_clear'));

      await _channel.invokeMethod<void>('refresh');
    } catch (_) {
      // A home screen with no widget on it, or a platform that has none:
      // nothing here is important enough to surface to the user.
    }
  }

  /// Wipes the widget when the account signs out.
  Future<void> clear() async {
    if (!supported) return;
    try {
      _lastPayload = '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kItems, '');
      await prefs.setString(kOpen, '0');
      await prefs.setString(kDone, '0');
      await prefs.setString(kMoney, '');
      await prefs.setString(kHabits, '');
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }
}

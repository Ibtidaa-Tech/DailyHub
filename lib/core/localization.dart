import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/strings_common.dart';
import '../l10n/strings_money.dart';
import '../l10n/strings_plan.dart';
import '../l10n/strings_life.dart';
import '../l10n/strings_settings.dart';
import '../l10n/strings_student.dart';
import '../l10n/strings_home.dart';
import '../l10n/strings_tracker.dart';
import '../l10n/strings_travel.dart';

/// English + Hindi strings. Each key maps to [english, hindi].
/// Use `context.t('key')` or `context.tr('key', {'n': '3'})`.
class AppStrings {
  static final Map<String, List<String>> _all = {
    ...stringsCommon,
    ...stringsPlan,
    ...stringsMoney,
    ...stringsLife,
    ...stringsSettings,
    ...stringsStudent,
    ...stringsTravel,
    ...stringsHome,
    ...stringsTracker,
  };

  static String of(String lang, String key) {
    final e = _all[key];
    if (e == null) {
      // Never show raw keys: "some_key" → "Some key".
      final s = key.replaceAll('_', ' ').trim();
      return s.isEmpty ? key : s[0].toUpperCase() + s.substring(1);
    }
    if (lang == 'hi' && e.length > 1 && e[1].isNotEmpty) return e[1];
    return e[0];
  }

  static bool has(String key) => _all.containsKey(key);

  static String fill(String s, Map<String, Object?> args) {
    var out = s;
    args.forEach((k, v) => out = out.replaceAll('{$k}', '${v ?? ''}'));
    return out;
  }
}

extension TranslateX on BuildContext {
  String get lang => LocaleScope.of(this);

  String t(String key) => AppStrings.of(LocaleScope.of(this), key);

  String tr(String key, Map<String, Object?> args) =>
      AppStrings.fill(AppStrings.of(LocaleScope.of(this), key), args);

  /// Picks the singular or plural key: tn('task', n) → 'task_one' / 'task_other'.
  String tn(String key, int n) => AppStrings.fill(
      AppStrings.of(LocaleScope.of(this), n == 1 ? '${key}_one' : '${key}_other'), {'n': n});

  /// Date formatting in the active language.
  String fmtDate(DateTime d, String pattern) {
    final l = LocaleScope.of(this);
    try {
      return DateFormat(pattern, l == 'hi' ? 'hi' : 'en').format(d);
    } catch (_) {
      return DateFormat(pattern).format(d);
    }
  }
}

/// Makes the language available to every widget below it.
class LocaleScope extends InheritedWidget {
  final String lang;
  const LocaleScope({super.key, required this.lang, required super.child});

  static String of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    return scope?.lang ?? 'en';
  }

  @override
  bool updateShouldNotify(LocaleScope oldWidget) => oldWidget.lang != lang;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import 'localization.dart';
import 'settings.dart';

/// Human-friendly dates and times in the active language.
extension FormatX on BuildContext {
  bool get use24 {
    final s = Provider.of<AppSettings?>(this, listen: false);
    return (s?.use24h ?? false) || MediaQuery.alwaysUse24HourFormatOf(this);
  }

  String timeOf(DateTime d) => fmtDate(d, use24 ? 'HH:mm' : 'h:mm a');

  String timeOfHm(String hm) {
    final t = parseHm(hm);
    if (t == null) return '';
    return timeOf(DateTime(2000, 1, 1, t.hour, t.minute));
  }

  String timeOfDay(TimeOfDay t) => timeOf(DateTime(2000, 1, 1, t.hour, t.minute));

  /// Today / Tomorrow / Yesterday / Wed, 3 Oct / 3 Oct 2027.
  String dayLabel(DateTime d, {bool short = false}) {
    final diff = daysBetween(DateTime.now(), d);
    if (diff == 0) return t('today');
    if (diff == 1) return t('tomorrow');
    if (diff == -1) return t('yesterday');
    if (diff > 1 && diff < 7) return fmtDate(d, short ? 'EEE' : 'EEEE');
    if (d.year == DateTime.now().year) return fmtDate(d, short ? 'd MMM' : 'EEE, d MMM');
    return fmtDate(d, 'd MMM yyyy');
  }

  /// "Today, 5:00 PM" / "Tomorrow" / "Wed, 3 Oct, 9:00 AM".
  String dayTimeLabel(DateTime d, {bool hasTime = true}) {
    final day = dayLabel(d);
    return hasTime ? '$day, ${timeOf(d)}' : day;
  }

  /// "in 3h", "2d ago", "now".
  String relative(DateTime d) {
    final diff = d.difference(DateTime.now());
    final past = diff.isNegative;
    final a = diff.abs();
    String v;
    if (a.inMinutes < 1) return t('now');
    if (a.inMinutes < 60) {
      v = tr('dur_min', {'n': a.inMinutes});
    } else if (a.inHours < 24) {
      v = tr('dur_hour', {'n': a.inHours});
    } else {
      v = tr('dur_day', {'n': a.inDays});
    }
    return past ? tr('ago', {'x': v}) : tr('in_x', {'x': v});
  }

  String monthLabel(DateTime d) => fmtDate(d, 'MMMM yyyy');
}

String greetingKey([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return 'good_night';
  if (h < 12) return 'good_morning';
  if (h < 17) return 'good_afternoon';
  if (h < 21) return 'good_evening';
  return 'good_night';
}

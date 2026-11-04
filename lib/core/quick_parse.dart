/// Natural-language capture: "call Rahul tomorrow 5pm", "spent 250 on lunch",
/// "got salary 50000", "lent 500 to Amit", "gym every day 7am #health !high".
///
/// Deterministic rules only — runs offline, instantly, and never sends your
/// text anywhere. English plus common Hinglish words (kal, aaj, shaam…).
/// The UI always shows what was understood before saving.
library;

enum CaptureKind { task, reminder, expense, income, note, lent, borrowed }

class Parsed {
  CaptureKind kind;
  String title;
  DateTime? date; // day (and time when hasTime)
  bool hasTime;
  String repeat; // none | daily | weekdays | weekly | monthly | yearly
  String priority; // none | low | medium | high
  List<String> tags;
  double? amount;
  String person;
  final String source;

  Parsed({
    required this.kind,
    required this.title,
    required this.source,
    this.date,
    this.hasTime = false,
    this.repeat = 'none',
    this.priority = 'none',
    List<String>? tags,
    this.amount,
    this.person = '',
  }) : tags = tags ?? [];

  bool get isMoney =>
      kind == CaptureKind.expense ||
      kind == CaptureKind.income ||
      kind == CaptureKind.lent ||
      kind == CaptureKind.borrowed;

  /// When a reminder needs a concrete time: given time, else 9:00, else in 1h.
  DateTime reminderTime() {
    final now = DateTime.now();
    final d = date;
    if (d == null) return now.add(const Duration(hours: 1));
    if (hasTime) return d;
    final at9 = DateTime(d.year, d.month, d.day, 9);
    return at9.isAfter(now) ? at9 : now.add(const Duration(hours: 1));
  }
}

class _Span {
  final DateTime? day;
  final int? hour;
  final int? minute;
  _Span({this.day, this.hour, this.minute});
}

class QuickParse {
  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
    'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10,
    'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  };

  static const _weekdays = {
    'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'tues': 2,
    'wednesday': 3, 'wed': 3, 'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4,
    'friday': 5, 'fri': 5, 'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7,
    'somvar': 1, 'mangalvar': 2, 'budhvar': 3, 'guruvar': 4, 'shukravar': 5,
    'shanivar': 6, 'ravivar': 7,
  };

  static const _taskVerbs = [
    'buy', 'call', 'email', 'send', 'submit', 'finish', 'complete', 'book',
    'order', 'collect', 'pick', 'drop', 'return', 'check', 'review', 'fix',
    'clean', 'wash', 'read', 'write', 'study', 'prepare', 'print', 'renew',
    'apply', 'meet', 'visit', 'get', 'bring', 'take', 'ask', 'message', 'text',
    'pay', 'cook', 'plan', 'learn', 'practice', 'watch', 'go', 'make',
  ];

  /// Splits a brain-dump into items (new lines, ';', and commas between
  /// whole thoughts). Fragments that are only a date/time join the previous
  /// item, so "call mom tomorrow, 5pm" stays one item.
  static List<String> split(String input) {
    final out = <String>[];
    for (final line in input.split(RegExp(r'[\n;]+'))) {
      final parts = line.split(RegExp(r',\s+'));
      for (final p in parts) {
        final t = p.trim();
        if (t.isEmpty) continue;
        final probe = parse(t);
        final onlyWhen = probe.title.trim().isEmpty && probe.date != null;
        if (onlyWhen && out.isNotEmpty) {
          out[out.length - 1] = '${out.last}, $t';
        } else {
          out.add(t);
        }
      }
    }
    return out;
  }

  static List<Parsed> parseAll(String input, {DateTime? now}) =>
      split(input).map((s) => parse(s, now: now)).toList();

  static Parsed parse(String input, {DateTime? now}) {
    final n = now ?? DateTime.now();
    var rest = ' ${input.trim()} ';
    final tags = <String>[];
    var priority = 'none';
    var repeat = 'none';
    CaptureKind? forced;

    String cut(RegExp re, [void Function(Match m)? on]) {
      return rest.replaceAllMapped(re, (m) {
        on?.call(m);
        return ' ';
      });
    }

    // Tags and priority markers.
    rest = cut(RegExp(r'(?<=\s)#([\p{L}\p{N}_-]+)', unicode: true), (m) => tags.add(m.group(1)!));
    rest = cut(RegExp(r'(?<=\s)(!high|!h|!!!|p1)(?=\s)', caseSensitive: false), (_) => priority = 'high');
    rest = cut(RegExp(r'(?<=\s)(!medium|!med|!m|!!|p2)(?=\s)', caseSensitive: false), (_) => priority = 'medium');
    rest = cut(RegExp(r'(?<=\s)(!low|!l|p3)(?=\s)', caseSensitive: false), (_) => priority = 'low');
    if (RegExp(r'\b(urgent|asap|important|zaroori)\b', caseSensitive: false).hasMatch(rest) && priority == 'none') {
      priority = 'high';
    }

    // Kind prefixes.
    final prefix = RegExp(r'^\s*(note|idea|n)\s*:\s*', caseSensitive: false).firstMatch(rest);
    if (prefix != null) {
      forced = CaptureKind.note;
      rest = ' ${rest.substring(prefix.end)} ';
    }
    final remind = RegExp(
        r"\b(remind me( to| about| of)?|reminder( to| for)?|don'?t forget( to)?|yaad dila(na|o)?|alarm( for)?)\b",
        caseSensitive: false);
    if (forced == null && remind.hasMatch(rest)) {
      forced = CaptureKind.reminder;
      rest = rest.replaceAll(remind, ' ');
    }

    // Repeat rules.
    final rep = <(RegExp, String)>[
      (RegExp(r'\b(every ?day|daily|everyday|roz(ana)?|har din)\b', caseSensitive: false), 'daily'),
      (RegExp(r'\b(every weekday|weekdays|on weekdays)\b', caseSensitive: false), 'weekdays'),
      (RegExp(r'\b(every month|monthly|har mahine)\b', caseSensitive: false), 'monthly'),
      (RegExp(r'\b(every year|yearly|annually|har saal)\b', caseSensitive: false), 'yearly'),
      (RegExp(r'\b(every week|weekly|har hafte)\b', caseSensitive: false), 'weekly'),
    ];
    for (final r in rep) {
      if (r.$1.hasMatch(rest)) {
        repeat = r.$2;
        rest = rest.replaceAll(r.$1, ' ');
        break;
      }
    }
    // "every monday" → weekly on Monday.
    DateTime? everyDay;
    rest = cut(RegExp(r'\bevery (monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b',
        caseSensitive: false), (m) {
      repeat = 'weekly';
      everyDay = _nextWeekday(n, _weekdays[m.group(1)!.toLowerCase()]!, allowToday: true);
    });

    // Dates & times.
    final when = _extractWhen(rest, n);
    rest = when.$2;
    var date = when.$1?.day ?? everyDay;
    final int? hour = when.$1?.hour;
    final minute = when.$1?.minute ?? 0;
    var hasTime = hour != null;
    if (hour != null && date == null) {
      var d = DateTime(n.year, n.month, n.day, hour, minute);
      if (d.isBefore(n) && repeat == 'none') d = DateTime(n.year, n.month, n.day + 1, hour, minute);
      date = d;
    } else if (date != null && hour != null) {
      date = DateTime(date.year, date.month, date.day, hour, minute);
    }
    if (repeat != 'none' && date == null) {
      date = DateTime(n.year, n.month, n.day);
    }

    // Money.
    final lower = rest.toLowerCase();
    double? amount;
    var person = '';
    CaptureKind? moneyKind;
    final amt = _amount(rest);
    if (amt != null) {
      final isLend = RegExp(r'\b(lent|lend|gave|udhaa?r diya|udhaa?r de)\b').hasMatch(lower);
      final isBorrow = RegExp(r'\b(borrowed|borrow|took|udhaa?r liya|udhaa?r le)\b').hasMatch(lower);
      final isIncome = RegExp(
              r'\b(got|received|recieved|earned|earn|salary|income|credited|credit|mila|mile|bonus|refund|cashback|sold)\b')
          .hasMatch(lower);
      final isExpense = RegExp(
              r'\b(spent|spend|paid|pay|payed|bought|purchase[d]?|kharch[a]?|diye|cost|bill|fees|debited)\b')
          .hasMatch(lower);
      final hasSymbol = RegExp(r'(₹|rs\.?\s*\d|\$|€|£|\binr\b|\busd\b|\baed\b|rupees|\d\s*rs\b|\dk\b)', caseSensitive: false)
          .hasMatch(rest);
      final words = rest.replaceAll(amt.$2, ' ').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final startsWithVerb = words.isNotEmpty && _taskVerbs.contains(words.first.toLowerCase()) && !isExpense;
      if (isLend) {
        moneyKind = CaptureKind.lent;
        person = _personAfter(rest, ['to', 'ko']);
      } else if (isBorrow) {
        moneyKind = CaptureKind.borrowed;
        person = _personAfter(rest, ['from', 'se']);
      } else if (isIncome) {
        moneyKind = CaptureKind.income;
      } else if (isExpense || hasSymbol) {
        moneyKind = CaptureKind.expense;
      } else if (!startsWithVerb && words.length <= 3 && amt.$1 >= 10 && forced == null && !hasTime) {
        moneyKind = CaptureKind.expense;
      }
      if (moneyKind != null) {
        amount = amt.$1;
        rest = rest.replaceFirst(amt.$2, ' ');
      }
    }

    // Title cleanup.
    var title = rest;
    if (moneyKind != null) {
      title = title.replaceAll(
          RegExp(
              r'\b(spent|spend|paid|pay|payed|bought|purchased?|kharch[a]?|diye|cost|got|received|recieved|earned|earn|credited|credit|mila|mile|lent|lend|gave|borrowed|borrow|took|udhaa?r|diya|liya|rs\.?|rupees|inr)\b',
              caseSensitive: false),
          ' ');
      if (person.isNotEmpty) {
        title = title.replaceFirst(RegExp('\\b(to|from|ko|se)\\s+${RegExp.escape(person)}\\b', caseSensitive: false), ' ');
      }
    }
    title = _tidy(title);

    final kind = forced ?? moneyKind ?? CaptureKind.task;
    if (kind == CaptureKind.reminder && date == null) {
      hasTime = false;
    }
    return Parsed(
      kind: kind,
      title: title,
      source: input.trim(),
      date: date,
      hasTime: hasTime,
      repeat: repeat,
      priority: priority,
      tags: tags,
      amount: amount,
      person: person,
    );
  }

  static String _tidy(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    const lead = ['to', 'on', 'at', 'for', 'by', 'about', 'and', 'of', 'ko', 'pe', 'par', 'ka', 'ki', 'ke', '-', ':', ','];
    const trail = ['on', 'at', 'by', 'for', 'to', 'and', 'the', 'in', 'ko', 'pe', 'par', 'ka', 'ki', 'ke', 'from', '-', ':', ','];
    var changed = true;
    while (changed && t.isNotEmpty) {
      changed = false;
      final parts = t.split(' ');
      if (parts.length > 1 && lead.contains(parts.first.toLowerCase())) {
        t = parts.sublist(1).join(' ');
        changed = true;
        continue;
      }
      if (parts.length > 1 && trail.contains(parts.last.toLowerCase())) {
        t = parts.sublist(0, parts.length - 1).join(' ');
        changed = true;
      }
    }
    t = t.replaceAll(RegExp(r'^[,.\-:]+|[,.\-:]+$'), '').trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  static String _personAfter(String s, List<String> preps) {
    final re = RegExp('\\b(?:${preps.join('|')})\\s+([A-Za-z\\u0900-\\u097F][\\w\\u0900-\\u097F]*(?:\\s+[A-Z][a-z]+)?)',
        caseSensitive: false);
    final m = re.firstMatch(s);
    if (m == null) return '';
    final p = m.group(1)!.trim();
    return p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1);
  }

  /// (amount, matched text) — handles ₹1,200 / rs 500 / 2.5k / 1,20,000.
  static (double, String)? _amount(String s) {
    final re = RegExp(
        r'(?:₹|rs\.?|inr|\$|€|£|usd|eur|aed)?\s?(\d{1,3}(?:,\d{2,3})+|\d+)(?:\.(\d{1,2}))?\s?(k\b|rs\b|rupees\b|₹)?',
        caseSensitive: false);
    for (final m in re.allMatches(s)) {
      final whole = m.group(0)!;
      final numStr = m.group(1)!.replaceAll(',', '');
      var v = double.tryParse(numStr) ?? 0;
      if (m.group(2) != null) v += double.parse('0.${m.group(2)}');
      if ((m.group(3) ?? '').toLowerCase() == 'k') v *= 1000;
      if (v <= 0) continue;
      return (v, whole);
    }
    return null;
  }

  static DateTime _nextWeekday(DateTime n, int wd, {bool allowToday = false}) {
    var diff = (wd - n.weekday) % 7;
    if (diff == 0 && !allowToday) diff = 7;
    return DateTime(n.year, n.month, n.day + diff);
  }

  /// Returns the parsed date/time (if any) and the text with it removed.
  static (_Span?, String) _extractWhen(String input, DateTime n) {
    var s = input;
    DateTime? day;
    int? hour;
    int? minute;
    final today = DateTime(n.year, n.month, n.day);

    bool take(RegExp re, void Function(RegExpMatch m) on) {
      final m = re.firstMatch(s);
      if (m == null) return false;
      on(m);
      s = s.replaceRange(m.start, m.end, ' ');
      return true;
    }

    // Relative durations: in 2 hours / in 30 min / in 3 days.
    take(RegExp(r'\bin (\d+|an?|one|two|three|half an?) ?(min(?:ute)?s?|hours?|hrs?|h|days?|weeks?|months?)\b',
        caseSensitive: false), (m) {
      final q = m.group(1)!.toLowerCase();
      final num = switch (q) {
        'a' || 'an' || 'one' => 1,
        'two' => 2,
        'three' => 3,
        _ => int.tryParse(q) ?? 1,
      };
      final u = m.group(2)!.toLowerCase();
      if (q.startsWith('half')) {
        final t = n.add(const Duration(minutes: 30));
        day = DateTime(t.year, t.month, t.day);
        hour = t.hour;
        minute = t.minute;
      } else if (u.startsWith('min')) {
        final t = n.add(Duration(minutes: num));
        day = DateTime(t.year, t.month, t.day);
        hour = t.hour;
        minute = t.minute;
      } else if (u.startsWith('h')) {
        final t = n.add(Duration(hours: num));
        day = DateTime(t.year, t.month, t.day);
        hour = t.hour;
        minute = t.minute;
      } else if (u.startsWith('day')) {
        day = DateTime(n.year, n.month, n.day + num);
      } else if (u.startsWith('week')) {
        day = DateTime(n.year, n.month, n.day + 7 * num);
      } else {
        day = DateTime(n.year, n.month + num, n.day);
      }
    });

    // Day words.
    if (day == null) {
      take(RegExp(r'\b(day after tomorrow|parso|parson)\b', caseSensitive: false),
          (_) => day = DateTime(n.year, n.month, n.day + 2));
    }
    if (day == null) {
      take(RegExp(r'\b(tomorrow|tmrw|tmr|tomorow|kal)\b', caseSensitive: false),
          (_) => day = DateTime(n.year, n.month, n.day + 1));
    }
    if (day == null) {
      take(RegExp(r'\b(today|aaj|tonight)\b', caseSensitive: false), (m) {
        day = today;
        if (m.group(1)!.toLowerCase() == 'tonight') hour ??= 21;
      });
    }
    if (day == null) {
      take(RegExp(r'\b(next week)\b', caseSensitive: false), (_) => day = _nextWeekday(n, 1));
    }
    if (day == null) {
      take(RegExp(r'\b(this weekend|weekend)\b', caseSensitive: false),
          (_) => day = _nextWeekday(n, 6, allowToday: true));
    }
    if (day == null) {
      take(RegExp(r'\b(next month)\b', caseSensitive: false), (_) => day = DateTime(n.year, n.month + 1, 1));
    }
    if (day == null) {
      take(
          RegExp(
              r'\b(next |this |on )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|somvar|mangalvar|budhvar|guruvar|shukravar|shanivar|ravivar)\b',
              caseSensitive: false), (m) {
        final wd = _weekdays[m.group(2)!.toLowerCase()]!;
        day = _nextWeekday(n, wd, allowToday: (m.group(1) ?? '').trim().toLowerCase() == 'this');
      });
    }
    // 5 oct / 5th october 2027 / oct 5.
    if (day == null) {
      final monthAlt = _months.keys.join('|');
      take(RegExp('\\b(?:on )?(\\d{1,2})(?:st|nd|rd|th)?\\s+($monthAlt)\\b(?:,?\\s*(\\d{4}))?', caseSensitive: false),
          (m) {
        final d = int.parse(m.group(1)!);
        final mo = _months[m.group(2)!.toLowerCase()]!;
        var y = int.tryParse(m.group(3) ?? '') ?? n.year;
        var dt = DateTime(y, mo, d);
        if (m.group(3) == null && dt.isBefore(today)) dt = DateTime(y + 1, mo, d);
        day = dt;
      });
    }
    if (day == null) {
      final monthAlt = _months.keys.join('|');
      take(RegExp('\\b($monthAlt)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s*(\\d{4}))?', caseSensitive: false), (m) {
        final mo = _months[m.group(1)!.toLowerCase()]!;
        final d = int.parse(m.group(2)!);
        var y = int.tryParse(m.group(3) ?? '') ?? n.year;
        var dt = DateTime(y, mo, d);
        if (m.group(3) == null && dt.isBefore(today)) dt = DateTime(y + 1, mo, d);
        day = dt;
      });
    }
    // 12/10 or 12-10-2026 (day first unless impossible).
    if (day == null) {
      take(RegExp(r'\b(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?\b'), (m) {
        var a = int.parse(m.group(1)!);
        var b = int.parse(m.group(2)!);
        if (b > 12 && a <= 12) {
          final t = a;
          a = b;
          b = t;
        }
        var y = int.tryParse(m.group(3) ?? '') ?? n.year;
        if (y < 100) y += 2000;
        if (b >= 1 && b <= 12 && a >= 1 && a <= 31) {
          var dt = DateTime(y, b, a);
          if (m.group(3) == null && dt.isBefore(today)) dt = DateTime(y + 1, b, a);
          day = dt;
        }
      });
    }
    // on the 5th → this or next month.
    if (day == null) {
      take(RegExp(r'\bon (?:the )?(\d{1,2})(?:st|nd|rd|th)\b', caseSensitive: false), (m) {
        final d = int.parse(m.group(1)!);
        var dt = DateTime(n.year, n.month, d);
        if (dt.isBefore(today)) dt = DateTime(n.year, n.month + 1, d);
        day = dt;
      });
    }

    // Times: 5pm, 5:30 pm, at 17:30, at 5, noon, morning…
    take(RegExp(r'\b(?:at |@ ?|by )?(\d{1,2})(?:[:.](\d{2}))?\s?(am|pm|a\.m\.|p\.m\.)', caseSensitive: false), (m) {
      var h = int.parse(m.group(1)!);
      final mi = int.tryParse(m.group(2) ?? '0') ?? 0;
      final pm = m.group(3)!.toLowerCase().startsWith('p');
      if (pm && h != 12) h += 12;
      if (!pm && h == 12) h = 0;
      if (h < 24 && mi < 60) {
        hour = h;
        minute = mi;
      }
    });
    if (hour == null) {
      take(RegExp(r'\b(?:at |@ ?)?([01]?\d|2[0-3]):([0-5]\d)\b'), (m) {
        hour = int.parse(m.group(1)!);
        minute = int.parse(m.group(2)!);
      });
    }
    if (hour == null) {
      take(RegExp(r'\b(?:at|@|baje)\s?(\d{1,2})\b(?!\s?(?:%|rs|k\b|₹))', caseSensitive: false), (m) {
        var h = int.parse(m.group(1)!);
        if (h >= 1 && h <= 7) h += 12;
        if (h < 24) {
          hour = h;
          minute = 0;
        }
      });
    }
    if (hour == null) {
      take(RegExp(r'\b(\d{1,2})\s?baje\b', caseSensitive: false), (m) {
        var h = int.parse(m.group(1)!);
        if (h >= 1 && h <= 7) h += 12;
        if (h < 24) {
          hour = h;
          minute = 0;
        }
      });
    }
    if (hour == null) {
      take(RegExp(r'\b(noon|dopahar|midday)\b', caseSensitive: false), (_) => hour = 12);
    }
    if (hour == null) {
      take(RegExp(r'\b(in the morning|morning|subah)\b', caseSensitive: false), (_) => hour = 9);
    }
    if (hour == null) {
      take(RegExp(r'\b(in the afternoon|afternoon)\b', caseSensitive: false), (_) => hour = 14);
    }
    if (hour == null) {
      take(RegExp(r'\b(in the evening|evening|shaam|sham)\b', caseSensitive: false), (_) => hour = 18);
    }
    if (hour == null) {
      take(RegExp(r'\b(at night|night|raat)\b', caseSensitive: false), (_) => hour = 21);
    }

    if (day == null && hour == null) return (null, s);
    return (_Span(day: day, hour: hour, minute: minute ?? 0), s);
  }
}

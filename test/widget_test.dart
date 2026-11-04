// Unit tests for DailyHub's rule-based Smart Capture parser.
//
// A widget test of the real app would need Firebase initialised, which doesn't
// work in a plain unit test, so what's worth testing here is the parser: it's
// pure Dart with no plugins, and it's the piece most likely to regress.
//
// Every date-dependent test passes a fixed `now` so the suite can't go red
// just because it ran at an awkward time of day.

import 'package:flutter_test/flutter_test.dart';

import 'package:dailyhub/core/quick_parse.dart';

void main() {
  // Wednesday, 15 October 2025, 10:00.
  final now = DateTime(2025, 10, 15, 10);

  group('QuickParse.split', () {
    test('splits on newlines and on commas between whole thoughts', () {
      final items = QuickParse.split('Buy charger, call Rahul\npay bill');
      expect(items.length, 3);
      expect(items[0], 'Buy charger');
      expect(items[1], 'call Rahul');
      expect(items[2], 'pay bill');
    });

    test('keeps a trailing time with the item it belongs to', () {
      final items = QuickParse.split('call mom tomorrow, 5pm');
      expect(items.length, 1);
    });

    test('drops empty fragments', () {
      expect(QuickParse.split('a,,  ,b').length, 2);
    });
  });

  group('QuickParse.parse — kind', () {
    test('plain text becomes a task', () {
      expect(QuickParse.parse('Buy charger', now: now).kind, CaptureKind.task);
    });

    test('"remind me to" forces a reminder', () {
      expect(QuickParse.parse('remind me to call mom', now: now).kind, CaptureKind.reminder);
    });

    test('a "note:" prefix forces a note', () {
      final p = QuickParse.parse('note: idea for the shop', now: now);
      expect(p.kind, CaptureKind.note);
      expect(p.title, 'Idea for the shop');
    });

    test('a spending word plus an amount becomes an expense', () {
      final p = QuickParse.parse('paid 500 rs for lunch', now: now);
      expect(p.kind, CaptureKind.expense);
      expect(p.amount, 500);
    });

    test('an earning word plus an amount becomes income', () {
      final p = QuickParse.parse('got 40000 salary', now: now);
      expect(p.kind, CaptureKind.income);
      expect(p.amount, 40000);
    });

    test('lending records the person', () {
      final p = QuickParse.parse('lent 500 to Raju', now: now);
      expect(p.kind, CaptureKind.lent);
      expect(p.amount, 500);
      expect(p.person, 'Raju');
    });

    test('borrowing records the person', () {
      final p = QuickParse.parse('borrowed 200 from Amit', now: now);
      expect(p.kind, CaptureKind.borrowed);
      expect(p.person, 'Amit');
    });
  });

  group('QuickParse.parse — amounts', () {
    test('reads a rupee symbol', () {
      expect(QuickParse.parse('spent ₹250 on food', now: now).amount, 250);
    });

    test('reads Indian digit grouping', () {
      expect(QuickParse.parse('spent 1,20,000 on the car', now: now).amount, 120000);
    });

    test('reads the k shorthand', () {
      expect(QuickParse.parse('spent 2k on books', now: now).amount, 2000);
    });
  });

  group('QuickParse.parse — dates and times', () {
    test('understands tomorrow', () {
      final p = QuickParse.parse('book train tomorrow', now: now);
      expect(p.date, isNotNull);
      expect(p.date!.day, 16);
      expect(p.hasTime, isFalse);
    });

    test('understands the Hinglish "kal"', () {
      expect(QuickParse.parse('gym kal', now: now).date!.day, 16);
    });

    test('understands a 12-hour time', () {
      final p = QuickParse.parse('meeting tomorrow 5pm', now: now);
      expect(p.date, isNotNull);
      expect(p.date!.hour, 17);
      expect(p.hasTime, isTrue);
    });

    test('a time alone today stays today when it is still ahead', () {
      final p = QuickParse.parse('call Rahul 6pm', now: now);
      expect(p.date!.day, 15);
      expect(p.date!.hour, 18);
    });

    test('a time that has already passed rolls to tomorrow', () {
      final p = QuickParse.parse('call Rahul 8am', now: now);
      expect(p.date!.day, 16);
      expect(p.date!.hour, 8);
    });

    test('plain text gets no date', () {
      expect(QuickParse.parse('buy milk', now: now).date, isNull);
    });
  });

  group('QuickParse.parse — markers', () {
    test('picks up #tags and strips them from the title', () {
      final p = QuickParse.parse('gym #health #daily', now: now);
      expect(p.tags, ['health', 'daily']);
      expect(p.title, 'Gym');
    });

    test('picks up a priority marker', () {
      expect(QuickParse.parse('submit report !high', now: now).priority, 'high');
      expect(QuickParse.parse('submit report p3', now: now).priority, 'low');
    });

    test('treats "urgent" as high priority', () {
      expect(QuickParse.parse('urgent: fix the tap', now: now).priority, 'high');
    });

    test('reads a repeat rule', () {
      expect(QuickParse.parse('pay rent every month', now: now).repeat, 'monthly');
      expect(QuickParse.parse('walk every day', now: now).repeat, 'daily');
      expect(QuickParse.parse('roz paani peena', now: now).repeat, 'daily');
    });

    test('"every monday" repeats weekly on the next Monday', () {
      final p = QuickParse.parse('team sync every monday', now: now);
      expect(p.repeat, 'weekly');
      expect(p.date!.weekday, DateTime.monday);
    });
  });

  group('QuickParse.parseAll', () {
    test('turns a brain-dump into several items of different kinds', () {
      final items = QuickParse.parseAll('buy milk\nspent 250 lunch\nremind me to call mom', now: now);
      expect(items.length, 3);
      expect(items[0].kind, CaptureKind.task);
      expect(items[1].kind, CaptureKind.expense);
      expect(items[2].kind, CaptureKind.reminder);
    });
  });
}

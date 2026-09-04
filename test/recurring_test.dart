import 'package:flutter_test/flutter_test.dart';
import 'package:penny/recurring.dart';
import 'package:penny/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Rule rule({
  String start = '2026-01-15',
  Freq freq = Freq.monthly,
  int interval = 1,
  String? last,
  String? end,
  bool active = true,
}) =>
    Rule(
      kind: TxKind.expense,
      amountMinor: 2500000,
      categoryId: 'c1',
      accountId: 'a1',
      note: 'Rent',
      freq: freq,
      interval: interval,
      startDay: start,
      endDay: end,
      lastRunDay: last,
      active: active,
    );

List<String> days(List<Txn> t) => [for (final x in t) x.day];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('monthly', () {
    test('produces one row per month up to today', () {
      final due = dueOccurrences(rule(), DateTime(2026, 4, 20));
      expect(days(due), ['2026-01-15', '2026-02-15', '2026-03-15', '2026-04-15']);
    });

    test('an occurrence due today is included', () {
      final due = dueOccurrences(rule(start: '2026-09-04'), DateTime(2026, 9, 4));
      expect(days(due), ['2026-09-04']);
    });

    test('a start day in the future owes nothing yet', () {
      expect(dueOccurrences(rule(start: '2026-12-01'), DateTime(2026, 9, 4)),
          isEmpty);
    });

    test('the 31st clamps in February and comes BACK on the 31st', () {
      // The bug this guards: computing March from the clamped 28th would pin
      // the rule to the 28th for the rest of its life.
      final due = dueOccurrences(rule(start: '2026-01-31'), DateTime(2026, 5, 5));
      expect(days(due),
          ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
    });

    test('February gets 29 days in a leap year', () {
      final due = dueOccurrences(rule(start: '2024-01-31'), DateTime(2024, 2, 29));
      expect(days(due), ['2024-01-31', '2024-02-29']);
    });

    test('an interval skips months', () {
      final due = dueOccurrences(
          rule(start: '2026-01-10', interval: 3), DateTime(2026, 10, 1));
      expect(days(due), ['2026-01-10', '2026-04-10', '2026-07-10']);
    });
  });

  group('weekly and daily', () {
    test('weekly lands on the same weekday', () {
      final due = dueOccurrences(
          rule(start: '2026-09-01', freq: Freq.weekly), DateTime(2026, 9, 20));
      expect(days(due),
          ['2026-09-01', '2026-09-08', '2026-09-15']);
      for (final d in days(due)) {
        expect(parseDay(d).weekday, DateTime.tuesday);
      }
    });

    test('a fortnightly rule is weekly with interval 2', () {
      final due = dueOccurrences(
          rule(start: '2026-09-01', freq: Freq.weekly, interval: 2),
          DateTime(2026, 10, 1));
      expect(days(due), ['2026-09-01', '2026-09-15', '2026-09-29']);
    });

    test('daily crosses a month end', () {
      final due = dueOccurrences(
          rule(start: '2026-08-30', freq: Freq.daily), DateTime(2026, 9, 2));
      expect(days(due),
          ['2026-08-30', '2026-08-31', '2026-09-01', '2026-09-02']);
    });
  });

  group('bounds', () {
    test('nothing is produced twice', () {
      final due = dueOccurrences(
          rule(last: '2026-03-15'), DateTime(2026, 5, 20));
      expect(days(due), ['2026-04-15', '2026-05-15']);
    });

    test('an end day stops the rule', () {
      final due = dueOccurrences(
          rule(end: '2026-03-31'), DateTime(2026, 12, 1));
      expect(days(due), ['2026-01-15', '2026-02-15', '2026-03-15']);
    });

    test('an inactive rule owes nothing', () {
      expect(dueOccurrences(rule(active: false), DateTime(2026, 6, 1)), isEmpty);
    });

    test('a long backlog is capped, not dumped in one frame', () {
      final due = dueOccurrences(
          rule(start: '2000-01-01', freq: Freq.daily), DateTime(2026, 9, 4));
      expect(due, hasLength(maxPerPass));
      expect(due.first.day, '2000-01-01');
    });
  });

  group('materialising into the store', () {
    test('adds the rows and remembers where it stopped', () async {
      final s = PennyStore();
      await s.load();
      s.seedDefaults();
      final a = s.accounts.first.id;
      final c = s.categoriesOf(TxKind.expense).first.id;

      final r = Rule(
          kind: TxKind.expense,
          amountMinor: 2500000,
          categoryId: c,
          accountId: a,
          note: 'Rent',
          startDay: '2026-01-15');
      s.addRule(r);

      expect(materialiseDue(s, now: DateTime(2026, 3, 20)), 3);
      expect(s.txns, hasLength(3));
      expect(r.lastRunDay, '2026-03-15');
      expect(s.balanceOf(a), -7500000);
    });

    test('running twice on the same day adds nothing the second time', () async {
      final s = PennyStore();
      await s.load();
      s.seedDefaults();
      s.addRule(Rule(
          kind: TxKind.expense,
          amountMinor: 2500000,
          categoryId: s.categoriesOf(TxKind.expense).first.id,
          accountId: s.accounts.first.id,
          startDay: '2026-01-15'));

      materialiseDue(s, now: DateTime(2026, 3, 20));
      final n = s.txns.length;
      expect(materialiseDue(s, now: DateTime(2026, 3, 20)), 0);
      expect(s.txns, hasLength(n),
          reason: 'relaunching the app must not duplicate rent');
    });

    test('materialised rows are ordinary and deletable on their own', () async {
      final s = PennyStore();
      await s.load();
      s.seedDefaults();
      final r = Rule(
          kind: TxKind.expense,
          amountMinor: 2500000,
          categoryId: s.categoriesOf(TxKind.expense).first.id,
          accountId: s.accounts.first.id,
          startDay: '2026-01-15');
      s.addRule(r);
      materialiseDue(s, now: DateTime(2026, 3, 20));

      s.removeTxn(s.txns.first);
      expect(s.txns, hasLength(2));
      // And the rule does not re-create it: the row was deliberately removed.
      expect(materialiseDue(s, now: DateTime(2026, 3, 20)), 0);
      expect(s.txns.every((t) => t.ruleId == r.id), isTrue);
    });

    test('a transfer rule keeps its destination', () async {
      final s = PennyStore();
      await s.load();
      s.seedDefaults();
      final from = s.accounts[1].id, to = s.accounts[0].id;
      s.addRule(Rule(
          kind: TxKind.transfer,
          amountMinor: 500000,
          categoryId: s.categoriesOf(TxKind.expense).first.id,
          accountId: from,
          toAccountId: to,
          freq: Freq.weekly,
          startDay: '2026-09-01'));

      materialiseDue(s, now: DateTime(2026, 9, 10));
      expect(s.txns, hasLength(2));
      expect(s.txns.every((t) => t.toAccountId == to), isTrue);
      expect(s.balanceOf(from), -1000000);
      expect(s.balanceOf(to), 1000000);
      expect(s.totalBalance, 0, reason: 'a standing transfer moves, not spends');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:penny/analytics.dart';
import 'package:penny/store.dart';

Txn tx(
  TxKind kind,
  int amount,
  String day, {
  String category = 'c1',
  String? to,
}) => Txn(
  kind: kind,
  amountMinor: amount,
  day: day,
  categoryId: category,
  accountId: 'a1',
  toAccountId: to,
);

void main() {
  group('ranges', () {
    test('a day is itself', () {
      final r = rangeFor(Period.day, DateTime(2026, 9, 4));
      expect(r, (from: '2026-09-04', to: '2026-09-04'));
    });

    test('a week runs Monday to Sunday', () {
      final r = rangeFor(Period.week, DateTime(2026, 9, 4)); // a Friday
      expect(r, (from: '2026-08-31', to: '2026-09-06'));
    });

    test('a month ends on its own last day, whatever that is', () {
      expect(rangeFor(Period.month, DateTime(2026, 2, 10)), (
        from: '2026-02-01',
        to: '2026-02-28',
      ));
      expect(rangeFor(Period.month, DateTime(2024, 2, 10)), (
        from: '2024-02-01',
        to: '2024-02-29',
      ));
      expect(rangeFor(Period.month, DateTime(2026, 12, 31)), (
        from: '2026-12-01',
        to: '2026-12-31',
      ));
    });

    test('shifting a month back crosses the year', () {
      expect(shiftRange(Period.month, DateTime(2026, 1, 15), -1), (
        from: '2025-12-01',
        to: '2025-12-31',
      ));
    });

    test('shifting a month from the 31st does not skip February', () {
      expect(shiftRange(Period.month, DateTime(2026, 1, 31), 1), (
        from: '2026-02-01',
        to: '2026-02-28',
      ));
    });
  });

  group('totals', () {
    final txns = [
      tx(TxKind.income, 8000000, '2026-09-01'),
      tx(TxKind.expense, 45000, '2026-09-02'),
      tx(TxKind.expense, 120000, '2026-09-04'),
      tx(TxKind.expense, 999999, '2026-08-31'), // outside September
    ];

    test('add up inside the range and nothing outside it', () {
      final t = totalsIn(txns, rangeFor(Period.month, DateTime(2026, 9, 15)));
      expect(t.income, 8000000);
      expect(t.expense, 165000);
      expect(t.net, 7835000);
    });

    test('a transfer is neither income nor expense', () {
      final withTransfer = [
        ...txns,
        tx(TxKind.transfer, 500000, '2026-09-03', to: 'a2'),
      ];
      final before = totalsIn(
        txns,
        rangeFor(Period.month, DateTime(2026, 9, 1)),
      );
      final after = totalsIn(
        withTransfer,
        rangeFor(Period.month, DateTime(2026, 9, 1)),
      );
      expect(
        after,
        before,
        reason: 'withdrawing cash must not change the month',
      );
    });

    test('an empty range is zero, not an error', () {
      final t = totalsIn(txns, rangeFor(Period.day, DateTime(2026, 1, 1)));
      expect(t.income, 0);
      expect(t.expense, 0);
      expect(t.net, 0);
    });

    test('a net can be negative without anything special happening', () {
      final t = totalsIn([
        tx(TxKind.expense, 5000, '2026-09-04'),
      ], rangeFor(Period.day, DateTime(2026, 9, 4)));
      expect(t.net, -5000);
    });

    test('the range is inclusive at both ends', () {
      final r = (from: '2026-09-02', to: '2026-09-04');
      expect(totalsIn(txns, r).expense, 165000);
    });
  });

  group('breakdowns', () {
    final txns = [
      tx(TxKind.expense, 300000, '2026-09-01', category: 'food'),
      tx(TxKind.expense, 100000, '2026-09-02', category: 'travel'),
      tx(TxKind.expense, 200000, '2026-09-03', category: 'food'),
      tx(TxKind.income, 900000, '2026-09-03', category: 'salary'),
      tx(TxKind.transfer, 500000, '2026-09-03', category: 'food', to: 'a2'),
    ];
    final september = rangeFor(Period.month, DateTime(2026, 9, 10));

    test('by category, largest first, transfers excluded', () {
      final b = byCategory(txns, september, TxKind.expense);
      expect(b.keys.toList(), ['food', 'travel']);
      expect(b['food'], 500000, reason: 'the transfer must not be counted');
      expect(b['travel'], 100000);
    });

    test('income and expense are separate breakdowns', () {
      expect(byCategory(txns, september, TxKind.income), {'salary': 900000});
    });

    test('a category with nothing in it is absent, not zero', () {
      final b = byCategory(
        txns,
        rangeFor(Period.day, DateTime(2026, 9, 2)),
        TxKind.expense,
      );
      expect(b, {'travel': 100000});
      expect(b.containsKey('food'), isFalse);
    });

    test('spend by day skips income and transfers', () {
      final byDay = spendByDay(txns, september);
      expect(byDay, {
        '2026-09-01': 300000,
        '2026-09-02': 100000,
        '2026-09-03': 200000,
      });
    });
  });

  group('series', () {
    final txns = [
      tx(TxKind.expense, 100000, '2026-07-05'),
      tx(TxKind.expense, 300000, '2026-09-05'),
      tx(TxKind.income, 900000, '2026-09-06'),
    ];

    test('runs oldest to newest and ends on the anchor', () {
      final s = series(txns, Period.month, DateTime(2026, 9, 15), 3);
      expect(s.map((b) => b.label), ['Jul', 'Aug', 'Sep']);
      expect(s.last.expense, 300000);
      expect(s.last.income, 900000);
    });

    test('an empty period is a zero bar, not a missing one', () {
      final s = series(txns, Period.month, DateTime(2026, 9, 15), 3);
      // August is empty. Dropping it would put July next to September and
      // make a two-month gap look like one step.
      expect(s[1].label, 'Aug');
      expect(s[1].expense, 0);
      expect(s[1].income, 0);
    });

    test('a daily series is labelled by day of month', () {
      final s = series(txns, Period.day, DateTime(2026, 9, 6), 2);
      expect(s.map((b) => b.label), ['5', '6']);
    });
  });

  group('the chart axis', () {
    test('rounds the peak up to a 1, 2 or 5', () {
      expect(niceAxisMax(7843100), 10000000); // ₹78,431 -> ₹1L
      expect(niceAxisMax(4500), 5000);
      expect(niceAxisMax(1100), 2000);
      expect(niceAxisMax(1000), 1000);
    });

    test('never returns a zero to divide a bar by', () {
      expect(niceAxisMax(0), greaterThan(0));
      expect(niceAxisMax(-5), greaterThan(0));
    });
  });

  group('comparison with the previous period', () {
    final txns = [
      tx(TxKind.expense, 100000, '2026-08-05'),
      tx(TxKind.expense, 280000, '2026-09-05'),
    ];

    test('reports the difference, signed', () {
      final d = changeVsPrevious(
        txns,
        Period.month,
        DateTime(2026, 9, 15),
        kind: TxKind.expense,
      );
      expect(d, 180000);
    });

    test('stays silent when the previous period predates the ledger', () {
      final d = changeVsPrevious(
        txns,
        Period.month,
        DateTime(2026, 8, 15),
        kind: TxKind.expense,
      );
      expect(d, isNull, reason: 'nothing before August to compare against');
    });

    test('stays silent when there is no prior data at all', () {
      final only = [tx(TxKind.expense, 100000, '2026-09-05')];
      expect(
        changeVsPrevious(
          only,
          Period.month,
          DateTime(2026, 9, 15),
          kind: TxKind.expense,
        ),
        isNull,
      );
    });
  });

  group('custom ranges', () {
    const r = (from: '2026-03-25', to: '2026-04-03'); // ten days, over DST

    test('count both ends, across a clock change', () {
      expect(daysIn(r), 10);
      expect(daysIn((from: '2026-09-04', to: '2026-09-04')), 1);
    });

    test('step by their own length', () {
      expect(shiftSpan(r, -1), (from: '2026-03-15', to: '2026-03-24'));
      expect(shiftSpan(r, 1), (from: '2026-04-04', to: '2026-04-13'));
    });

    test('chart as equal spans ending with the range', () {
      final s = spanSeries([tx(TxKind.expense, 500, '2026-03-20')], r, 2);
      expect(s.map((b) => b.range).toList(), [shiftSpan(r, -1), r]);
      expect(s.map((b) => b.expense).toList(), [500, 0]);
    });

    test('compare against the span before', () {
      final txns = [
        tx(TxKind.expense, 500, '2026-03-20'),
        tx(TxKind.expense, 800, '2026-03-30'),
      ];
      expect(
        changeBetween(txns, r, shiftSpan(r, -1), kind: TxKind.expense),
        300,
      );
    });
  });
}

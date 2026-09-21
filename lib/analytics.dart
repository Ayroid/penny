/// The maths, kept out of the screens that draw it.
///
/// Everything here is a plain function over a list of transactions: no
/// widgets, no BuildContext, no store. That is what makes the numbers testable
/// by calling them rather than by pumping a widget tree and reading pixels.
///
/// Transfers are excluded from every income and expense figure in this file.
/// Moving money from the bank to a wallet is not spending, and a ledger that
/// counts it as such overstates the month by exactly the amount withdrawn.
library;

import 'store.dart';

/// The three windows the overview switches between.
enum Period {
  day('Day'),
  week('Week'),
  month('Month');

  const Period(this.label);
  final String label;
}

/// An inclusive span of day keys. Strings rather than DateTimes because that
/// is how transactions store their day, and comparing them is a string
/// compare — zero-padded keys sort chronologically.
typedef Range = ({String from, String to});

Range rangeFor(Period period, DateTime anchor) {
  final d = DateTime(anchor.year, anchor.month, anchor.day);
  return switch (period) {
    Period.day => (from: dayKey(d), to: dayKey(d)),
    Period.week => (
      from: dayKey(startOfWeek(d)),
      to: dayKey(shiftDays(startOfWeek(d), 6)),
    ),
    Period.month => (
      from: dayKey(startOfMonth(d)),
      // Day zero of the next month is the last day of this one, whatever
      // its length and without a table of month lengths.
      to: dayKey(DateTime(d.year, d.month + 1, 0)),
    ),
  };
}

/// [anchor] moved [by] whole periods — what the arrows over a period do.
DateTime shiftAnchor(Period period, DateTime anchor, int by) =>
    switch (period) {
      Period.day => shiftDays(anchor, by),
      Period.week => shiftDays(anchor, by * 7),
      Period.month => shiftMonths(anchor, by),
    };

/// [range] shifted [by] whole periods — what the overview's month arrows do.
Range shiftRange(Period period, DateTime anchor, int by) =>
    rangeFor(period, shiftAnchor(period, anchor, by));

/// Whole days in [r], both ends counted. Measured in UTC so a daylight-saving
/// change inside the span cannot lose it an hour, and with it a day.
int daysIn(Range r) {
  final a = parseDay(r.from), b = parseDay(r.to);
  return DateTime.utc(
        b.year,
        b.month,
        b.day,
      ).difference(DateTime.utc(a.year, a.month, a.day)).inDays +
      1;
}

/// [r] moved [by] whole copies of itself — what the arrows over a hand-picked
/// range do. Ten days back from the 11th–20th is the 1st–10th.
Range shiftSpan(Range r, int by) {
  final n = daysIn(r) * by;
  return (
    from: dayKey(shiftDays(parseDay(r.from), n)),
    to: dayKey(shiftDays(parseDay(r.to), n)),
  );
}

bool inRange(Txn t, Range r) =>
    t.day.compareTo(r.from) >= 0 && t.day.compareTo(r.to) <= 0;

List<Txn> within(List<Txn> txns, Range r) => [
  for (final t in txns)
    if (inRange(t, r)) t,
];

/// What came in, what went out, and the difference.
typedef Totals = ({int income, int expense});

extension TotalsNet on Totals {
  /// Positive means the period ended up. Negative is not a failure state and
  /// is never drawn in red — see the design system.
  int get net => income - expense;
}

Totals totalsIn(List<Txn> txns, Range r) {
  var income = 0, expense = 0;
  for (final t in txns) {
    if (!inRange(t, r)) continue;
    switch (t.kind) {
      case TxKind.income:
        income += t.amountMinor;
      case TxKind.expense:
        expense += t.amountMinor;
      case TxKind.transfer:
        break; // Not spending, not earning.
    }
  }
  return (income: income, expense: expense);
}

/// Category id -> total, largest first. Empty categories are absent rather
/// than present with a zero, so a breakdown never lists things that did not
/// happen.
Map<String, int> byCategory(List<Txn> txns, Range r, TxKind kind) {
  assert(kind != TxKind.transfer, 'transfers have no meaningful breakdown');
  final out = <String, int>{};
  for (final t in txns) {
    if (t.kind != kind || !inRange(t, r)) continue;
    out[t.categoryId] = (out[t.categoryId] ?? 0) + t.amountMinor;
  }
  final sorted = out.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in sorted) e.key: e.value};
}

/// Day key -> amount spent, for the heatmap. Days with no spend are absent.
Map<String, int> spendByDay(List<Txn> txns, Range r) {
  final out = <String, int>{};
  for (final t in txns) {
    if (t.kind != TxKind.expense || !inRange(t, r)) continue;
    out[t.day] = (out[t.day] ?? 0) + t.amountMinor;
  }
  return out;
}

/// Day key -> that day's net: what came in, less what went out.
///
/// Transfers are neither, so they never move a day's net — the same rule the
/// totals and the breakdowns follow. Days where nothing happened are absent;
/// days that happened and came out even are present with a zero, because
/// "money moved and it balanced" is not the same as "nothing moved".
Map<String, int> netByDay(List<Txn> txns, Range r) {
  final out = <String, int>{};
  for (final t in txns) {
    if (t.kind == TxKind.transfer || !inRange(t, r)) continue;
    final delta = t.kind == TxKind.income ? t.amountMinor : -t.amountMinor;
    out[t.day] = (out[t.day] ?? 0) + delta;
  }
  return out;
}

/// One bar per period, oldest first, ending at [anchor]'s own period.
///
/// Used for the trend chart. Periods with nothing in them are included as
/// zeroes — a gap in a bar chart is information, and dropping it would make
/// two non-adjacent months look adjacent.
typedef Bucket = ({Range range, String label, int income, int expense});

List<Bucket> series(
  List<Txn> txns,
  Period period,
  DateTime anchor,
  int count,
) => [
  for (var i = count - 1; i >= 0; i--)
    _bucket(
      txns,
      shiftRange(period, anchor, -i),
      (from) => _labelFor(period, from),
    ),
];

/// The same, for a hand-picked range: [count] equal spans ending with [r].
List<Bucket> spanSeries(List<Txn> txns, Range r, int count) => [
  for (var i = count - 1; i >= 0; i--)
    _bucket(txns, shiftSpan(r, -i), (from) => '${from.day}/${from.month}'),
];

Bucket _bucket(List<Txn> txns, Range r, String Function(DateTime) label) {
  final t = totalsIn(txns, r);
  return (
    range: r,
    label: label(parseDay(r.from)),
    income: t.income,
    expense: t.expense,
  );
}

String _labelFor(Period period, DateTime d) => switch (period) {
  Period.day => '${d.day}',
  Period.week => '${d.day}/${d.month}',
  Period.month => _monthShort[d.month - 1],
};

const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// [minor] rounded up to a 1, 2 or 5 at its own magnitude — a chart axis that
/// tops out at ₹80K rather than at ₹78,431.
int niceAxisMax(int minor) {
  if (minor <= 0) return 100;
  var unit = 1;
  while (unit * 10 <= minor) {
    unit *= 10;
  }
  for (final step in [1, 2, 5]) {
    if (minor <= unit * step) return unit * step;
  }
  return unit * 10;
}

/// The same figure one period earlier, for "₹1,800 more than last month".
///
/// Returns null when there is nothing to compare against — no prior data at
/// all — so the caller can stay quiet rather than claim a 100% rise.
int? changeVsPrevious(
  List<Txn> txns,
  Period period,
  DateTime anchor, {
  required TxKind kind,
}) => changeBetween(
  txns,
  rangeFor(period, anchor),
  shiftRange(period, anchor, -1),
  kind: kind,
);

/// [changeVsPrevious] for any two windows — a hand-picked range against the
/// span of the same length before it.
int? changeBetween(
  List<Txn> txns,
  Range now,
  Range previous, {
  required TxKind kind,
}) {
  // Nothing recorded on or before the previous period means there is no
  // comparison to make — better silent than claiming a rise from zero.
  if (!txns.any((t) => t.day.compareTo(previous.to) <= 0)) return null;

  final a = totalsIn(txns, now), b = totalsIn(txns, previous);
  return kind == TxKind.income ? a.income - b.income : a.expense - b.expense;
}

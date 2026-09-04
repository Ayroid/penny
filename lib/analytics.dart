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

/// [range] shifted [by] whole periods — what the overview's month arrows do.
Range shiftRange(Period period, DateTime anchor, int by) => switch (period) {
      Period.day => rangeFor(period, shiftDays(anchor, by)),
      Period.week => rangeFor(period, shiftDays(anchor, by * 7)),
      Period.month => rangeFor(period, shiftMonths(anchor, by)),
    };

bool inRange(Txn t, Range r) =>
    t.day.compareTo(r.from) >= 0 && t.day.compareTo(r.to) <= 0;

List<Txn> within(List<Txn> txns, Range r) =>
    [for (final t in txns) if (inRange(t, r)) t];

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

/// One bar per period, oldest first, ending at [anchor]'s own period.
///
/// Used for the trend chart. Periods with nothing in them are included as
/// zeroes — a gap in a bar chart is information, and dropping it would make
/// two non-adjacent months look adjacent.
typedef Bucket = ({Range range, String label, int income, int expense});

List<Bucket> series(List<Txn> txns, Period period, DateTime anchor, int count) {
  final out = <Bucket>[];
  for (var i = count - 1; i >= 0; i--) {
    final r = shiftRange(period, anchor, -i);
    final t = totalsIn(txns, r);
    out.add((
      range: r,
      label: _labelFor(period, parseDay(r.from)),
      income: t.income,
      expense: t.expense,
    ));
  }
  return out;
}

String _labelFor(Period period, DateTime d) => switch (period) {
      Period.day => '${d.day}',
      Period.week => '${d.day}/${d.month}',
      Period.month => _monthShort[d.month - 1],
    };

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The same figure one period earlier, for "₹1,800 more than last month".
///
/// Returns null when there is nothing to compare against — no prior data at
/// all — so the caller can stay quiet rather than claim a 100% rise.
int? changeVsPrevious(List<Txn> txns, Period period, DateTime anchor,
    {required TxKind kind}) {
  final previous = shiftRange(period, anchor, -1);
  // Nothing recorded on or before the previous period means there is no
  // comparison to make — better silent than claiming a rise from zero.
  if (!txns.any((t) => t.day.compareTo(previous.to) <= 0)) return null;

  final now = totalsIn(txns, rangeFor(period, anchor));
  final then = totalsIn(txns, previous);
  final a = kind == TxKind.income ? now.income : now.expense;
  final b = kind == TxKind.income ? then.income : then.expense;
  return a - b;
}

// ── Quick add ───────────────────────────────────────────────────────────────

/// A transaction worth offering as a one-tap repeat.
///
/// A record rather than a class so equality is structural — two entries for the
/// same category, account, amount and note *are* the same suggestion, and that
/// falls out of the language instead of a hand-written `==`.
typedef QuickAdd = ({
  TxKind kind,
  int amountMinor,
  String categoryId,
  String accountId,
  String note,
});

/// The handful of entries most worth repeating, best first.
///
/// Ranked by how often a thing has been entered, then by how recently. Pure
/// recency puts a one-off ₹2,400 shopping trip ahead of the ₹20 chai bought
/// five times this week, and it is the chai that wants a shortcut.
///
/// Transfers are excluded: they need a destination account, so "the same
/// again" is a weaker claim and the sheet is the right place to make it.
List<QuickAdd> quickAdds(List<Txn> txns, {int scan = 60, int limit = 6}) {
  final count = <QuickAdd, int>{};
  final firstSeen = <QuickAdd, int>{};

  var i = 0;
  for (final t in txns.take(scan)) {
    if (t.kind == TxKind.transfer) continue;
    final key = (
      kind: t.kind,
      amountMinor: t.amountMinor,
      categoryId: t.categoryId,
      accountId: t.accountId,
      note: t.note,
    );
    count[key] = (count[key] ?? 0) + 1;
    firstSeen.putIfAbsent(key, () => i);
    i++;
  }

  final ranked = count.keys.toList()
    ..sort((a, b) {
      final byCount = count[b]!.compareTo(count[a]!);
      return byCount != 0 ? byCount : firstSeen[a]!.compareTo(firstSeen[b]!);
    });

  return ranked.take(limit).toList();
}

/// [suggestion] as a transaction, dated today.
Txn txnFrom(QuickAdd suggestion) => Txn(
      kind: suggestion.kind,
      amountMinor: suggestion.amountMinor,
      day: dayKey(today()),
      categoryId: suggestion.categoryId,
      accountId: suggestion.accountId,
      note: suggestion.note,
    );

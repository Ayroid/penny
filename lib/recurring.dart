import 'clock.dart';
import 'store.dart';

/// How many occurrences one pass will materialise.
///
/// A rule whose start day is years in the past — a hand-edited export, a
/// restored backup, a clock that jumped — would otherwise produce thousands of
/// rows in the frame the app opens in. The cap turns that into a catch-up over
/// several launches instead of one stall, because `lastRunDay` advances to the
/// last row actually produced.
///
/// ponytail: 400 is roughly a year of a weekly rule, or thirteen months of a
/// daily one. Raise it if a real backlog is ever seen taking more than one
/// launch to clear.
const maxPerPass = 400;

/// The [k]th occurrence of [rule], counting from zero at its start day.
///
/// Always derived from `startDay`, never from the previous occurrence. A
/// monthly rule on the 31st clamps to the 28th in February — and if March were
/// then computed from that 28th it would stay on the 28th forever. Counting
/// from the original day makes February the exception it should be.
DateTime occurrence(Rule rule, int k) {
  final start = parseDay(rule.startDay);
  return switch (rule.freq) {
    Freq.daily => shiftDays(start, k * rule.interval),
    Freq.weekly => shiftDays(start, k * rule.interval * 7),
    Freq.monthly => shiftMonths(start, k * rule.interval),
  };
}

/// Every transaction [rule] owes as of [now], oldest first.
///
/// Pure: no clock, no store, no plugin. The rules are the part most likely to
/// be wrong, so they are the part tested by calling rather than by pumping.
List<Txn> dueOccurrences(Rule rule, DateTime now) {
  if (!rule.active) return const [];

  final todayKey = dayKey(DateTime(now.year, now.month, now.day));
  final out = <Txn>[];

  for (var k = 0; k < 100000; k++) {
    final day = dayKey(occurrence(rule, k));

    if (day.compareTo(todayKey) > 0) break;
    if (rule.endDay != null && day.compareTo(rule.endDay!) > 0) break;
    // Already materialised. Keep counting rather than starting from the last
    // run, so monthly clamping stays anchored to the start day.
    if (rule.lastRunDay != null && day.compareTo(rule.lastRunDay!) <= 0) {
      continue;
    }

    out.add(
      Txn(
        kind: rule.kind,
        amountMinor: rule.amountMinor,
        day: day,
        categoryId: rule.categoryId,
        accountId: rule.accountId,
        toAccountId: rule.kind == TxKind.transfer ? rule.toAccountId : null,
        note: rule.note,
        ruleId: rule.id,
      ),
    );

    if (out.length >= maxPerPass) break;
  }

  return out;
}

/// Run every rule and add what it owes. Returns how many rows were created.
///
/// Called once when the store finishes loading and again when the app comes
/// back to the foreground — there is no background isolate and no server, so a
/// rule that came due while the app was closed appears the next time it opens.
/// Idempotent: running it twice in a row adds nothing the second time.
int materialiseDue(PennyStore store, {DateTime? now}) {
  final at = now ?? clock();
  var added = 0;

  for (final rule in store.rules) {
    final due = dueOccurrences(rule, at);
    if (due.isEmpty) continue;

    for (final t in due) {
      store.txns.add(t);
    }
    rule.lastRunDay = due.last.day;
    added += due.length;
  }

  if (added > 0) store.touch();
  return added;
}

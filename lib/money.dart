/// Money, as an integer number of paise.
///
/// Never a double. `0.1 + 0.2 != 0.3` in binary floating point, and a ledger
/// that drifts by a paise per hundred entries is worse than no ledger at all.
/// Nothing in Penny converts an amount to `double` — not to store it, not to
/// total it, not to draw it. Charts scale integers to pixels at the last
/// moment, which is the only place a fraction is allowed to appear.
library;

const rupee = '₹';

/// The largest amount the keypad will build: ₹9,99,99,999.99.
///
/// A cap rather than an unbounded int because the entry keypad appends digits
/// on every tap, and a leaning-on-the-key accident should stop rather than run
/// to an amount no one can read. Ten crore is comfortably past any personal
/// transaction and still far from the 64-bit ceiling.
const maxMinor = 9999999999;

/// Indian digit grouping: the last three digits, then pairs.
///
/// `1234567` -> `12,34,567`. This is not a formatting preference — `₹1,20,450`
/// and `₹120,450` are the difference between an app that reads as local and
/// one that reads as imported. Hand-rolled rather than pulling in `intl` and
/// its locale data for ten lines of string work.
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);

  final parts = <String>[];
  var i = head.length;
  while (i > 2) {
    parts.insert(0, head.substring(i - 2, i));
    i -= 2;
  }
  if (i > 0) parts.insert(0, head.substring(0, i));

  return '${parts.join(',')},$tail';
}

/// `12045000` -> `₹1,20,450.00`.
///
/// [signed] puts an explicit `+` on a positive amount, for a net figure where
/// the direction is the point. A negative amount always shows its `-`.
String rupees(int minor, {bool signed = false}) {
  final negative = minor < 0;
  final abs = minor.abs();
  final sign = negative
      ? '-'
      : signed
          ? '+'
          : '';
  final paise = (abs % 100).toString().padLeft(2, '0');
  return '$sign$rupee${groupIndian('${abs ~/ 100}')}.$paise';
}

/// The same, without the paise — for axis labels and dense rows where two
/// decimal places on every line is noise.
String rupeesWhole(int minor, {bool signed = false}) {
  final negative = minor < 0;
  final abs = minor.abs();
  final sign = negative
      ? '-'
      : signed
          ? '+'
          : '';
  return '$sign$rupee${groupIndian('${abs ~/ 100}')}';
}

// ── Keypad arithmetic ───────────────────────────────────────────────────────
// The entry sheet builds an amount paise-first, the way a bank app does:
// tapping 1,2,3,4,5,6 reads ₹1,234.56. There is no string to parse because a
// string is never produced, which takes locale, decimal separators, thousands
// separators and rounding out of the money path entirely.

/// Append one digit, or refuse if that would exceed [maxMinor].
int appendDigit(int minor, int digit) {
  assert(digit >= 0 && digit <= 9);
  final next = minor * 10 + digit;
  return next > maxMinor ? minor : next;
}

/// Remove the last digit. Backspacing an empty amount stays empty.
int dropDigit(int minor) => minor ~/ 10;

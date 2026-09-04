/// Money, as an integer number of paise.
///
/// Never a double. `0.1 + 0.2 != 0.3` in binary floating point, and a ledger
/// that drifts by a paise per hundred entries is worse than no ledger at all.
/// Nothing in Penny converts an amount to `double` — not to store it, not to
/// total it, not to draw it. Charts scale integers to pixels at the last
/// moment, which is the only place a fraction is allowed to appear.
library;

import 'package:flutter/services.dart';

const rupee = '₹';

/// The largest amount Penny will accept: ₹9,99,99,999.99.
///
/// A cap rather than an unbounded int, because the field is fed by a keyboard
/// and a paste or a leant-on key should stop rather than run to an amount no
/// one can read. Ten crore is comfortably past any personal transaction and
/// still far from the 64-bit ceiling.
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

// ── Reading an amount back ──────────────────────────────────────────────────
// The amount is typed on the platform's own numeric keyboard, so unlike the
// rest of this file it does have to come in as a string once. It is parsed
// exactly here and nowhere else, and it becomes an int immediately.

/// `"1,234.56"` -> `123456` paise. Null if [input] is not an amount.
///
/// Accepts the grouping commas the keyboard offers and a partial decimal
/// (`"12."` is 1200 paise) so the field stays usable mid-typing. Digits past
/// two decimal places are **truncated, not rounded** — the input formatter
/// stops them being typed at all, and silently rounding someone's number up is
/// worse than ignoring what they could not have entered.
int? parseRupees(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll(' ', '');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^\d*\.?\d*$').hasMatch(cleaned)) return null;

  final parts = cleaned.split('.');
  if (parts.length > 2) return null;

  // Length first, then value. `int.tryParse` gives up past 19 digits and
  // returns null, which would make a 30-digit paste read as garbage rather
  // than as "too big" — and the multiply below would overflow into a negative
  // amount for anything shorter that still exceeds the cap.
  if (parts[0].length > 9) return maxMinor;
  final whole = parts[0].isEmpty ? 0 : int.tryParse(parts[0]);
  if (whole == null) return null;
  if (whole > maxMinor ~/ 100) return maxMinor;

  var paise = 0;
  if (parts.length == 2 && parts[1].isNotEmpty) {
    paise = int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0;
  }

  final total = whole * 100 + paise;
  return total > maxMinor ? maxMinor : total;
}

/// The editable text for [minor], for seeding a field when editing a row.
/// Drops a trailing `.00` — nobody wants to backspace over it to retype.
String amountFieldText(int minor) {
  if (minor == 0) return '';
  final paise = minor % 100;
  final whole = minor ~/ 100;
  return paise == 0 ? '$whole' : '$whole.${paise.toString().padLeft(2, '0')}';
}

/// Digits, one decimal point, at most two places after it.
///
/// Applied to the whole candidate string rather than character by character,
/// so a paste of "12.345" is rejected outright instead of being let through a
/// digit at a time.
final amountInputFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) =>
      RegExp(r'^\d{0,9}(\.\d{0,2})?$').hasMatch(newValue.text)
      ? newValue
      : oldValue,
);

/// What an amount looks like when the balance is hidden.
///
/// A fixed width rather than one dot per digit: the length of the mask would
/// otherwise leak the size of the number, which is most of what someone was
/// hiding.
const maskedAmount = '••••••';

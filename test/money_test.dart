import 'package:flutter_test/flutter_test.dart';
import 'package:penny/money.dart';

void main() {
  group('Indian grouping', () {
    test('groups the last three digits, then pairs', () {
      expect(groupIndian('1'), '1');
      expect(groupIndian('12'), '12');
      expect(groupIndian('123'), '123');
      expect(groupIndian('1234'), '1,234');
      expect(groupIndian('12345'), '12,345');
      expect(groupIndian('123456'), '1,23,456');
      expect(groupIndian('1234567'), '12,34,567');
      expect(groupIndian('12345678'), '1,23,45,678');
      expect(groupIndian('123456789'), '12,34,56,789');
    });

    test('a lakh is not a hundred thousand', () {
      // The whole reason this function exists rather than a comma every three.
      expect(groupIndian('100000'), '1,00,000');
      expect(groupIndian('10000000'), '1,00,00,000');
    });
  });

  group('formatting', () {
    test('the plan\'s worked example', () {
      expect(rupees(12045000), '₹1,20,450.00');
    });

    test('paise are always two places', () {
      expect(rupees(0), '₹0.00');
      expect(rupees(5), '₹0.05');
      expect(rupees(50), '₹0.50');
      expect(rupees(105), '₹1.05');
      expect(rupees(199), '₹1.99');
    });

    test('negatives carry their sign, positives only when asked', () {
      expect(rupees(45000), '₹450.00');
      expect(rupees(45000, signed: true), '+₹450.00');
      expect(rupees(-45000), '-₹450.00');
      expect(rupees(-45000, signed: true), '-₹450.00');
      expect(rupees(0, signed: true), '+₹0.00');
    });

    test('the whole-rupee form drops the paise without rounding up', () {
      expect(rupeesWhole(12045099), '₹1,20,450');
      expect(rupeesWhole(-45099), '-₹450');
      expect(rupeesWhole(45000, signed: true), '+₹450');
    });
  });

  group('parsing what was typed', () {
    test('a typed amount is rupees, not paise', () {
      // The keypad this replaced built paise-first, so 5-0-0 meant ₹5.00.
      // A field prefixed with ₹ cannot work that way: 500 is five hundred,
      // and the paise only appear once a decimal point is typed.
      expect(rupees(parseRupees('500')!), '₹500.00');
      expect(rupees(parseRupees('5.00')!), '₹5.00');
      expect(rupees(parseRupees('5')!), '₹5.00');
    });

    test('plain rupees', () {
      expect(parseRupees('450'), 45000);
      expect(parseRupees('0'), 0);
      expect(parseRupees('1'), 100);
    });

    test('rupees and paise', () {
      expect(parseRupees('450.50'), 45050);
      expect(parseRupees('450.5'), 45050);
      expect(parseRupees('0.05'), 5);
      expect(parseRupees('1234.56'), 123456);
    });

    test('the keyboard\'s grouping commas are accepted', () {
      // The system numeric keyboard offers a comma key, and people paste
      // amounts with grouping in them.
      expect(parseRupees('1,20,450.00'), 12045000);
      expect(parseRupees('1,234.56'), 123456);
    });

    test('a half-typed decimal still reads', () {
      // Otherwise the Add button flickers off the moment the point is typed.
      expect(parseRupees('12.'), 1200);
      expect(parseRupees('.5'), 50);
      expect(parseRupees('.'), 0);
    });

    test('nothing typed is not zero, it is nothing', () {
      expect(parseRupees(''), isNull);
      expect(parseRupees('   '), isNull);
    });

    test('garbage is rejected rather than guessed at', () {
      expect(parseRupees('abc'), isNull);
      expect(parseRupees('12.34.56'), isNull);
      expect(parseRupees('-450'), isNull);
      expect(parseRupees('1e5'), isNull);
      expect(parseRupees('₹450'), isNull);
    });

    test('extra decimal places truncate, never round up', () {
      // Rounding someone's amount up is worse than ignoring digits the
      // formatter would not have let them type.
      expect(parseRupees('1.999'), 199);
      expect(parseRupees('0.009'), 0);
    });

    test('an absurd amount clamps instead of overflowing', () {
      expect(parseRupees('999999999999999'), maxMinor);
      expect(parseRupees('99999999.99'), maxMinor);
      expect(parseRupees(''.padRight(30, '9')), maxMinor);
    });

    test('round-trips through the field text', () {
      for (final minor in [0, 5, 100, 45050, 12045000, maxMinor]) {
        final text = amountFieldText(minor);
        expect(parseRupees(text) ?? 0, minor, reason: 'via "$text"');
      }
    });

    test('field text drops a pointless .00', () {
      expect(amountFieldText(45000), '450');
      expect(amountFieldText(45050), '450.50');
      expect(amountFieldText(5), '0.05');
      expect(amountFieldText(0), '');
    });
  });

  group('the input formatter', () {
    String filter(String current, String next) => amountInputFormatter
        .formatEditUpdate(
          TextEditingValue(text: current),
          TextEditingValue(text: next),
        )
        .text;

    test('lets a normal amount through', () {
      expect(filter('', '4'), '4');
      expect(filter('45', '450'), '450');
      expect(filter('450', '450.'), '450.');
      expect(filter('450.', '450.5'), '450.5');
      expect(filter('450.5', '450.50'), '450.50');
    });

    test('refuses a third decimal place', () {
      expect(filter('450.50', '450.500'), '450.50');
    });

    test('refuses a second decimal point, letters and signs', () {
      expect(filter('450.5', '450.5.'), '450.5');
      expect(filter('450', '450a'), '450');
      expect(filter('450', '-450'), '450');
    });

    test('refuses a paste that is not an amount', () {
      expect(filter('', '12.345'), '');
      expect(filter('', '1,234'), '');
    });
  });
}

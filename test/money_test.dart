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

  group('keypad arithmetic', () {
    test('tapping 1,2,3,4,5,6 builds ₹1,234.56', () {
      var m = 0;
      for (final d in [1, 2, 3, 4, 5, 6]) {
        m = appendDigit(m, d);
      }
      expect(m, 123456);
      expect(rupees(m), '₹1,234.56');
    });

    test('the first digits are paise', () {
      var m = appendDigit(0, 5);
      expect(rupees(m), '₹0.05');
      m = appendDigit(m, 0);
      expect(rupees(m), '₹0.50');
      m = appendDigit(m, 0);
      expect(rupees(m), '₹5.00');
    });

    test('backspace removes one digit and bottoms out at zero', () {
      var m = 123456;
      m = dropDigit(m);
      expect(m, 12345);
      for (var i = 0; i < 10; i++) {
        m = dropDigit(m);
      }
      expect(m, 0);
      expect(dropDigit(0), 0);
    });

    test('leaning on a key stops at the cap instead of running away', () {
      var m = 0;
      for (var i = 0; i < 40; i++) {
        m = appendDigit(m, 9);
      }
      expect(m, maxMinor);
      expect(rupees(m), '₹9,99,99,999.99');
    });

    test('a leading zero does not grow the amount', () {
      var m = 0;
      for (var i = 0; i < 5; i++) {
        m = appendDigit(m, 0);
      }
      expect(m, 0);
      expect(rupees(m), '₹0.00');
    });
  });
}

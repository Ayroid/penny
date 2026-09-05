import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penny/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PennyStore> loaded() async {
  final s = PennyStore();
  await s.load();
  return s;
}

Future<PennyStore> seeded() async {
  final s = await loaded();
  s.seedDefaults();
  return s;
}

/// An export with its timestamp removed, so two can be compared for content.
Map<String, dynamic> data(String raw) =>
    Map<String, dynamic>.from(jsonDecode(raw) as Map)..remove('exportedAt');

String cat(PennyStore s, String name) =>
    s.categories.firstWhere((c) => c.name == name).id;
String acc(PennyStore s, String name) =>
    s.accounts.firstWhere((a) => a.name == name).id;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('day keys', () {
    test('are zero-padded, so lexical order is chronological', () {
      expect(dayKey(DateTime(2026, 9, 4)), '2026-09-04');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
      final days = ['2026-10-01', '2026-09-04', '2026-09-30']..sort();
      expect(days, ['2026-09-04', '2026-09-30', '2026-10-01']);
    });

    test('round-trip through parseDay', () {
      final d = DateTime(2026, 2, 29);
      expect(parseDay(dayKey(d)), d);
    });

    test('day arithmetic crosses month and year ends', () {
      expect(dayKey(shiftDays(DateTime(2026, 1, 31), 1)), '2026-02-01');
      expect(dayKey(shiftDays(DateTime(2026, 12, 31), 1)), '2027-01-01');
      expect(dayKey(shiftDays(DateTime(2026, 3, 1), -1)), '2026-02-28');
    });

    test('month arithmetic clamps instead of rolling over', () {
      // A rent rule set on the 31st must land on the 28th in February, not
      // skip into March.
      expect(dayKey(shiftMonths(DateTime(2026, 1, 31), 1)), '2026-02-28');
      expect(dayKey(shiftMonths(DateTime(2024, 1, 31), 1)), '2024-02-29');
      expect(dayKey(shiftMonths(DateTime(2026, 3, 31), 1)), '2026-04-30');
      expect(dayKey(shiftMonths(DateTime(2026, 1, 15), 13)), '2027-02-15');
    });

    test('the week starts on Monday', () {
      expect(dayKey(startOfWeek(DateTime(2026, 9, 4))), '2026-08-31');
      expect(dayKey(startOfWeek(DateTime(2026, 8, 31))), '2026-08-31');
      expect(dayKey(startOfWeek(DateTime(2026, 9, 6))), '2026-08-31');
    });
  });

  test('ids never collide, even generated in a tight loop', () {
    // Recurring rules materialise a run of rows in one pass; a bare
    // microsecond timestamp can repeat inside that loop.
    final ids = {for (var i = 0; i < 5000; i++) newId()};
    expect(ids, hasLength(5000));
  });

  group('seeding', () {
    test('a new ledger arrives usable', () async {
      final s = await seeded();
      expect(s.accounts.map((a) => a.name), ['Cash', 'Bank', 'Wallet']);
      expect(s.categoriesOf(TxKind.expense), isNotEmpty);
      expect(s.categoriesOf(TxKind.income), isNotEmpty);
      expect(s.totalBalance, 0);
    });

    test('seeding twice does not duplicate', () async {
      final s = await seeded();
      final n = s.categories.length;
      s.seedDefaults();
      expect(s.categories, hasLength(n));
    });
  });

  group('balances', () {
    test('income adds and expense subtracts', () async {
      final s = await seeded();
      final bank = acc(s, 'Bank');
      s.addTxn(
        Txn(
          kind: TxKind.income,
          amountMinor: 8000000,
          day: '2026-09-01',
          categoryId: cat(s, 'Salary'),
          accountId: bank,
        ),
      );
      s.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 45000,
          day: '2026-09-02',
          categoryId: cat(s, 'Food & Drink'),
          accountId: bank,
        ),
      );

      expect(s.balanceOf(bank), 8000000 - 45000);
      expect(s.totalBalance, 7955000);
    });

    test('an opening balance is the starting point', () async {
      final s = await seeded();
      final cash = s.accountById(acc(s, 'Cash'))!;
      cash.openingBalanceMinor = 500000;
      s.touch();
      expect(s.balanceOf(cash.id), 500000);
      expect(s.totalBalance, 500000);
    });

    test('an account can open in the red', () async {
      final s = await seeded();
      final card = s.accountById(acc(s, 'Wallet'))!;
      card.openingBalanceMinor = -250000;
      s.touch();
      expect(s.balanceOf(card.id), -250000);
    });
  });

  group('transfers — the reason the ledger stays honest', () {
    test('move money between accounts without touching the totals', () async {
      final s = await seeded();
      final bank = acc(s, 'Bank'), cash = acc(s, 'Cash');
      s.accountById(bank)!.openingBalanceMinor = 1000000;
      s.addTxn(
        Txn(
          kind: TxKind.transfer,
          amountMinor: 500000,
          day: '2026-09-03',
          categoryId: cat(s, 'Other'),
          accountId: bank,
          toAccountId: cash,
        ),
      );

      expect(s.balanceOf(bank), 500000, reason: 'money left the bank');
      expect(s.balanceOf(cash), 500000, reason: 'and arrived in cash');
      expect(
        s.totalBalance,
        1000000,
        reason: 'a withdrawal does not change what you have',
      );
    });

    test('a transfer is neither income nor expense', () async {
      final s = await seeded();
      s.addTxn(
        Txn(
          kind: TxKind.transfer,
          amountMinor: 500000,
          day: '2026-09-03',
          categoryId: cat(s, 'Other'),
          accountId: acc(s, 'Bank'),
          toAccountId: acc(s, 'Cash'),
        ),
      );

      final income = s.txns.where((t) => t.kind == TxKind.income);
      final expense = s.txns.where((t) => t.kind == TxKind.expense);
      expect(income, isEmpty);
      expect(
        expense,
        isEmpty,
        reason: 'a cash withdrawal must not read as spending',
      );
    });
  });

  group('ordering', () {
    test('newest day first, and stable within a day', () async {
      final s = await seeded();
      final a = acc(s, 'Cash'), c = cat(s, 'Other');
      Txn t(String day, String note) => Txn(
        kind: TxKind.expense,
        amountMinor: 100,
        day: day,
        categoryId: c,
        accountId: a,
        note: note,
      );

      s.addTxn(t('2026-09-01', 'first'));
      s.addTxn(t('2026-09-03', 'third'));
      s.addTxn(t('2026-09-02', 'second'));
      expect(s.txns.map((x) => x.note), ['third', 'second', 'first']);
    });

    test('editing a day re-sorts', () async {
      final s = await seeded();
      final a = acc(s, 'Cash'), cc = cat(s, 'Other');
      s.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 100,
          day: '2026-09-01',
          categoryId: cc,
          accountId: a,
          note: 'moved',
        ),
      );
      s.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 100,
          day: '2026-09-02',
          categoryId: cc,
          accountId: a,
          note: 'other',
        ),
      );
      expect(s.txns.first.note, 'other');

      s.txns.firstWhere((t) => t.note == 'moved').day = '2026-09-05';
      s.touch();
      expect(s.txns.first.note, 'moved');
    });
  });

  test('remove returns the index so undo can put it back', () async {
    final s = await seeded();
    final a = acc(s, 'Cash'), c = cat(s, 'Other');
    for (final d in ['2026-09-01', '2026-09-02', '2026-09-03']) {
      s.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 100,
          day: d,
          categoryId: c,
          accountId: a,
          note: d,
        ),
      );
    }
    final victim = s.txns[1];
    final i = s.removeTxn(victim);
    expect(i, 1);
    expect(s.txns, hasLength(2));
    s.insertTxnAt(i, victim);
    expect(s.txns.map((t) => t.note), [
      '2026-09-03',
      '2026-09-02',
      '2026-09-01',
    ]);
  });

  group('backup', () {
    test('export then import is a round trip', () async {
      final s = await seeded();
      s.addTxn(
        Txn(
          kind: TxKind.income,
          amountMinor: 8000000,
          day: '2026-09-01',
          categoryId: cat(s, 'Salary'),
          accountId: acc(s, 'Bank'),
          note: 'September',
        ),
      );
      s.addTxn(
        Txn(
          kind: TxKind.transfer,
          amountMinor: 500000,
          day: '2026-09-02',
          categoryId: cat(s, 'Other'),
          accountId: acc(s, 'Bank'),
          toAccountId: acc(s, 'Cash'),
        ),
      );
      final before = s.exportJson();
      final balance = s.totalBalance;

      final fresh = await loaded();
      expect(fresh.importJson(before), isTrue);
      expect(fresh.txns, hasLength(2));
      expect(fresh.totalBalance, balance);
      expect(
        fresh.txns.firstWhere((t) => t.note == 'September').amountMinor,
        8000000,
      );
      expect(fresh.txns.any((t) => t.kind == TxKind.transfer), isTrue);
    });

    test('a malformed file leaves existing data untouched', () async {
      final s = await seeded();
      s.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 45000,
          day: '2026-09-01',
          categoryId: cat(s, 'Food & Drink'),
          accountId: acc(s, 'Cash'),
        ),
      );
      final before = s.exportJson();

      expect(s.importJson('this is not json'), isFalse);
      expect(s.importJson('{"txns": "not a list"}'), isFalse);
      // Compared without `exportedAt`, which is a fresh timestamp per call.
      expect(
        data(s.exportJson()),
        data(before),
        reason: 'a rejected import must not have cleared anything',
      );
    });

    test('a hand-edited negative amount cannot invert a balance', () async {
      final s = await loaded();
      final ok = s.importJson('''
        {"accounts":[{"id":"a1","name":"Cash","opening":0}],
         "categories":[{"id":"c1","name":"Other","kind":"expense"}],
         "txns":[{"id":"t1","kind":"expense","amount":-999999,"day":"2026-09-01",
                  "category":"c1","account":"a1"}]}
      ''');
      expect(ok, isTrue);
      expect(s.txns.single.amountMinor, 0);
      expect(s.balanceOf('a1'), 0);
    });

    test(
      'a row naming a category that does not exist is adopted, not lost',
      () async {
        final s = await loaded();
        s.importJson('''
        {"accounts":[{"id":"a1","name":"Cash","opening":0}],
         "categories":[],
         "txns":[{"id":"t1","kind":"expense","amount":45000,"day":"2026-09-01",
                  "category":"ghost","account":"ghost"}]}
      ''');
        expect(s.txns, hasLength(1), reason: 'the money must not vanish');
        expect(s.categoryById(s.txns.single.categoryId)?.name, 'Uncategorised');
        expect(s.txns.single.accountId, 'a1');
        expect(s.balanceOf('a1'), -45000);
      },
    );

    test('a transfer with nowhere to go degrades to an expense', () async {
      final s = await loaded();
      s.importJson('''
        {"accounts":[{"id":"a1","name":"Cash","opening":100000}],
         "categories":[{"id":"c1","name":"Other","kind":"expense"}],
         "txns":[{"id":"t1","kind":"transfer","amount":50000,"day":"2026-09-01",
                  "category":"c1","account":"a1","toAccount":"ghost"}]}
      ''');
      // Left as a transfer it would move money out of the ledger entirely.
      expect(s.txns.single.kind, TxKind.expense);
      expect(s.txns.single.toAccountId, isNull);
      expect(s.balanceOf('a1'), 50000);
    });

    test('an empty document is a valid empty ledger', () async {
      final s = await loaded();
      expect(s.importJson('{}'), isTrue);
      expect(s.txns, isEmpty);
      expect(
        s.accounts,
        hasLength(1),
        reason: 'there is always somewhere to put money',
      );
    });
  });

  group('persistence', () {
    test('a saved ledger comes back on the next launch', () async {
      final s = await seeded();
      s.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 45000,
          day: '2026-09-01',
          categoryId: cat(s, 'Food & Drink'),
          accountId: acc(s, 'Cash'),
          note: 'lunch',
        ),
      );
      await Future<void>.delayed(Duration.zero); // let the write land

      final next = await loaded();
      expect(next.txns.single.note, 'lunch');
      expect(next.totalBalance, -45000);
    });

    test(
      'corrupt stored data starts empty rather than bricking launch',
      () async {
        SharedPreferences.setMockInitialValues({'ledger': '{{{not json'});
        final s = await loaded();
        expect(s.loaded, isTrue);
        expect(s.txns, isEmpty);
      },
    );

    test('a moment is claimed once per day', () async {
      final s = await loaded();
      expect(s.claimMoment('first-entry'), isTrue);
      expect(s.claimMoment('first-entry'), isFalse);
      expect(s.claimMoment('something-else'), isTrue);
    });
  });

  group('quick entries', () {
    Future<(PennyStore, Shortcut)> withPin() async {
      final s = await seeded();
      final pin = Shortcut(
        kind: TxKind.expense,
        amountMinor: 2000,
        categoryId: cat(s, 'Food & Drink'),
        accountId: acc(s, 'Cash'),
        note: 'chai',
      );
      s.addShortcut(pin);
      return (s, pin);
    }

    test('a shortcut becomes a transaction dated today', () async {
      final (s, pin) = await withPin();
      final t = pin.toTxn();
      expect(t.day, dayKey(today()));
      expect(t.amountMinor, 2000);
      expect(t.note, 'chai');
      expect(t.kind, TxKind.expense);
      expect(s.shortcuts, hasLength(1));
    });

    test('pinning the same thing twice adds nothing', () async {
      final (s, pin) = await withPin();
      final again = Shortcut(
        kind: pin.kind,
        amountMinor: pin.amountMinor,
        categoryId: pin.categoryId,
        accountId: pin.accountId,
        note: pin.note,
      );
      expect(s.addShortcut(again), isFalse);
      expect(s.shortcuts, hasLength(1));
    });

    test(
      'the same amount from a different account is a different pin',
      () async {
        final (s, pin) = await withPin();
        expect(
          s.addShortcut(
            Shortcut(
              kind: pin.kind,
              amountMinor: pin.amountMinor,
              categoryId: pin.categoryId,
              accountId: acc(s, 'Bank'),
              note: pin.note,
            ),
          ),
          isTrue,
        );
        expect(s.shortcuts, hasLength(2));
      },
    );

    test('a transaction finds the pin that matches it', () async {
      final (s, pin) = await withPin();
      final matching = pin.toTxn();
      expect(s.shortcutFor(matching)?.id, pin.id);

      final different = Txn(
        kind: TxKind.expense,
        amountMinor: 9999,
        day: dayKey(today()),
        categoryId: pin.categoryId,
        accountId: pin.accountId,
      );
      expect(s.shortcutFor(different), isNull);
    });

    test('pins survive a save and reload', () async {
      await withPin();
      await Future<void>.delayed(Duration.zero);

      final next = await loaded();
      expect(next.shortcuts, hasLength(1));
      expect(next.shortcuts.single.note, 'chai');
      expect(next.shortcuts.single.amountMinor, 2000);
    });

    test('a pin survives export and import', () async {
      final (s, _) = await withPin();
      final fresh = await loaded();
      expect(fresh.importJson(s.exportJson()), isTrue);
      expect(fresh.shortcuts.single.note, 'chai');
    });

    test(
      'a pin pointing at a deleted account is dropped, not repointed',
      () async {
        // Adopting it would spend from the wrong account on a single tap — a
        // shortcut is a convenience, not a record worth rescuing.
        final s = await loaded();
        s.importJson('''
        {"accounts":[{"id":"a1","name":"Cash","opening":0}],
         "categories":[{"id":"c1","name":"Food","kind":"expense"}],
         "txns":[],
         "shortcuts":[
           {"id":"s1","kind":"expense","amount":2000,"category":"c1","account":"a1"},
           {"id":"s2","kind":"expense","amount":2000,"category":"c1","account":"ghost"}
         ]}
      ''');
        expect(s.shortcuts.map((x) => x.id), ['s1']);
      },
    );
  });

  group('renaming seeded defaults', () {
    test('an untouched Card account becomes Wallet', () async {
      final s = await loaded();
      s.importJson('''
        {"accounts":[{"id":"a1","name":"Card","icon":"credit-card","opening":0}],
         "categories":[],"txns":[]}
      ''');
      expect(s.accounts.single.name, 'Wallet');
      expect(s.accounts.single.icon, 'wallet');
    });

    test('an account the person renamed is left alone', () async {
      final s = await loaded();
      s.importJson('''
        {"accounts":[{"id":"a1","name":"HDFC Card","icon":"credit-card","opening":0}],
         "categories":[],"txns":[]}
      ''');
      expect(s.accounts.single.name, 'HDFC Card');
    });

    test('an account whose icon was changed is left alone', () async {
      // Changing the icon is a decision too, and overwriting it would be
      // undoing something the person did on purpose.
      final s = await loaded();
      s.importJson('''
        {"accounts":[{"id":"a1","name":"Card","icon":"gem","opening":0}],
         "categories":[],"txns":[]}
      ''');
      expect(s.accounts.single.name, 'Card');
      expect(s.accounts.single.icon, 'gem');
    });
  });
}

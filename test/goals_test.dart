import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/goals_screen.dart';
import 'package:penny/sheets.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Money put aside is money moved: a transfer out of a real account and into
/// the goals account, tagged with the goal. So what can go wrong is a balance
/// that does not add up, a goal that disagrees with the rows behind it, and a
/// celebration that replays.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Money in every account money can come out of. Putting aside is capped at
  /// what the account actually holds, so a store with nothing in it can no
  /// longer fund anything.
  void fund(PennyStore store, [int minor = 1000000]) {
    for (final a in store.accounts) {
      if (!a.forGoals) a.openingBalanceMinor = minor;
    }
  }

  Future<PennyStore> emptyStore() async {
    final store = PennyStore();
    await store.load();
    store.seedDefaults();
    fund(store);
    return store;
  }

  Goal phone() => Goal(name: 'Phone', targetMinor: 100000);

  group('putting money aside', () {
    test('moves it out of the account it came from', () async {
      final store = await emptyStore();
      final cash = store.accounts.first;
      cash.openingBalanceMinor = 500000;
      final g = phone();
      store.addGoal(g);

      final before = store.totalBalance;
      store.putAside(g, 30000, cash.id);

      expect(
        store.balanceOf(cash.id),
        470000,
        reason: 'the account is lighter',
      );
      expect(store.balanceOf(store.goalsAccount().id), 30000);
      expect(
        store.totalBalance,
        before,
        reason: 'a transfer moves money, it does not spend it',
      );
      expect(store.totalSetAside, 30000);
    });

    test('shows up in the ledger as an ordinary transfer', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 30000, store.accounts.first.id);

      final row = store.txns.single;
      expect(row.kind, TxKind.transfer);
      expect(row.toAccountId, store.goalsAccount().id);
      expect(row.goalId, g.id);
      expect(row.note, 'Phone', reason: 'the row says what it was for');
    });

    test('the goals account is made on first use, not seeded', () async {
      final store = await emptyStore();
      expect(store.goalsAccountOrNull, isNull);
      expect(store.accounts, hasLength(3));

      final g = phone();
      store.addGoal(g);
      store.putAside(g, 1000, store.accounts.first.id);
      expect(store.goalsAccountOrNull, isNotNull);
      expect(store.accounts, hasLength(4));
    });

    test('what the goal holds is summed from those rows', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 25000, store.accounts.first.id);
      store.putAside(g, 15000, store.accounts[1].id);

      final status = store.statusOf(g);
      expect(status.saved, 40000);
      expect(status.remaining, 60000);
      expect(status.progress, 0.4);
      expect(status.reached, isFalse);
    });

    test(
      'deleting the row in the ledger takes it back out of the goal',
      () async {
        final store = await emptyStore();
        final g = phone();
        store.addGoal(g);
        final row = store.putAside(g, 40000, store.accounts.first.id)!;
        expect(store.statusOf(g).saved, 40000);

        store.removeTxn(row);
        expect(
          store.statusOf(g).saved,
          0,
          reason: 'the rows are the record; there is nothing to reconcile',
        );
      },
    );

    test('a goal over its target is full, not 130% full', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 130000, store.accounts.first.id);

      final status = store.statusOf(g);
      expect(
        status.saved,
        100000,
        reason: 'only what the goal still needed moved',
      );
      expect(status.progress, 1.0);
      expect(status.remaining, 0);
      expect(status.reached, isTrue);
    });

    test('never more than the account actually holds', () async {
      final store = await emptyStore();
      final cash = store.accounts.first..openingBalanceMinor = 20000;
      final g = phone();
      store.addGoal(g);

      expect(store.putAside(g, 50000, cash.id), isNull);
      expect(store.statusOf(g).saved, 0, reason: 'nothing moved at all');
      expect(store.txns, isEmpty);

      store.putAside(g, 20000, cash.id);
      expect(store.balanceOf(cash.id), 0);
      expect(
        store.putAside(g, 1, cash.id),
        isNull,
        reason: 'an empty account has nothing left to give',
      );
    });

    test('a target of zero is a broken file, not a finished goal', () async {
      final store = await emptyStore();
      final g = Goal(name: 'Nothing', targetMinor: 0);
      store.addGoal(g);
      expect(store.statusOf(g).reached, isFalse);
    });
  });

  group('taking it back out', () {
    test('lands in the account you chose', () async {
      final store = await emptyStore();
      final cash = store.accounts.first;
      // Empty, so the balance after is the amount that came back and nothing
      // else.
      final bank = store.accounts[1]..openingBalanceMinor = 0;
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 50000, cash.id);

      store.takeOut(g, 20000, bank.id);
      expect(store.statusOf(g).saved, 30000);
      expect(store.balanceOf(bank.id), 20000);
      expect(store.balanceOf(store.goalsAccount().id), 30000);
    });

    test('cannot hand back money that was never put in', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 30000, store.accounts.first.id);

      store.takeOut(g, 50000, store.accounts.first.id);
      expect(store.statusOf(g).saved, 0);
      expect(
        store.balanceOf(store.goalsAccount().id),
        0,
        reason: 'capped at what the goal held, not what was asked for',
      );
    });
  });

  group('deleting a goal', () {
    test('leaves the money and the history where they are', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 40000, store.accounts.first.id);

      store.removeGoal(g);
      expect(store.goals, isEmpty);
      expect(store.txns, hasLength(1), reason: 'the transfer happened');
      expect(store.balanceOf(store.goalsAccount().id), 40000);
      // The row stops claiming to belong to a goal that is not there.
      expect(store.txns.single.goalId, isNull);
    });
  });

  group('milestones', () {
    test('one contribution to full celebrates once, not four times', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);

      store.putAside(g, 100000, store.accounts.first.id);
      expect(store.claimMilestone(g), 100);
      expect(store.claimMilestone(g), isNull);
    });

    test('a quarter, then half, each get their own moment', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);

      store.putAside(g, 25000, store.accounts.first.id);
      expect(store.claimMilestone(g), 25);
      store.putAside(g, 25000, store.accounts.first.id);
      expect(store.claimMilestone(g), 50);
    });

    test('putting money back in does not replay a moment', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);

      store.putAside(g, 50000, store.accounts.first.id);
      expect(store.claimMilestone(g), 50);
      store.takeOut(g, 30000, store.accounts.first.id);
      store.putAside(g, 30000, store.accounts.first.id);
      expect(store.claimMilestone(g), isNull);
    });

    test('a moment claimed today is still claimed tomorrow', () async {
      final store = await emptyStore();
      expect(store.claimMoment('anything'), isTrue);
      expect(store.claimMoment('anything'), isFalse);

      // The guard is persisted, so a relaunch must not replay it either.
      final next = PennyStore();
      await next.load();
      expect(next.claimMoment('anything'), isFalse);
    });
  });

  test('goals and their transfers survive an export and an import', () async {
    final store = await emptyStore();
    final g = phone();
    store.addGoal(g);
    store.putAside(g, 40000, store.accounts.first.id);

    final restored = PennyStore();
    await restored.load();
    expect(restored.importJson(store.exportJson()), isTrue);
    expect(restored.goals.single.name, 'Phone');
    expect(restored.statusOf(restored.goals.single).saved, 40000);
    expect(
      restored.goalsAccountOrNull,
      isNotNull,
      reason: 'the goals account is an account like any other',
    );
    expect(restored.totalSetAside, 40000);
  });

  group('the page', () {
    Widget page(PennyStore store) => MaterialApp(
      theme: appTheme(dark: false),
      home: ListenableBuilder(
        listenable: store,
        builder: (context, _) => GoalsPage(store: store),
      ),
    );

    void phoneView(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(1080, 2280)
        ..devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('a goal is added from the empty state', (tester) async {
      phoneView(tester);
      final store = await emptyStore();
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add a goal'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Phone');
      // Not `.last` — the icon picker's search box is a text field too.
      await tester.enterText(
        find.descendant(
          of: find.byType(AmountField),
          matching: find.byType(TextField),
        ),
        '1000',
      );
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(store.goals.single.name, 'Phone');
      expect(store.goals.single.targetMinor, 100000);
      expect(find.text('Phone'), findsOneWidget);
      // The hero says it too, and the two agree.
      expect(find.text('0%'), findsNWidgets(2));
    });

    testWidgets('putting money aside moves it and celebrates the milestone', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final cash = store.accounts.first;
      cash.openingBalanceMinor = 200000;
      store.addGoal(phone());
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Put aside'));
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(1), reason: 'it went through the ledger');
      expect(store.balanceOf(cash.id), 150000);
      expect(find.text('Halfway there'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsNWidgets(2));
    });

    testWidgets('the sheet refuses money the account does not have', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      // The first chip is the one the sheet opens on.
      store.accounts.first.openingBalanceMinor = 20000;
      store.addGoal(phone());
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pumpAndSettle();

      // The reason is a tooltip on the field's warning sign — one tap when
      // the amount looks wrong, and no space taken the rest of the time.
      final warning = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('only has'),
      );
      expect(warning, findsOneWidget);
      await tester.tap(warning);
      await tester.pumpAndSettle();
      expect(find.textContaining('only has'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Put aside'),
      );
      expect(button.onPressed, isNull, reason: 'more than the account holds');

      // What the goal still needs, on the other hand, only trims.
      await tester.enterText(find.byType(TextField).first, '150');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Put aside'));
      await tester.pumpAndSettle();
      expect(store.statusOf(store.goals.single).saved, 15000);
    });

    testWidgets('taking money back out asks first', (tester) async {
      phoneView(tester);
      final store = await emptyStore();
      final cash = store.accounts.first;
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 50000, cash.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      Future<void> askFor(String amount) async {
        await tester.tap(find.text('Phone'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, amount);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, 'Take out'));
        await tester.pumpAndSettle();
      }

      // Backing out of the question leaves the money where it was — the point
      // of asking at all, on a button a thumb's width from Put aside.
      await askFor('200');
      expect(find.text('Take it back out?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Leave it'));
      await tester.pumpAndSettle();
      expect(store.statusOf(g).saved, 50000);

      await askFor('200');
      await tester.tap(find.widgetWithText(TextButton, 'Take out'));
      await tester.pumpAndSettle();
      expect(store.statusOf(g).saved, 30000);
      expect(store.balanceOf(cash.id), greaterThan(-50000));
    });

    testWidgets('a finished goal reads as ready, and only then', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();
      expect(find.text('READY'), findsNothing);

      store.putAside(g, 100000, store.accounts.first.id);
      await tester.pumpAndSettle();
      expect(find.text('READY'), findsOneWidget);
    });

    testWidgets('a funded goal rises to the top, above the ones still going', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final laptop = Goal(name: 'Laptop', targetMinor: 500000);
      final g = phone();
      store.addGoal(laptop);
      store.addGoal(g);
      store.putAside(g, 100000, store.accounts.first.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      final ready = tester.getTopLeft(find.text('Phone')).dy;
      final going = tester.getTopLeft(find.text('Laptop')).dy;
      expect(ready, lessThan(going), reason: 'READY sorts first');
      expect(
        store.goals.first.name,
        'Laptop',
        reason: 'the store is untouched',
      );

      // The hero adds up every goal rather than reading one of them: the
      // second ₹1,000 is the funded goal's own line.
      expect(find.text('₹1,000'), findsNWidgets(2));
      expect(
        find.textContaining('₹5,000 to go across 2 goals'),
        findsOneWidget,
      );
    });

    testWidgets('"bought it" closes the goal and spends out of Goals', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 100000, store.accounts.first.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Bought it'));
      await tester.pumpAndSettle();
      // The confirmation, which is a dialog's own text button.
      await tester.tap(find.widgetWithText(TextButton, 'Bought it'));
      await tester.pumpAndSettle();

      expect(store.goals, isEmpty);
      // The entry sheet, carrying what it cost, what it was for, and the
      // account the money is actually sitting in.
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(
        find.text('Goals'),
        findsOneWidget,
        reason: 'the account pill on the sheet — the title is on the shell',
      );
    });

    testWidgets('hidden amounts are hidden here too', (tester) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 50000, store.accounts.first.id);
      await store.setHideAmounts(true);

      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      expect(find.textContaining('₹'), findsNothing);
      // The share of the way there is not an amount, and stays readable.
      expect(find.text('50%'), findsNWidgets(2));
    });
  });
}

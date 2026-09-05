import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/goals_screen.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Money put aside is money moved: a transfer out of a real account and into
/// the goals account, tagged with the goal. So what can go wrong is a balance
/// that does not add up, a goal that disagrees with the rows behind it, and a
/// celebration that replays.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PennyStore> emptyStore() async {
    final store = PennyStore();
    await store.load();
    store.seedDefaults();
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

      expect(store.balanceOf(cash.id), 470000, reason: 'the account is lighter');
      expect(store.balanceOf(store.goalsAccount().id), 30000);
      expect(store.totalBalance, before,
          reason: 'a transfer moves money, it does not spend it');
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

    test('deleting the row in the ledger takes it back out of the goal',
        () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      final row = store.putAside(g, 40000, store.accounts.first.id);
      expect(store.statusOf(g).saved, 40000);

      store.removeTxn(row);
      expect(store.statusOf(g).saved, 0,
          reason: 'the rows are the record; there is nothing to reconcile');
    });

    test('a goal over its target is full, not 130% full', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 130000, store.accounts.first.id);

      final status = store.statusOf(g);
      expect(status.progress, 1.0);
      expect(status.remaining, 0);
      expect(status.reached, isTrue);
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
      final bank = store.accounts[1];
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
      expect(store.balanceOf(store.goalsAccount().id), 0,
          reason: 'capped at what the goal held, not what was asked for');
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
    expect(restored.goalsAccountOrNull, isNotNull,
        reason: 'the goals account is an account like any other');
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
      await tester.enterText(find.byType(TextField).last, '1000');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.goals.single.name, 'Phone');
      expect(store.goals.single.targetMinor, 100000);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('putting money aside moves it and celebrates the milestone',
        (tester) async {
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
      await tester.tap(find.widgetWithText(FilledButton, 'Put it aside'));
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(1), reason: 'it went through the ledger');
      expect(store.balanceOf(cash.id), 150000);
      expect(find.text('Halfway there'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('a finished goal reads as ready, and only then',
        (tester) async {
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

    testWidgets('"bought it" closes the goal and spends out of Goals',
        (tester) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 100000, store.accounts.first.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Bought it'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Bought it'));
      await tester.pumpAndSettle();

      expect(store.goals, isEmpty);
      // The entry sheet, carrying what it cost, what it was for, and the
      // account the money is actually sitting in.
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Goals'), findsNWidgets(2),
          reason: 'the page title behind it, and the account pill on the sheet');
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
      expect(find.text('50%'), findsOneWidget);
    });
  });
}

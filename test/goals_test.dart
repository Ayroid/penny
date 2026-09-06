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

    test(
      'it can be dated back, for a month caught up in one sitting',
      () async {
        final store = await emptyStore();
        final g = phone();
        store.addGoal(g);
        final when = shiftDays(today(), -12);

        final row = store.putAside(
          g,
          30000,
          store.accounts.first.id,
          on: when,
        )!;
        expect(row.day, dayKey(when));
        expect(
          store.statusOf(g).saved,
          30000,
          reason: 'the goal counts by tag, not by date',
        );
      },
    );

    test('and so can taking it back out', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 30000, store.accounts.first.id);
      final when = shiftDays(today(), -3);

      final row = store.takeOut(g, 10000, store.accounts.first.id, on: when)!;
      expect(row.day, dayKey(when));
      expect(store.statusOf(g).saved, 20000);
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

  group('pausing and archiving', () {
    test('a paused goal takes no more money', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 20000, store.accounts.first.id);

      store.setGoalState(g, GoalState.paused);
      expect(store.roomToPutAside(g, store.accounts.first.id), 0);
      expect(store.putAside(g, 10000, store.accounts.first.id), isNull);
      expect(
        store.statusOf(g).saved,
        20000,
        reason: 'what was already put aside stays put aside',
      );
    });

    test('and hands back what it holds, because that is still yours', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 20000, store.accounts.first.id);
      store.setGoalState(g, GoalState.paused);

      expect(store.takeOut(g, 20000, store.accounts.first.id), isNotNull);
      expect(store.statusOf(g).saved, 0);
    });

    test('resuming lets it take money again', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.setGoalState(g, GoalState.paused);
      store.setGoalState(g, GoalState.active);

      expect(store.putAside(g, 10000, store.accounts.first.id), isNotNull);
    });

    test('an archived goal is off the page, not out of the file', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 40000, store.accounts.first.id);

      store.setGoalState(g, GoalState.archived);
      expect(store.liveGoals, isEmpty);
      expect(store.archivedGoals, hasLength(1));
      expect(store.goals, hasLength(1), reason: 'nothing was deleted');
      expect(
        store.totalSetAside,
        40000,
        reason: 'the money is in the goals account either way',
      );
    });

    test('the state rides the backup', () async {
      final store = await emptyStore();
      final paused = phone()..name = 'Paused';
      final away = phone()..name = 'Away';
      store.addGoal(paused);
      store.addGoal(away);
      store.setGoalState(paused, GoalState.paused);
      store.setGoalState(away, GoalState.archived);

      final back = PennyStore();
      await back.load();
      back.importJson(store.exportJson());

      expect(back.goals.firstWhere((g) => g.name == 'Paused').paused, isTrue);
      expect(back.goals.firstWhere((g) => g.name == 'Away').archived, isTrue);
    });

    test('a state this build does not know is just a goal', () {
      final g = Goal.fromJson({'name': 'Odd', 'target': 100, 'state': 'zzz'});
      expect(g.state, GoalState.active);
    });
  });

  group('when the goals and the account disagree', () {
    /// A goal funded to [saved], then [gone] taken straight out of the goals
    /// account by something that is not a goal — what a hand-edited backup can
    /// still carry in, and what nothing in the app offers any more.
    Future<(PennyStore, Goal)> drained(int saved, int gone) async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, saved, store.accounts.first.id);
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: gone,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: store.goalsAccount().id,
        ),
      );
      return (store, g);
    }

    test('the shortfall is what the goals claim and cannot have', () async {
      final (store, g) = await drained(40000, 30000);
      expect(
        store.statusOf(g).saved,
        40000,
        reason: 'the goal still claims it',
      );
      expect(
        store.totalSetAside,
        10000,
        reason: 'the account does not hold it',
      );
      expect(store.goalsShortfall, 30000);
    });

    test('a ledger that adds up reports nothing', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 40000, store.accounts.first.id);
      expect(store.goalsShortfall, 0);
    });

    test('money left behind by a deleted goal is not a shortfall', () async {
      // The designed state: deleting a goal leaves its money in the account.
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 40000, store.accounts.first.id);
      store.removeGoal(g);

      expect(store.totalSetAside, 40000);
      expect(store.goalsShortfall, 0, reason: 'more held than claimed is fine');
    });
  });

  group('the goals account is not a pickable account', () {
    test('it is off the list money is moved by hand', () async {
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 20000, store.accounts.first.id);
      final vault = store.goalsAccount();

      expect(store.liveAccounts, contains(vault));
      expect(
        store.pickableAccounts(),
        isNot(contains(vault)),
        reason: 'money gets in and out of it through a goal',
      );
    });

    test('unless a sheet is already sitting on it', () async {
      // The prefilled "Bought it" spend, and a contribution opened from the
      // ledger: a picker that cannot show the current value changes it.
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 20000, store.accounts.first.id);
      final vault = store.goalsAccount();

      expect(store.pickableAccounts(vault.id), contains(vault));
    });

    test('archived accounts stay off it too', () async {
      final store = await emptyStore();
      final cash = store.accounts.first;
      store.setAccountArchived(cash, true);
      expect(store.pickableAccounts(), isNot(contains(cash)));
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
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(1), reason: 'it went through the ledger');
      expect(store.balanceOf(cash.id), 150000);
      expect(find.text('Halfway there'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsNWidgets(2));
    });

    testWidgets('a contribution can be dated from the sheet', (tester) async {
      phoneView(tester);
      final store = await emptyStore();
      store.addGoal(phone());
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      expect(
        find.text('Today'),
        findsOneWidget,
        reason: 'the pill says what it will write before it writes it',
      );

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      // The platform picker opens on today; step back a day and take it.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      final earlier = shiftMonths(today(), -1);
      await tester.tap(find.text('${earlier.day}').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '300');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(store.txns.single.day, dayKey(earlier));
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
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(button.onPressed, isNull, reason: 'more than the account holds');

      // What the goal still needs, on the other hand, only trims.
      await tester.enterText(find.byType(TextField).first, '150');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
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
        await tester.tap(find.widgetWithText(OutlinedButton, 'Withdraw'));
        await tester.pumpAndSettle();
      }

      // Backing out of the question leaves the money where it was — the point
      // of asking at all, on a button a thumb's width from Add.
      await askFor('200');
      expect(find.text('Withdraw from this goal?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Leave it'));
      await tester.pumpAndSettle();
      expect(store.statusOf(g).saved, 50000);

      await askFor('200');
      await tester.tap(find.widgetWithText(TextButton, 'Withdraw'));
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

      // The hero adds up every goal rather than reading one of them.
      expect(find.text('₹1,000'), findsOneWidget);
      expect(find.text('₹1,000 of ₹1,000'), findsOneWidget);
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

      // The entry sheet, carrying what it cost, what it was for, and the
      // account the money is actually sitting in.
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(
        find.text('Phone'),
        findsNWidgets(2),
        reason: 'the card still behind the sheet, and the note it prefilled',
      );
      expect(
        find.text('Goals'),
        findsOneWidget,
        reason: 'the account pill on the sheet — the title is on the shell',
      );
      expect(
        store.goals,
        hasLength(1),
        reason: 'still open — nothing has been spent yet',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(store.goals, isEmpty, reason: 'the spend closed it');
      // By kind rather than by position: the transfer that funded it and the
      // spend that closed it are both dated today, and the ledger sorts by day.
      final spend = store.txns.singleWhere((t) => t.kind == TxKind.expense);
      expect(spend.amountMinor, 100000);
      expect(spend.accountId, store.goalsAccount().id);
    });

    testWidgets('the entry sheet will not offer the Goals account', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 100000, store.accounts.first.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      // In through the sanctioned door: the spend "Bought it" prefills is on
      // the Goals account, so the picker has to show it.
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Bought it'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Bought it'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Goals'));
      await tester.pumpAndSettle();
      expect(
        find.text('Goals'),
        findsWidgets,
        reason: 'the account the sheet is already on stays selectable',
      );

      // Off it, and it is gone: an ordinary expense cannot be entered against
      // what the goals have spoken for.
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      expect(find.text('Goals'), findsNothing);
    });

    testWidgets('backing out of that sheet keeps the goal', (tester) async {
      // The goal used to close before the sheet opened, so cancelling left
      // the money in Goals with nothing pointing at it.
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
      await tester.tap(find.widgetWithText(TextButton, 'Bought it'));
      await tester.pumpAndSettle();

      // Out of the entry sheet without saving.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(store.goals, hasLength(1));
      expect(store.statusOf(g).saved, 100000);
    });

    testWidgets('a shortfall is said out loud, above the goals', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 40000, store.accounts.first.id);
      // Money out of the goals account by something that is not a goal —
      // what a hand-edited backup can still carry in.
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 30000,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: store.goalsAccount().id,
        ),
      );

      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('more than Goals holds'),
        findsOneWidget,
        reason: 'the page cannot silently draw a figure it knows is wrong',
      );
    });

    testWidgets('the goal editor has an icon but no colour', (tester) async {
      // Goals are the brand's green, all of them: a palette index on a goal
      // was decoration nobody was choosing between.
      phoneView(tester);
      final store = await emptyStore();
      store.addGoal(phone());
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit goal'));
      await tester.pumpAndSettle();

      expect(find.text('COLOUR'), findsNothing);
      expect(find.text('ICON'), findsOneWidget);
    });

    testWidgets('pausing a goal shuts the door on Add', (tester) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 20000, store.accounts.first.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit goal'));
      await tester.pumpAndSettle();
      final pause = find.widgetWithText(OutlinedButton, 'Pause');
      await tester.ensureVisible(pause);
      await tester.pumpAndSettle();
      await tester.tap(pause);
      await tester.pumpAndSettle();

      expect(store.goals.single.paused, isTrue);
      expect(find.text('PAUSED'), findsOneWidget);

      // The sheet still opens — money can come back out — but nothing more
      // goes in, and the sheet says why rather than leaving Add dead.
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      final add = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(add.onPressed, isNull);
      expect(find.textContaining('paused'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Withdraw'),
            )
            .onPressed,
        isNull,
        reason: 'nothing typed yet — but the button is there',
      );
    });

    testWidgets('archiving takes it off the page, and back again', (
      tester,
    ) async {
      phoneView(tester);
      final store = await emptyStore();
      final g = phone();
      store.addGoal(g);
      store.putAside(g, 20000, store.accounts.first.id);
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit goal'));
      await tester.pumpAndSettle();
      final archive = find.widgetWithText(OutlinedButton, 'Archive');
      await tester.ensureVisible(archive);
      await tester.pumpAndSettle();
      await tester.tap(archive);
      await tester.pumpAndSettle();

      expect(store.goals.single.archived, isTrue);
      expect(
        find.text('Phone'),
        findsNothing,
        reason: 'off the page, but not out of the file',
      );

      // The door back in, on the empty state as well as under the list.
      await tester.tap(find.text('1 archived goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      final restore = find.widgetWithText(OutlinedButton, 'Restore goal');
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();

      expect(store.goals.single.archived, isFalse);
      expect(find.text('Nothing archived.'), findsOneWidget);

      // Out of the sheet, and the goal is back on the page with the link gone.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('1 archived goal'), findsNothing);
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

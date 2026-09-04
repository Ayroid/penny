import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/home.dart';
import 'package:penny/ledger_screen.dart';
import 'package:penny/analytics_screen.dart';
import 'package:penny/main.dart';
import 'package:penny/onboarding.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A store with defaults and nothing in it.
Future<PennyStore> emptyStore() async {
  final s = PennyStore();
  await s.load();
  s.seedDefaults();
  return s;
}


/// A phone-shaped viewport.
///
/// The default 800x600 test window is shorter than any phone, and the entry
/// sheet is deliberately capped at 92% of the screen — so on the default view
/// its Add button sits below the fold and cannot be tapped.
void phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2280)
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
      theme: appTheme(dark: dark),
      home: child,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the overview opens on an empty ledger and offers a way in',
      (tester) async {
    final store = await emptyStore();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();

    expect(find.text('TOTAL BALANCE'), findsOneWidget);
    expect(find.text('₹0.00'), findsWidgets);
    expect(find.text('Nothing tracked yet'), findsOneWidget);
    expect(find.text('Add a transaction'), findsWidgets);
  });

  testWidgets('the keypad builds an amount paise-first and saves a transaction',
      (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add a transaction').first);
    await tester.pumpAndSettle();

    // 4 5 0 0 0 reads as ₹450.00 — the first digits are paise.
    for (final d in ['4', '5', '0', '0', '0']) {
      await tester.tap(find.widgetWithText(InkWell, d).last);
      await tester.pump();
    }
    expect(find.text('₹450.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(store.txns, hasLength(1));
    expect(store.txns.single.amountMinor, 45000);
    expect(store.txns.single.kind, TxKind.expense);
    expect(store.totalBalance, -45000);
  });

  testWidgets('backspace and the cap behave on screen', (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add a transaction').first);
    await tester.pumpAndSettle();

    for (final d in ['1', '2', '3']) {
      await tester.tap(find.widgetWithText(InkWell, d).last);
      await tester.pump();
    }
    expect(find.text('₹1.23'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    expect(find.text('₹0.12'), findsOneWidget);

    // Nothing to save while the amount is zero.
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    // Two of these on screen: the sheet's amount, and the balance on the page
    // behind it. The assertion that matters is that Add is now dead.
    expect(find.text('₹0.00'), findsWidgets);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull,
        reason: 'a zero amount is not a transaction');
  });

  testWidgets('a transfer needs two different accounts before it can save',
      (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add a transaction').first);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Moved'));
    await tester.pumpAndSettle();
    for (final d in ['5', '0', '0', '0', '0']) {
      await tester.tap(find.widgetWithText(InkWell, d).last);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(store.txns.single.kind, TxKind.transfer);
    expect(store.txns.single.toAccountId, isNotNull);
    expect(store.txns.single.toAccountId,
        isNot(store.txns.single.accountId));
    // The whole point: moving money does not change how much there is.
    expect(store.totalBalance, 0);
  });

  testWidgets('the ledger groups by day and carries a running balance',
      (tester) async {
    final store = await emptyStore();
    final cash = store.accounts.first.id;
    final food = store.categoriesOf(TxKind.expense).first.id;
    final salary = store.categoriesOf(TxKind.income).first.id;
    store.addTxn(Txn(
        kind: TxKind.income,
        amountMinor: 8000000,
        day: dayKey(today()),
        categoryId: salary,
        accountId: cash));
    store.addTxn(Txn(
        kind: TxKind.expense,
        amountMinor: 45000,
        day: dayKey(shiftDays(today(), -1)),
        categoryId: food,
        accountId: cash,
        note: 'lunch'));

    await tester.pumpWidget(wrap(LedgerPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('+₹80,000.00'), findsOneWidget);
    expect(find.text('-₹450.00'), findsOneWidget);
    expect(find.text('2 entries'), findsOneWidget);
  });

  testWidgets('search narrows the ledger', (tester) async {
    final store = await emptyStore();
    final cash = store.accounts.first.id;
    for (final (note, amount) in [('lunch', 45000), ('petrol', 200000)]) {
      store.addTxn(Txn(
          kind: TxKind.expense,
          amountMinor: amount,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: cash,
          note: note));
    }

    await tester.pumpWidget(wrap(LedgerPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('2 entries'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'petrol');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('-₹2,000.00'), findsOneWidget);
    expect(find.text('-₹450.00'), findsNothing);
  });

  testWidgets('insights stays quiet with nothing to read', (tester) async {
    final store = await emptyStore();
    await tester.pumpWidget(wrap(InsightsPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to read yet'), findsOneWidget);
  });

  testWidgets('insights breaks spending down by category', (tester) async {
    final store = await emptyStore();
    final cash = store.accounts.first.id;
    final cats = store.categoriesOf(TxKind.expense);
    store.addTxn(Txn(
        kind: TxKind.expense,
        amountMinor: 300000,
        day: dayKey(today()),
        categoryId: cats[0].id,
        accountId: cash));
    store.addTxn(Txn(
        kind: TxKind.expense,
        amountMinor: 100000,
        day: dayKey(today()),
        categoryId: cats[1].id,
        accountId: cash));

    await tester.pumpWidget(wrap(InsightsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text(cats[0].name), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('every screen renders in dark mode too', (tester) async {
    final store = await emptyStore();
    store.addTxn(Txn(
        kind: TxKind.expense,
        amountMinor: 45000,
        day: dayKey(today()),
        categoryId: store.categoriesOf(TxKind.expense).first.id,
        accountId: store.accounts.first.id));

    for (final page in [
      HomePage(store: store, onSettings: () {}),
      LedgerPage(store: store),
      InsightsPage(store: store),
    ]) {
      await tester.pumpWidget(wrap(page, dark: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  group('the app as a whole', () {
    // Every other test pumps a page directly with a store already loaded,
    // which is exactly why the launch-frame hang got through: `App` was the
    // one widget nothing exercised end to end.
    testWidgets('leaves the launch frame once the store has loaded',
        (tester) async {
      await tester.pumpWidget(const App());

      // First frame: nothing loaded, so the drawn mark stands in.
      expect(find.byType(LaunchFrame), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(LaunchFrame), findsNothing,
          reason: 'a loaded store must not leave the app on its splash');
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('goes straight to the shell for someone already onboarded',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(find.byType(LaunchFrame), findsNothing);
      expect(find.byType(RootScreen), findsOneWidget);
      expect(find.text('TOTAL BALANCE'), findsOneWidget);
    });

    testWidgets('switching theme rebuilds the shell', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(Theme.of(tester.element(find.byType(RootScreen))).brightness,
          Brightness.light);

      final store = tester.state<State<App>>(find.byType(App));
      // ignore: avoid_dynamic_calls
      await (store as dynamic).store.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(Theme.of(tester.element(find.byType(RootScreen))).brightness,
          Brightness.dark);
    });
  });
}

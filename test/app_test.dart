import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/home.dart';
import 'package:penny/ledger_screen.dart';
import 'package:penny/analytics_screen.dart';
import 'package:penny/main.dart';
import 'package:penny/money.dart';
import 'package:penny/onboarding.dart';
import 'package:penny/page_bar.dart';
import 'package:penny/settings.dart';
import 'package:penny/store.dart';
import 'package:penny/txn_row.dart';
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

/// Drag the overview far enough for its RECENT rows to build.
///
/// `ListView` builds lazily, so rows below the fold are not in the element
/// tree at all. `scrollUntilVisible` is no help here: its finder must resolve
/// to exactly one element, which `TxnRow` does not once there are two of them.
Future<void> scrollToRows(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
  await tester.pumpAndSettle();
}

/// The overview as the shell actually composes it.
///
/// `RootScreen` wraps its pages in a `ListenableBuilder`, so a page repaints
/// when the store changes. Pumping `HomePage` bare instead means it never sees
/// anything added through a sheet.
Widget home(PennyStore store, {bool dark = false}) => wrap(
  ListenableBuilder(
    listenable: store,
    builder: (context, _) => HomePage(store: store),
  ),
  dark: dark,
);

Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
  theme: appTheme(dark: dark),
  home: child,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the overview opens on an empty ledger and offers a way in', (
    tester,
  ) async {
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();

    expect(find.text('TOTAL BALANCE'), findsOneWidget);
    expect(find.text('₹0.00'), findsWidgets);
    expect(find.text('Nothing tracked yet'), findsOneWidget);
    expect(find.text('Add a transaction'), findsWidgets);
  });

  testWidgets('typing an amount and saving it', (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    // The amount field is the one that autofocuses, and it reads as rupees —
    // "450" is four hundred and fifty, not four rupees fifty.
    await tester.enterText(find.byType(TextField).first, '450');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(store.txns, hasLength(1));
    expect(store.txns.single.amountMinor, 45000);
    expect(store.txns.single.kind, TxKind.expense);
    expect(store.totalBalance, -45000);
  });

  testWidgets('paise are typed after a decimal point', (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '450.50');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(store.txns.single.amountMinor, 45050);
  });

  testWidgets('an empty or zero amount cannot be saved', (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    FilledButton add() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));

    expect(add().onPressed, isNull, reason: 'nothing typed yet');

    await tester.enterText(find.byType(TextField).first, '0');
    await tester.pumpAndSettle();
    expect(add().onPressed, isNull, reason: 'zero is not a transaction');

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pumpAndSettle();
    expect(add().onPressed, isNotNull);
  });

  testWidgets('the field refuses a third decimal place', (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(field, '12.34');
    await tester.pumpAndSettle();
    await tester.enterText(field, '12.345');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(store.txns.single.amountMinor, 1234);
  });

  testWidgets('a transfer needs two different accounts before it can save', (
    tester,
  ) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Moved'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(store.txns.single.kind, TxKind.transfer);
    expect(store.txns.single.toAccountId, isNotNull);
    expect(store.txns.single.toAccountId, isNot(store.txns.single.accountId));
    // The whole point: moving money does not change how much there is.
    expect(store.totalBalance, 0);
  });

  testWidgets('the ledger groups by day and carries a running balance', (
    tester,
  ) async {
    final store = await emptyStore();
    final cash = store.accounts.first.id;
    final food = store.categoriesOf(TxKind.expense).first.id;
    final salary = store.categoriesOf(TxKind.income).first.id;
    store.addTxn(
      Txn(
        kind: TxKind.income,
        amountMinor: 8000000,
        day: dayKey(today()),
        categoryId: salary,
        accountId: cash,
      ),
    );
    store.addTxn(
      Txn(
        kind: TxKind.expense,
        amountMinor: 45000,
        day: dayKey(shiftDays(today(), -1)),
        categoryId: food,
        accountId: cash,
        note: 'lunch',
      ),
    );

    await tester.pumpWidget(wrap(LedgerPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('+₹80,000.00'), findsOneWidget);
    expect(find.text('-₹450.00'), findsOneWidget);
  });

  testWidgets('search narrows the ledger', (tester) async {
    final store = await emptyStore();
    final cash = store.accounts.first.id;
    for (final (note, amount) in [('lunch', 45000), ('petrol', 200000)]) {
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: amount,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: cash,
          note: note,
        ),
      );
    }

    await tester.pumpWidget(wrap(LedgerPage(store: store)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'petrol');
    await tester.pumpAndSettle();
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
    store.addTxn(
      Txn(
        kind: TxKind.expense,
        amountMinor: 300000,
        day: dayKey(today()),
        categoryId: cats[0].id,
        accountId: cash,
      ),
    );
    store.addTxn(
      Txn(
        kind: TxKind.expense,
        amountMinor: 100000,
        day: dayKey(today()),
        categoryId: cats[1].id,
        accountId: cash,
      ),
    );

    await tester.pumpWidget(wrap(InsightsPage(store: store)));
    await tester.pumpAndSettle();

    expect(find.text(cats[0].name), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('every screen renders in dark mode too', (tester) async {
    final store = await emptyStore();
    store.addTxn(
      Txn(
        kind: TxKind.expense,
        amountMinor: 45000,
        day: dayKey(today()),
        categoryId: store.categoriesOf(TxKind.expense).first.id,
        accountId: store.accounts.first.id,
      ),
    );

    for (final page in [
      HomePage(store: store),
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
    testWidgets('leaves the launch frame once the store has loaded', (
      tester,
    ) async {
      await tester.pumpWidget(const App());

      // First frame: nothing loaded, so the drawn mark stands in.
      expect(find.byType(LaunchFrame), findsOneWidget);

      await tester.pumpAndSettle();

      expect(
        find.byType(LaunchFrame),
        findsNothing,
        reason: 'a loaded store must not leave the app on its splash',
      );
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('goes straight to the shell for someone already onboarded', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(find.byType(LaunchFrame), findsNothing);
      expect(find.byType(RootScreen), findsOneWidget);
      expect(find.text('TOTAL BALANCE'), findsOneWidget);
    });

    testWidgets('the lit tab pill travels with the swipe', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      phone(tester);

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      // The one box painted in the accent inside the bar. Three tabs each
      // fading their own background — what this replaced — puts no box at full
      // accent anywhere mid-swipe, and two of them half lit.
      final accent = sproutOf(tester.element(find.byType(PageTabs)));
      Rect litPill() => tester.getRect(
        find.descendant(
          of: find.byType(PageTabs),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == accent,
          ),
        ),
      );

      final onOverview = litPill();

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await drag.moveBy(const Offset(-30, 0)); // past the touch slop
      await tester.pump();
      await drag.moveBy(const Offset(-150, 0));
      await tester.pump();

      final midSwipe = litPill();
      expect(
        midSwipe.left,
        greaterThan(onOverview.left),
        reason: 'the pill moves with the finger, not once the page lands',
      );
      expect(
        midSwipe.width,
        closeTo(onOverview.width, 0.5),
        reason: 'one pill travelling, not one shrinking while another grows',
      );

      // Let go short of the halfway mark and the page comes back, and so does
      // the pill: it is the page's own offset, not a selection of its own.
      await drag.up();
      await tester.pumpAndSettle();
      expect(litPill().left, onOverview.left);

      // And a tap takes it the whole way, still as one box that moves.
      await tester.tap(find.bySemanticsLabel('Goals'));
      await tester.pumpAndSettle();
      final onGoals = litPill();
      expect(onGoals.left, greaterThan(midSwipe.left));
      expect(onGoals.width, closeTo(onOverview.width, 0.5));
    });

    testWidgets('switching theme rebuilds the shell', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(RootScreen))).brightness,
        Brightness.light,
      );

      final store = tester.state<State<App>>(find.byType(App));
      // ignore: avoid_dynamic_calls
      await (store as dynamic).store.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(RootScreen))).brightness,
        Brightness.dark,
      );
    });
  });

  group('quick entries', () {
    /// Add a transaction through the sheet, saved for quick add.
    Future<void> saveEntry(WidgetTester tester, String amount) async {
      await tester.tap(find.byType(FloatingActionButton).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, amount);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save for quick add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
    }

    /// Hold the add button until the row floats out.
    Future<void> holdAdd(WidgetTester tester) async {
      await tester.longPress(find.byType(FloatingActionButton).first);
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is saved until the person saves it', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();

      // Entering things does not conjure chips: the row is curated, never
      // guessed at from history.
      await tester.tap(find.byType(FloatingActionButton).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(1));
      expect(store.shortcuts, isEmpty);

      // And a hold on an empty list opens nothing, rather than an empty row
      // that reads as a broken control.
      await holdAdd(tester);
      expect(find.bySemanticsLabel('Add Food & Drink, ₹20'), findsNothing);
    });

    testWidgets('saving puts it behind the add button', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();

      await saveEntry(tester, '20');

      expect(store.shortcuts, hasLength(1));
      expect(store.shortcuts.single.amountMinor, 2000);
      // Not on the page until it is asked for.
      expect(find.bySemanticsLabel('Add Food & Drink, ₹20'), findsNothing);

      await holdAdd(tester);
      expect(find.bySemanticsLabel('Add Food & Drink, ₹20'), findsOneWidget);
    });

    testWidgets('a chip adds to today on one tap', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await saveEntry(tester, '20');

      await holdAdd(tester);
      await tester.tap(find.bySemanticsLabel('Add Food & Drink, ₹20'));
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(2));
      expect(store.txns.first.amountMinor, 2000);
      expect(store.txns.first.day, dayKey(today()));
      // And the row is gone with it — one pick, not a menu left standing.
      expect(find.bySemanticsLabel('Add Food & Drink, ₹20'), findsNothing);
    });

    testWidgets('holding and releasing over a chip adds it', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await saveEntry(tester, '20');

      // The Pinterest gesture: the finger never comes up between opening the
      // row and choosing from it.
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(FloatingActionButton).first),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final chip = tester.getCenter(
        find.bySemanticsLabel('Add Food & Drink, ₹20'),
      );
      await drag.moveTo(chip);
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(2));
      expect(store.txns.first.amountMinor, 2000);
    });

    testWidgets('releasing where it opened leaves the row up', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await saveEntry(tester, '20');

      // A hold that goes nowhere is a menu, not a mis-fire: nothing is added,
      // and the chips stay to be tapped.
      await holdAdd(tester);

      expect(store.txns, hasLength(1));
      expect(find.bySemanticsLabel('Add Food & Drink, ₹20'), findsOneWidget);
    });

    testWidgets('the row stays inside the screen, and survives a hover', (
      tester,
    ) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();

      // A long amount and a short one: the pair that used to be laid out in a
      // box the width of the screen, which both swallowed taps meant for the
      // page behind it and had nowhere to put an entry that did not fit.
      await saveEntry(tester, '13000');
      await saveEntry(tester, '32');
      await holdAdd(tester);

      final button = tester.getRect(find.byType(FloatingActionButton).first);
      final chips = [
        tester.getRect(find.bySemanticsLabel('Add Food & Drink, ₹13,000')),
        tester.getRect(find.bySemanticsLabel('Add Food & Drink, ₹32')),
      ];
      expect(
        chips.map((c) => c.right).reduce((a, b) => a > b ? a : b),
        button.right,
        reason: 'flush with the button, never off the edge beside it',
      );
      for (final chip in chips) {
        expect(chip.left, greaterThanOrEqualTo(16.0));
        expect(chip.bottom, lessThanOrEqualTo(button.top));
      }

      // And the hover that made a chip's own tooltip ask where it was, on a
      // screen it could not yet be placed on. An assertion here is a failure:
      // flutter_test fails a test on any exception the framework throws.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(chips.first.center);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byType(Tooltip), findsWidgets);
    });

    testWidgets('adding from a chip is corrected in the ledger', (
      tester,
    ) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await saveEntry(tester, '20');

      await holdAdd(tester);
      await tester.tap(find.bySemanticsLabel('Add Food & Drink, ₹20'));
      await tester.pumpAndSettle();
      expect(store.txns, hasLength(2));

      // The undo bar covers the top of RECENT while it is up, and this is
      // about the other correction — the one you make after it has gone, by
      // opening the row and deleting it like any other.
      await tester.pump(undoLinger);
      await tester.pumpAndSettle();
      await scrollToRows(tester);
      await tester.tap(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.txns, hasLength(1));
    });

    testWidgets('saving the same thing twice leaves one chip', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();

      await saveEntry(tester, '20');
      await saveEntry(tester, '20');

      // Two chips that cannot be told apart is exactly what the guessed
      // version got wrong.
      expect(store.shortcuts, hasLength(1));
      expect(store.txns, hasLength(2));
    });

    testWidgets('the toggle reflects what is already saved', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await saveEntry(tester, '20');

      // Reopen that transaction from the RECENT list. The overview's ListView
      // builds lazily, so the RECENT rows are not in the tree until they are
      // scrolled into it.
      await scrollToRows(tester);
      await tester.tap(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Saved for quick add'), findsOneWidget);

      await tester.tap(find.byTooltip('Saved for quick add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.shortcuts, isEmpty);
    });
  });

  group('hiding the balance', () {
    testWidgets('the eye masks the total and every account', (tester) async {
      phone(tester);
      final store = await emptyStore();
      store.addTxn(
        Txn(
          kind: TxKind.income,
          amountMinor: 8500000,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.income).first.id,
          accountId: store.accounts.first.id,
        ),
      );

      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      expect(find.text('₹85,000.00'), findsWidgets);

      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();

      expect(store.hideAmounts, isTrue);
      expect(find.text('••••••'), findsWidgets);
      // The per-account chips have to go too — leaving them is leaving the
      // balance on screen in three pieces.
      expect(find.textContaining('₹85,000'), findsNothing);
      expect(find.text('Cash  $maskedAmount'), findsOneWidget);
    });

    testWidgets('nothing below the balance moves when it is hidden', (
      tester,
    ) async {
      phone(tester);
      final store = await emptyStore();
      // Amounts wide enough that the account chips have a real layout to
      // disturb — a mask is a different width from a number, and if that
      // reflows the Wrap the whole screen jumps.
      store.addTxn(
        Txn(
          kind: TxKind.income,
          amountMinor: 8500000,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.income).first.id,
          accountId: store.accounts[1].id,
        ),
      );
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 1849900,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: store.accounts.first.id,
        ),
      );

      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      final shownCard = tester.getSize(find.byType(TintCard).first);
      final shownBelow = tester.getTopLeft(find.text('CREDIT')).dy;

      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(TintCard).first).height,
        shownCard.height,
        reason: 'the balance card changed height',
      );
      expect(
        tester.getTopLeft(find.text('CREDIT')).dy,
        shownBelow,
        reason: 'everything below the balance card moved',
      );
    });

    testWidgets('it is one tap back', (tester) async {
      phone(tester);
      final store = await emptyStore();
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show amounts'));
      await tester.pumpAndSettle();

      expect(store.hideAmounts, isFalse);
      expect(find.text('••••••'), findsNothing);
    });

    testWidgets('the mask does not leak how big the number is', (tester) async {
      phone(tester);
      final small = await emptyStore();
      await tester.pumpWidget(home(small));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      final masked = tester.widget<Text>(find.text('••••••').first).data;

      // A mask sized to the digits would give away the order of magnitude,
      // which is most of what was being hidden.
      expect(masked, '••••••');
    });

    testWidgets('the ledger is masked too, not just the overview', (
      tester,
    ) async {
      phone(tester);
      final store = await emptyStore();
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 45000,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: store.accounts.first.id,
          note: 'lunch',
        ),
      );
      await store.setHideAmounts(true);

      await tester.pumpWidget(
        wrap(
          ListenableBuilder(
            listenable: store,
            builder: (context, _) => LedgerPage(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Every figure on the screen: the row, its running balance and the day's
      // net. "Hide amounts" that covers one screen is half a promise.
      expect(find.textContaining('₹'), findsNothing);
      expect(find.text(maskedAmount), findsWidgets);
      expect(find.textContaining('lunch'), findsOneWidget);
    });
  });

  testWidgets('hiding survives a relaunch', (tester) async {
    phone(tester);
    final store = await emptyStore();
    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide amounts'));
    await tester.pumpAndSettle();

    final next = PennyStore();
    await next.load();
    expect(
      next.hideAmounts,
      isTrue,
      reason: 'having to hide it again every launch is why people stop',
    );
  });

  group('deleting an entry', () {
    Future<PennyStore> withOne(WidgetTester tester) async {
      final store = await emptyStore();
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 45000,
          day: dayKey(today()),
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: store.accounts.first.id,
          note: 'lunch',
        ),
      );
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await scrollToRows(tester);
      await tester.tap(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('Delete is the same shape as Save', (tester) async {
      phone(tester);
      await withOne(tester);

      final save = tester.getSize(find.widgetWithText(FilledButton, 'Save'));
      final del = tester.getSize(find.widgetWithText(OutlinedButton, 'Delete'));
      expect(del.width, save.width);
      expect(del.height, save.height);
    });

    testWidgets('it asks first, and Keep changes nothing', (tester) async {
      phone(tester);
      final store = await withOne(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();

      // The amount is in the question — "delete this?" is easy to say yes to
      // on the wrong row.
      expect(find.text('Delete this entry?'), findsOneWidget);
      expect(find.textContaining('₹450.00'), findsWidgets);
      expect(find.textContaining('lunch'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();
      expect(store.txns, hasLength(1), reason: 'Keep must keep it');
    });

    testWidgets('confirming deletes it and closes the sheet', (tester) async {
      phone(tester);
      final store = await withOne(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.txns, isEmpty);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    });

    testWidgets('and then offers to put it back where it was', (tester) async {
      phone(tester);
      final store = await emptyStore();
      final category = store.categoriesOf(TxKind.expense).first.id;
      final account = store.accounts.first.id;
      // Three on one day, so undoing the middle one has somewhere wrong to
      // land: appended, it would come back at the bottom of its own day.
      for (final note in ['bus', 'lunch', 'chai']) {
        store.addTxn(
          Txn(
            kind: TxKind.expense,
            amountMinor: 45000,
            day: dayKey(today()),
            categoryId: category,
            accountId: account,
            note: note,
          ),
        );
      }
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      await scrollToRows(tester);

      await tester.tap(find.textContaining('lunch'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.txns.map((t) => t.note), ['chai', 'bus']);

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();
      expect(store.txns.map((t) => t.note), ['chai', 'lunch', 'bus']);
    });

    testWidgets('the question no longer claims it cannot be undone', (
      tester,
    ) async {
      phone(tester);
      await withOne(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be undone'), findsNothing);
      expect(find.textContaining('undo this'), findsOneWidget);
    });
  });

  group('recurring rules', () {
    testWidgets('a rule is edited in place, not stopped and rebuilt', (
      tester,
    ) async {
      phone(tester);
      final store = await emptyStore();
      store.addRule(
        Rule(
          kind: TxKind.expense,
          amountMinor: 1200000,
          categoryId: store.categoriesOf(TxKind.expense).first.id,
          accountId: store.accounts.first.id,
          note: 'Rent',
          startDay: dayKey(today()),
        ),
      );

      await tester.pumpWidget(wrap(SettingsScreen(store: store)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recurring'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      expect(find.text('Edit rule'), findsOneWidget);

      // The amount is the first field on the sheet, the note the last.
      await tester.enterText(find.byType(TextField).first, '15000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.rules, hasLength(1), reason: 'edited, not replaced');
      expect(store.rules.single.amountMinor, 1500000);
      expect(store.rules.single.note, 'Rent');
    });
  });

  group('the spend grid', () {
    Future<PennyStore> aWeek(WidgetTester tester) async {
      final store = await emptyStore();
      final cash = store.accounts.first.id;
      final food = store.categoriesOf(TxKind.expense).first.id;
      // Something on today and something three days back, both inside the
      // current week only if today is late enough in it — so anchor on the
      // week's own Monday instead.
      for (final offset in [0, 1]) {
        store.addTxn(
          Txn(
            kind: TxKind.expense,
            amountMinor: 45000 * (offset + 1),
            day: dayKey(shiftDays(startOfWeek(today()), offset)),
            categoryId: food,
            accountId: cash,
          ),
        );
      }
      await tester.pumpWidget(home(store));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('the week shows exactly seven days', (tester) async {
      phone(tester);
      await aWeek(tester);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(find.text('SPEND BY DAY'), findsOneWidget);
      final monday = startOfWeek(today());
      for (var i = 0; i < 7; i++) {
        final d = shiftDays(monday, i);
        expect(
          find.bySemanticsLabel(RegExp('^Day ${d.day}\\b')),
          findsOneWidget,
          reason: 'day ${d.day} of the week is missing',
        );
      }
    });

    testWidgets('a day shows no grid — one cell says nothing', (tester) async {
      phone(tester);
      await aWeek(tester);

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('SPEND BY DAY'), findsNothing);
    });

    testWidgets('the month still lays out as a calendar', (tester) async {
      phone(tester);
      await aWeek(tester);

      // Month is the default. The first of the month sits under its own
      // weekday, so the grid has leading blanks the week does not.
      expect(find.text('SPEND BY DAY'), findsOneWidget);
      final last = DateTime(today().year, today().month + 1, 0).day;
      expect(find.bySemanticsLabel(RegExp('^Day $last\\b')), findsOneWidget);
    });
  });

  testWidgets('recent rows are grouped under day headers', (tester) async {
    phone(tester);
    final store = await emptyStore();
    final cash = store.accounts.first.id;
    final food = store.categoriesOf(TxKind.expense).first.id;
    for (final offset in [0, 0, 1, 2]) {
      store.addTxn(
        Txn(
          kind: TxKind.expense,
          amountMinor: 45000,
          day: dayKey(shiftDays(today(), -offset)),
          categoryId: food,
          accountId: cash,
        ),
      );
    }

    await tester.pumpWidget(home(store));
    await tester.pumpAndSettle();
    await scrollToRows(tester);

    // Same words the ledger uses — the two must not call a day different
    // things on different screens.
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(
      find.text(dayHeader(dayKey(shiftDays(today(), -2)))),
      findsOneWidget,
    );

    // One header for the day with two entries on it, not two.
    expect(find.byType(TxnRow), findsNWidgets(4));
  });
}

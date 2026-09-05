import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/main.dart';
import 'package:penny/page_bar.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The undo bar has two ways to be useless, and both of them shipped once:
/// laid out underneath the floating tab pill, where it cannot be read and its
/// UNDO cannot be tapped, and then staying there until dismissed by a hand
/// that could not reach it.
///
/// Neither shows up in a golden — the pill paints over the bar, so the image
/// looks correct — and neither shows up in a test that pumps a page on its
/// own, because the pill lives in the shell above it. So: the real shell, at
/// phone size, with a gesture strip.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PennyStore> emptyStore() async {
    final store = PennyStore();
    await store.load();
    store.seedDefaults();
    return store;
  }

  Shortcut entryOf(PennyStore store, String note, int amountMinor) => Shortcut(
    kind: TxKind.expense,
    amountMinor: amountMinor,
    categoryId: store.categoriesOf(TxKind.expense).first.id,
    accountId: store.accounts.first.id,
    note: note,
  );

  Future<Shortcut> shellWithAnEntry(
    WidgetTester tester,
    PennyStore store,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2280)
      ..devicePixelRatio = 3.0
      // The strip Android keeps for its own back-swipe. Left at zero, a
      // margin that ignores the inset would pass this — and `viewPadding` as
      // well as `padding`, because the two are the same thing on a device with
      // no keyboard up, and it is `viewPadding` that a floating button reads.
      ..padding = const FakeViewPadding(bottom: 144)
      ..viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);

    final entry = entryOf(store, 'Chai', 12000);
    store.addShortcut(entry);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(dark: false),
        home: RootScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    return entry;
  }

  /// Hold the add button, then take the one chip that floats out.
  Future<void> addFromTheRow(WidgetTester tester) async {
    await tester.longPress(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add Chai, ₹120'));
    await tester.pumpAndSettle();
  }

  testWidgets('the undo bar clears the tab pill', (tester) async {
    final store = await emptyStore();
    await shellWithAnEntry(tester, store);

    await addFromTheRow(tester);

    expect(find.text('UNDO'), findsOneWidget);

    // The painted boxes, not the widgets: `SnackBar` is its own margin and
    // `PageTabs` is an `Align` filling the shell, so both of those rects are
    // the whole screen and would compare true no matter where the bar landed.
    final bar = tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    final pill = tester.getRect(
      find.descendant(
        of: find.byType(PageTabs),
        matching: find.byType(Material),
      ),
    );
    expect(bar.bottom, lessThanOrEqualTo(pill.top));
    // And just above it, not hanging a pill and a half up the screen: the
    // `Scaffold` already lifts a floating bar clear of the add button, which
    // sits on the pill's own line, so anything this app adds on top of that is
    // counted twice.
    expect(pill.top - bar.bottom, lessThan(tabBarHeight));

    // And within reach: tapped rather than only measured, because a widget
    // can be laid out clear of the pill and still sit under something else.
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(store.txns, isEmpty);
  });

  testWidgets('the undo bar leaves on its own', (tester) async {
    final store = await emptyStore();
    await shellWithAnEntry(tester, store);

    await addFromTheRow(tester);
    expect(find.text('UNDO'), findsOneWidget);

    // Nothing tapped and nothing swiped — only time passing.
    await tester.pump(undoLinger);
    await tester.pumpAndSettle();

    expect(find.text('UNDO'), findsNothing);
    // Leaving is not undoing: what was added stays added.
    expect(store.txns, hasLength(1));
  });
}

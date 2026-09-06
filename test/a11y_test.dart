import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/analytics.dart';
import 'package:penny/clock.dart';
import 'package:penny/home.dart';
import 'package:penny/ledger_screen.dart';
import 'package:penny/page_bar.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PennyStore> seeded() async {
  final store = PennyStore();
  await store.load();
  store.seedDefaults();
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
  store.addTxn(
    Txn(
      kind: TxKind.income,
      amountMinor: 8500000,
      day: dayKey(today()),
      categoryId: store.categoriesOf(TxKind.income).first.id,
      accountId: store.accounts[1].id,
    ),
  );
  return store;
}

Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
  theme: appTheme(dark: dark),
  home: child,
);

void main() {
  late DateTime Function() previousClock;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previousClock = useFixedClock(DateTime(2026, 9, 17, 10, 30));
  });
  tearDown(() => clock = previousClock);

  testWidgets('every icon-only control names itself', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store)));
    await tester.pumpAndSettle();

    // An icon button with no label is a mystery to a screen reader and has no
    // tooltip for anyone else either.
    for (final tooltip in ['Previous month', 'Next month']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      expect(find.bySemanticsLabel(tooltip), findsWidgets, reason: tooltip);
    }

    // The add button is the exception, and named rather than tooltipped: a
    // tooltip is a long press, and a long press on that button floats the
    // quick entries out instead.
    expect(find.byTooltip('Add a transaction'), findsNothing);
    expect(find.bySemanticsLabel('Add a transaction'), findsWidgets);

    // Settings and Insights live on the shell's bar now, above all three
    // pages rather than on this one.
    await tester.pumpWidget(
      wrap(Scaffold(body: ShellBar(store: store, page: 0))),
    );
    await tester.pumpAndSettle();
    for (final tooltip in ['Settings', 'Insights']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      expect(find.bySemanticsLabel(tooltip), findsWidgets, reason: tooltip);
    }
  });

  testWidgets('tap targets are never below 48', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store)));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
  });

  // Contrast is asserted analytically in palette_test, per pair and per theme,
  // rather than with `textContrastGuideline` here.
  //
  // That guideline samples the two dominant colours inside a text node's rect
  // and calls the lighter one the background. For a selected segmented pill
  // that rect is mostly the deep fill sitting in a lighter track, so it
  // measures the fill against the track and never looks at the white glyph on
  // the pill, which is 9.1. It is a false positive on a shape the design
  // system prescribes, and suppressing it per-widget would hide the real
  // failures it is there to catch elsewhere.
  //
  // What is worth pinning here is that the widget actually uses the colours
  // palette_test blessed, so the two files cannot drift apart.
  testWidgets('the selected pill uses the measured ink, and travels', (
    tester,
  ) async {
    final store = await seeded();
    for (final dark in [false, true]) {
      await tester.pumpWidget(wrap(HomePage(store: store), dark: dark));
      await tester.pumpAndSettle();

      final segmented = find.byType(Segmented<Period>);

      TextStyle labelStyle(String label) => tester
          .widget<AnimatedDefaultTextStyle>(
            find.ancestor(
              of: find.text(label),
              matching: find.descendant(
                of: segmented,
                matching: find.byType(AnimatedDefaultTextStyle),
              ),
            ),
          )
          .style;

      expect(
        labelStyle('Month').color,
        onSproutDeep,
        reason: 'the pill is the deep tone, which exists to carry white',
      );
      expect(
        labelStyle('Month').fontWeight,
        FontWeight.w700,
        reason: 'weight carries the selection when colour cannot',
      );

      // The pill sits over the selected segment rather than each segment
      // fading its own background: three of three, so hard right.
      Alignment pillAt() =>
          tester
                  .widget<AnimatedAlign>(
                    find.descendant(
                      of: segmented,
                      matching: find.byType(AnimatedAlign),
                    ),
                  )
                  .alignment
              as Alignment;
      expect(pillAt(), const Alignment(1, 0));

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(
        pillAt(),
        const Alignment(-1, 0),
        reason: 'the pill travels to the new selection',
      );

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a transaction announces itself as one thing, not five', (
    tester,
  ) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(LedgerPage(store: store)));
    await tester.pumpAndSettle();

    // The row merges into a single announcement carrying the category, the
    // amount and the note — rather than a screen reader reading out an icon,
    // two labels and two numbers as separate stops.
    expect(
      find.bySemanticsLabel(RegExp(r'Food & Drink, -₹450\.00, Cash · lunch')),
      findsOneWidget,
    );
  });

  testWidgets('a heatmap cell says what it is worth', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store)));
    await tester.pumpAndSettle();

    // Colour is never the only signal: the shade encodes the amount, the ring
    // marks today, the minus sign carries the direction — and the semantics
    // carry all three in words, the net one signed.
    expect(
      find.bySemanticsLabel(
        RegExp(r'Day 17, today, ₹450\.00, net \+₹84,550\.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Day 1, nothing spent')),
      findsOneWidget,
    );
  });

  testWidgets('the selected period is announced as selected', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store)));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel('Month'));
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Week'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
    handle.dispose();
  });
}

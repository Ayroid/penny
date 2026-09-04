import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/analytics.dart';
import 'package:penny/clock.dart';
import 'package:penny/home.dart';
import 'package:penny/ledger_screen.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PennyStore> seeded() async {
  final store = PennyStore();
  await store.load();
  store.seedDefaults();
  store.addTxn(Txn(
      kind: TxKind.expense,
      amountMinor: 45000,
      day: dayKey(today()),
      categoryId: store.categoriesOf(TxKind.expense).first.id,
      accountId: store.accounts.first.id,
      note: 'lunch'));
  store.addTxn(Txn(
      kind: TxKind.income,
      amountMinor: 8500000,
      day: dayKey(today()),
      categoryId: store.categoriesOf(TxKind.income).first.id,
      accountId: store.accounts[1].id));
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
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();

    // An icon button with no label is a mystery to a screen reader and has no
    // tooltip for anyone else either.
    for (final tooltip in [
      'Settings',
      'Add a transaction',
      'Previous month',
      'Next month',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
      expect(find.bySemanticsLabel(tooltip), findsWidgets, reason: tooltip);
    }
  });

  testWidgets('tap targets are never below 48', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
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
  // that rect is mostly the accent fill sitting in a lighter track, so it
  // measures the fill against the track — 2.19 — and never looks at the navy
  // glyph on the pill, which is 5.43. It is a false positive on a shape the
  // design system prescribes, and suppressing it per-widget would hide the
  // real failures it is there to catch elsewhere.
  //
  // What is worth pinning here is that the widget actually uses the colours
  // palette_test blessed, so the two files cannot drift apart.
  testWidgets('the selected pill uses the measured accent and ink',
      (tester) async {
    final store = await seeded();
    for (final dark in [false, true]) {
      await tester.pumpWidget(
          wrap(HomePage(store: store, onSettings: () {}), dark: dark));
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.descendant(
          of: find.byType(Segmented<Period>), matching: find.text('Month')));
      expect(label.style?.color, navy,
          reason: 'white on the sprout measures 2.57 and must never appear');

      final pill = tester.widget<AnimatedContainer>(find.ancestor(
          of: find.text('Month'), matching: find.byType(AnimatedContainer)));
      expect((pill.decoration as BoxDecoration).color,
          dark ? sproutDark : sprout);
    }
  });

  testWidgets('a transaction announces itself as one thing, not five',
      (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(LedgerPage(store: store)));
    await tester.pumpAndSettle();

    // The row merges into a single announcement carrying the category, the
    // amount and the note — rather than a screen reader reading out an icon,
    // two labels and two numbers as separate stops.
    expect(
      find.bySemanticsLabel(
          RegExp(r'Food & Drink, -₹450\.00, Cash · lunch')),
      findsOneWidget,
    );
  });

  testWidgets('a heatmap cell says what it is worth', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();

    // Colour is never the only signal: the shade encodes the amount, and the
    // semantics carry the same figure in words.
    expect(find.bySemanticsLabel(RegExp(r'Day 17, ₹450\.00')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Day 1, nothing spent')),
        findsOneWidget);
  });

  testWidgets('the selected period is announced as selected', (tester) async {
    final store = await seeded();
    await tester.pumpWidget(wrap(HomePage(store: store, onSettings: () {})));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel('Month'));
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel('Week'))
        .flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });
}

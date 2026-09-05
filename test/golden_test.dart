import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/analytics_screen.dart';
import 'package:penny/clock.dart';
import 'package:penny/entry_sheet.dart';
import 'package:penny/goals_screen.dart';
import 'package:penny/home.dart';
import 'package:penny/ledger_screen.dart';
import 'package:penny/onboarding.dart';
import 'package:penny/settings.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Goldens render with the real typefaces.
///
/// Three families, and all three matter: without the sans every string draws
/// in the runner's fallback, without Lucide every icon is a hollow box, and
/// without a mono every amount and date is one too — which is most of the
/// numbers on every screen.
Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family)
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }

  await load('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf');

  // Lucide ships its font inside the package, so this path is as reproducible
  // as the dependency itself.
  final lucide = Directory(
          '${File(Platform.resolvedExecutable).parent.path}/../..')
      .path;
  for (final candidate in [
    '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/lucide_icons_flutter-3.1.17/assets/lucide.ttf',
    '$lucide/lucide.ttf',
  ]) {
    if (File(candidate).existsSync()) {
      // IconData carries fontPackage: 'lucide_icons_flutter', so the family
      // Flutter actually looks up is package-qualified.
      await load('packages/lucide_icons_flutter/Lucide', candidate);
      break;
    }
  }

  // The app asks for the *platform* mono by design — nothing is bundled — so
  // a golden run has to supply one. Whichever the machine has; the run is
  // best-effort here rather than pinned, exactly as in Wick.
  for (final candidate in [
    '/usr/share/fonts/google-noto-vf/NotoSansMono[wght].ttf',
    '/usr/share/fonts/adwaita-mono-fonts/AdwaitaMono-Regular.ttf',
    '/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf',
    '/System/Library/Fonts/Menlo.ttc',
  ]) {
    if (File(candidate).existsSync()) {
      await load('monospace', candidate);
      break;
    }
  }
}

/// A fixed ledger: a salary, a spread of spending across the month, and one
/// transfer, so every surface has something real on it.
Future<PennyStore> seeded() async {
  final store = PennyStore();
  await store.load();
  store.seedDefaults();

  final cash = store.accounts[0].id;
  final bank = store.accounts[1].id;
  final expense = {
    for (final c in store.categoriesOf(TxKind.expense)) c.name: c.id
  };
  final income = {
    for (final c in store.categoriesOf(TxKind.income)) c.name: c.id
  };

  store.accountById(bank)!.openingBalanceMinor = 4200000;
  store.accountById(cash)!.openingBalanceMinor = 350000;

  void add(TxKind kind, int amount, int dayOffset, String category,
      {String note = ''}) {
    store.addTxn(Txn(
      kind: kind,
      amountMinor: amount,
      day: dayKey(shiftDays(today(), -dayOffset)),
      categoryId: kind == TxKind.income ? income[category]! : expense[category]!,
      accountId: kind == TxKind.income ? bank : cash,
      note: note,
    ));
  }

  add(TxKind.income, 8500000, 16, 'Salary', note: 'September');
  add(TxKind.expense, 2400000, 15, 'Rent');
  add(TxKind.expense, 186000, 12, 'Groceries', note: 'weekly shop');
  add(TxKind.expense, 32000, 10, 'Food & Drink', note: 'chai and samosa');
  add(TxKind.expense, 145000, 8, 'Transport', note: 'petrol');
  add(TxKind.expense, 89900, 5, 'Entertainment', note: 'cinema');
  add(TxKind.expense, 240000, 3, 'Shopping');
  add(TxKind.expense, 45000, 1, 'Food & Drink', note: 'lunch');
  add(TxKind.expense, 62000, 0, 'Groceries', note: 'milk and eggs');
  store.addTxn(Txn(
    kind: TxKind.transfer,
    amountMinor: 1000000,
    day: dayKey(shiftDays(today(), -7)),
    categoryId: expense['Other']!,
    accountId: bank,
    toAccountId: cash,
    note: 'ATM',
  ));

  return store;
}

/// Let the mascot PNGs actually decode.
///
/// A golden test runs under fake async, where no real future ever completes,
/// so `Image.asset` lays out at its reserved height and paints nothing.
/// Precaching the provider by hand does not help either: `PennyImage` passes
/// `cacheHeight`, which wraps it in a `ResizeImage` under a different cache
/// key from a bare `AssetImage`. `runAsync` is the only place real futures
/// run, so the fix is to give them a moment there and then repaint.
Future<void> settleImages(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pumpAndSettle();
}

/// Pump one screen at a phone size and file it against its golden.
Future<void> shot(
  WidgetTester tester,
  String name,
  Widget child, {
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2280)
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: appTheme(dark: dark),
    home: child,
  ));
  await tester.pumpAndSettle();
  await settleImages(tester);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// Mid-month, mid-morning. Every screen renders a date or a greeting, so
/// without a pinned clock these images fail the next day.
final _pinned = DateTime(2026, 9, 17, 10, 30);

void main() {
  setUpAll(loadFonts);

  late DateTime Function() previousClock;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previousClock = useFixedClock(_pinned);
  });
  tearDown(() => clock = previousClock);

  testWidgets('overview', (tester) async {
    await shot(
        tester, 'overview', HomePage(store: await seeded(), onSettings: () {}));
  });

  testWidgets('overview dark', (tester) async {
    await shot(tester, 'overview_dark',
        HomePage(store: await seeded(), onSettings: () {}),
        dark: true);
  });

  testWidgets('overview week', (tester) async {
    final store = await seeded();
    tester.view
      ..physicalSize = const Size(1080, 2280)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(dark: false),
      home: HomePage(store: store, onSettings: () {}),
    ));
    await tester.pumpAndSettle();
    await settleImages(tester);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/overview_week.png'));
  });

  testWidgets('overview empty', (tester) async {
    final store = PennyStore();
    await store.load();
    store.seedDefaults();
    await shot(
        tester, 'overview_empty', HomePage(store: store, onSettings: () {}));
  });

  testWidgets('ledger', (tester) async {
    await shot(tester, 'ledger', LedgerPage(store: await seeded()));
  });

  testWidgets('ledger dark', (tester) async {
    await shot(tester, 'ledger_dark', LedgerPage(store: await seeded()),
        dark: true);
  });

  testWidgets('insights', (tester) async {
    await shot(tester, 'insights', InsightsPage(store: await seeded()));
  });

  testWidgets('insights dark', (tester) async {
    await shot(tester, 'insights_dark', InsightsPage(store: await seeded()),
        dark: true);
  });

  testWidgets('goals', (tester) async {
    final store = await seeded();
    final phone = Goal(name: 'Phone', targetMinor: 4500000, icon: 'phone');
    final trip = Goal(name: 'Trip home', targetMinor: 1200000, icon: 'plane');
    store
      ..addGoal(phone)
      ..addGoal(trip);
    store.putAside(phone, 1800000, store.accounts[1].id);
    store.putAside(trip, 1200000, store.accounts[1].id);
    await shot(tester, 'goals', GoalsPage(store: store));
  });

  /// The empty state is the one screen that draws `Penny.focus`, the pose that
  /// shipped in the APK for months without a caller.
  testWidgets('goals empty', (tester) async {
    final store = PennyStore();
    await store.load();
    store.seedDefaults();
    await shot(tester, 'goals_empty', GoalsPage(store: store));
  });

  testWidgets('settings', (tester) async {
    await shot(tester, 'settings', SettingsScreen(store: await seeded()));
  });

  testWidgets('entry sheet', (tester) async {
    final store = await seeded();
    tester.view
      ..physicalSize = const Size(1080, 2280)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(dark: false),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showEntrySheet(context, store),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await settleImages(tester);

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/entry_sheet.png'));
  });

  testWidgets('onboarding', (tester) async {
    final store = PennyStore();
    await store.load();
    await shot(tester, 'onboarding', OnboardingScreen(store: store));
  });
}

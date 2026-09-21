import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/lock.dart';
import 'package:penny/main.dart';
import 'package:penny/settings.dart';
import 'package:penny/store.dart';
import 'package:penny/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var answer = true;
  var canLock = true;
  var asked = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    answer = true;
    canLock = true;
    asked = 0;
    askPhone = () async {
      asked++;
      return answer;
    };
    phoneCanLock = () async => canLock;
  });
  tearDown(() => unlocked.value = false);

  test('a short trip away does not ask again; a longer one does', () {
    expect(relockAfter(const Duration(seconds: 5)), isFalse);
    expect(relockAfter(lockGrace), isTrue);
  });

  group('opening a locked Penny', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'onboarded': true,
        'appLock': true,
      }),
    );

    testWidgets('asks straight away, and shows the ledger once it is you', (
      tester,
    ) async {
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('TOTAL BALANCE'), findsOneWidget);
    });

    testWidgets('a refusal leaves nothing showing but the way in', (
      tester,
    ) async {
      answer = false;
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('TOTAL BALANCE'), findsNothing);

      answer = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('TOTAL BALANCE'), findsOneWidget);
    });

    testWidgets('a quick trip to another app comes back unlocked', (
      tester,
    ) async {
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();

      expect(asked, 1, reason: 'within the grace period');
      expect(find.byType(LockScreen), findsNothing);
    });
  });

  group('the setting', () {
    Future<PennyStore> open(WidgetTester tester) async {
      final store = PennyStore();
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(dark: false),
          home: SettingsScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('turns on only once the phone has said it is you', (
      tester,
    ) async {
      final store = await open(tester);

      answer = false;
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(store.appLock, isFalse);

      answer = true;
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(store.appLock, isTrue);
      expect(unlocked.value, isTrue, reason: 'no lock screen straight after');

      // Turning it off asks as well.
      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();
      expect(store.appLock, isFalse);
      expect(asked, 3);
    });

    testWidgets('a phone with no screen lock is told so, not locked', (
      tester,
    ) async {
      canLock = false;
      final store = await open(tester);

      await tester.tap(find.text('App lock'));
      await tester.pumpAndSettle();

      expect(store.appLock, isFalse);
      expect(asked, 0);
      expect(
        find.text('Set up a screen lock on your phone first.'),
        findsOneWidget,
      );
    });
  });
}

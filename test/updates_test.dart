import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/store.dart';
import 'package:penny/page_bar.dart';
import 'package:penny/theme.dart';
import 'package:penny/updates.dart';

void main() {
  test('isNewer compares numbers, not strings', () {
    expect(isNewer('v0.2.0', '0.1.0'), isTrue);
    expect(isNewer('v0.10.0', '0.9.0'), isTrue);
    expect(isNewer('v0.1.0', '0.1.0'), isFalse);
    expect(isNewer('v0.1.0', '0.2.0'), isFalse);
    expect(isNewer('v1.0', '0.9.9'), isTrue);
    expect(isNewer('v0.2.0+5', '0.2.0'), isFalse);
  });

  test('pickApk takes the APK for this ABI', () {
    final assets = [
      {'name': 'penny-0.2.0-armeabi-v7a.apk', 'browser_download_url': 'v7'},
      {'name': 'penny-0.2.0-arm64-v8a.apk', 'browser_download_url': 'v8'},
      {'name': 'notes.txt', 'browser_download_url': 'txt'},
    ];
    expect(pickApk(assets, 'arm64-v8a'), 'v8');
    expect(pickApk(assets, 'armeabi-v7a'), 'v7');
    expect(pickApk(assets, 'x86_64'), isNull);
  });

  testWidgets('a newer version found puts a red dot on Settings', (
    tester,
  ) async {
    addTearDown(() => updateWaiting.value = null);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(dark: false),
        home: Scaffold(body: ShellBar(store: PennyStore(), page: 0)),
      ),
    );
    Badge dot() => tester.widget(find.byType(Badge));
    expect(dot().isLabelVisible, isFalse);

    updateWaiting.value = 'v9.9.9';
    await tester.pump();
    expect(dot().isLabelVisible, isTrue);
    expect(find.byTooltip('Settings, update ready'), findsOneWidget);
  });
}

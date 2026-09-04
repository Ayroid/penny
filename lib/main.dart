import 'package:flutter/material.dart';

import 'analytics_screen.dart';
import 'home.dart';
import 'ledger_screen.dart';
import 'onboarding.dart';
import 'page_bar.dart';
import 'penny.dart';
import 'recurring.dart';
import 'settings.dart';
import 'store.dart';
import 'theme.dart';

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final store = PennyStore();

  /// Only the parts of the store that decide what the MaterialApp renders.
  ///
  /// Rebuilding the whole app on every store notification would repaint three
  /// pages of cards on each keypad tap. This rebuilds when the shell actually
  /// changes and lets each page listen for itself.
  ///
  /// Assigned in initState rather than declared `late var ... = (...)`. A late
  /// initializer runs on first *read*, which is inside `_onStoreChanged` —
  /// i.e. after loading already finished. It would capture the post-load
  /// values, compare them equal to themselves, and never rebuild, leaving the
  /// app on its launch frame forever. Pinned by a test.
  late (ThemeMode, bool, bool) _shell;

  @override
  void initState() {
    super.initState();
    _shell = (store.themeMode, store.loaded, store.onboarded);
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onStoreChanged);
    store.load().then((_) {
      // Rules that came due while the app was closed catch up here. There is
      // no background isolate and no server, so "when it next opens" is the
      // honest contract.
      materialiseDue(store);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back after midnight, or after a few days away, should not need a
    // relaunch to show the rent that fell due.
    if (state == AppLifecycleState.resumed && store.loaded) {
      materialiseDue(store);
    }
  }

  void _onStoreChanged() {
    final next = (store.themeMode, store.loaded, store.onboarded);
    if (next != _shell) setState(() => _shell = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Penny',
      debugShowCheckedModeBanner: false,
      theme: appTheme(dark: false),
      darkTheme: appTheme(dark: true),
      themeMode: store.themeMode,
      home: !store.loaded
          ? const LaunchFrame()
          : store.onboarded
          ? RootScreen(store: store)
          : OnboardingScreen(store: store),
    );
  }
}

/// What fills the gap between the system splash and the first real frame.
///
/// The same mark on the same ground the system splash used, so the handoff is
/// invisible rather than a flash of empty scaffold.
class LaunchFrame extends StatelessWidget {
  const LaunchFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: CoinMark(size: 128, semanticLabel: 'Penny')),
    );
  }
}

/// The shell: three swipeable pages under a floating tab pill.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.store});

  final PennyStore store;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _pages = PageController();

  /// The PageView's fractional offset, as a ValueNotifier rather than
  /// setState: a swipe then repaints only the tab pill, not three pages full
  /// of cards and a heatmap.
  final _position = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      // `page` is pixels / viewportDimension, which is 0/0 — NaN — until the
      // PageView has been laid out once. NaN then flows into the tab weights,
      // and Dart's `clamp` propagates NaN rather than clamping it, so the pill
      // lays out at a nonsense width. Hold the last good value instead.
      final page = _pages.hasClients ? _pages.page : null;
      if (page != null && !page.isNaN) _position.value = page;
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Stack(
        children: [
          PageView(
            controller: _pages,
            children: [
              HomePage(
                store: widget.store,
                onSettings: () => openSettings(context, widget.store),
              ),
              LedgerPage(store: widget.store),
              InsightsPage(store: widget.store),
            ],
          ),
          PageTabs(
            position: _position,
            onSelect: (i) => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
          ),
        ],
      ),
    );
  }
}

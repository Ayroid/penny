import 'package:flutter/material.dart';

import 'goals_screen.dart';
import 'home.dart';
import 'ledger_screen.dart';
import 'onboarding.dart';
import 'page_bar.dart';
import 'penny.dart';
import 'recurring.dart';
import 'store.dart';
import 'theme.dart';
import 'updates.dart';

void main() {
  runApp(const App());
  checkOnLaunch();
}

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
  /// pages of cards on every keystroke. This rebuilds when the shell actually
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
      // No scrollbars, anywhere. Flutter draws one beside every scroll view on
      // a desktop platform, and Penny is a phone app whose lists — the icon
      // grid especially — are short enough to flick. The scrolling itself is
      // untouched.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
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

  /// The page that has *landed*. The bar's title changes on this rather than
  /// on [_position], so a swipe does not recount the ledger on every frame.
  final _page = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      // `page` is pixels / viewportDimension, which is 0/0 — NaN — until the
      // PageView has been laid out once. NaN then flows into the tab weights,
      // and Dart's `clamp` propagates NaN rather than clamping it, so the pill
      // lays out at a nonsense width. Hold the last good value instead.
      final page = _pages.hasClients ? _pages.page : null;
      if (page == null || page.isNaN) return;
      _position.value = page;
      _page.value = page.round();
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _position.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      // A `Material` rather than a `Scaffold`: the pages inside bring their
      // own, and a second one out here takes the snackbars — which then no
      // longer lift clear of the page's add button, because this one has no
      // button on it. All the shell needs from a Scaffold is a ground to paint
      // and an ink surface for the bar's buttons.
      builder: (context, _) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // One bar over all three pages, rebuilt when a swipe lands
              // rather than with the drag.
              ValueListenableBuilder<int>(
                valueListenable: _page,
                builder: (context, page, _) =>
                    ShellBar(store: widget.store, page: page),
              ),
              Expanded(
                child: Stack(
                  children: [
                    PageView(
                      controller: _pages,
                      children: [
                        HomePage(store: widget.store),
                        LedgerPage(store: widget.store),
                        GoalsPage(store: widget.store),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

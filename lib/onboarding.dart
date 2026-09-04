import 'package:flutter/material.dart';

import 'penny.dart';
import 'store.dart';
import 'theme.dart';

/// Three pages, then out of the way.
///
/// The seed happens on the second page rather than silently at launch, so the
/// accounts and categories that appear are ones the person was told about.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.store});

  final PennyStore store;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 1) widget.store.seedDefaults();
    if (_page < 2) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      widget.store.finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _Page(
                    pose: Penny.standing,
                    headline: "I'm Penny",
                    body:
                        'Your buddy for smarter money choices and a brighter tomorrow. '
                        'Track what comes in and what goes out — that is the whole idea.',
                  ),
                  _Page(
                    pose: Penny.thinking,
                    headline: 'Accounts and categories',
                    body:
                        'Starting you with Cash, Bank and Card, and the categories most '
                        'spending falls into. Rename, recolour or archive any of them later.',
                  ),
                  _Page(
                    pose: Penny.rest,
                    headline: 'It stays on your phone',
                    body:
                        'No account, no sync, no analytics. Your backup is a file you '
                        'export and keep. Nothing leaves this device unless you send it.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? sproutOf(context)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _next,
                    child: Text(switch (_page) {
                      0 => 'Start',
                      1 => 'Looks good',
                      _ => 'Add my first entry',
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.pose, required this.headline, required this.body});

  final Penny pose;
  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    return PennyMessage(pose: pose, headline: headline, body: body, size: 160);
  }
}

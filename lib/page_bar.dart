import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// The shell's top bar: a title, an optional line under it, and up to two
/// round icon buttons.
///
/// A tab page passes no [onBack] — the tabs below are its navigation, and a
/// back arrow on a page you cannot go back from is a lie. A page that was
/// *pushed*, like Insights, passes one, and gets the same bar rather than a
/// stock `AppBar` that reads as a different app.
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: RoundIconButton(
                icon: LucideIcons.arrowLeft,
                tooltip: 'Back',
                onPressed: onBack!,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: text.headlineLarge),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: text.bodySmall),
                  ),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// One destination in the shell.
typedef TabSpec = ({String label, IconData icon});

/// What the floating pill occupies at the bottom of the screen: the tab, the
/// track's padding on both sides, and the gap it floats in.
///
/// Named rather than typed in twice, because the pill is not the only thing
/// that wants the bottom of the screen — [showUndoBar] has to land above it,
/// and two hand-tuned numbers that must agree is a pair that drifts the first
/// time either is touched. Wick exports the same three for the same reason.
const tabHeight = 44.0;
const tabInset = 5.0;
const tabBarHeight = tabHeight + tabInset * 2;
const tabBarGap = 16.0;

const shellTabs = <TabSpec>[
  (label: 'Overview', icon: LucideIcons.house),
  (label: 'Ledger', icon: LucideIcons.receiptText),
  (label: 'Goals', icon: LucideIcons.piggyBank),
];

/// The slot the add button occupies at the bottom right, and the gap it keeps
/// from the pill.
///
/// The pill centres itself in what is *left* of the width rather than in the
/// whole of it: centred on the screen, a three-tab pill with its selected tab
/// open runs to about 232 and the button starts at 284, so the two would
/// overlap on a narrow phone. Wick floats the same pair and the same numbers
/// have to agree there.
const dockButton = 54.0;
const dockGap = 14.0;

/// The floating tab pill.
///
/// A `Stack` overlay rather than a `bottomNavigationBar`, which would reserve a
/// strip of the screen for chrome on every page. [position] is the PageView's
/// fractional offset, so the selected pill slides with the swipe instead of
/// snapping when it settles.
class PageTabs extends StatelessWidget {
  const PageTabs({super.key, required this.position, required this.onSelect});

  final ValueListenable<double> position;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.bottomCenter,
      // Above the gesture bar, not under it. The shell is a bare Stack over the
      // whole screen, so without this the pill sits in the strip the system
      // reserves for its own back-swipe.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: tabBarGap,
            right: dockButton + dockGap * 2,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark(context) ? darkCard : Colors.white,
              borderRadius: BorderRadius.circular(pill),
              boxShadow: cardShadow(isDark(context)),
            ),
            clipBehavior: Clip.antiAlias,
            // The shell is a bare Stack — the pages inside it bring their own
            // Scaffolds, but this pill floats above them with no Material of its
            // own, and every tab is an InkWell. Without this the tabs assert on
            // first build and the pill lays out at a nonsense width.
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(tabInset),
                child: ValueListenableBuilder<double>(
                  valueListenable: position,
                  builder: (context, value, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < shellTabs.length; i++)
                        _Tab(
                          spec: shellTabs[i],
                          // How selected this tab is, 0 to 1. Mid-swipe both
                          // neighbours are partly lit, which is what makes the pill
                          // track the finger.
                          // `clamp` does not tame a NaN — it returns one — and a
                          // NaN weight becomes a NaN width. The listenable is
                          // supplied by the caller, so this does not trust it.
                          weight: value.isNaN
                              ? (i == 0 ? 1.0 : 0.0)
                              : (1 - (value - i).abs()).clamp(0.0, 1.0),
                          onTap: () => onSelect(i),
                          scheme: scheme,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.spec,
    required this.weight,
    required this.onTap,
    required this.scheme,
  });

  final TabSpec spec;
  final double weight;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final accent = sproutOf(context);
    // Colour is never the only signal: the label also appears, and the glyph
    // gains weight, as a tab becomes selected.
    final fill = accent.withValues(alpha: weight);
    final ink = Color.lerp(scheme.secondary, onAccent(context), weight)!;

    return Semantics(
      button: true,
      selected: weight > 0.5,
      label: spec.label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(pill),
        child: Container(
          height: tabHeight,
          constraints: const BoxConstraints(minWidth: 48),
          padding: EdgeInsets.symmetric(horizontal: 14 + 6 * weight),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 19, color: ink),
              // The label only exists once the tab is more than half selected,
              // so three labels never compete for the width of the pill.
              ClipRect(
                child: Align(
                  widthFactor: weight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: Text(
                      spec.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How long an undo stays offered. Long enough to notice a mis-tap, short
/// enough that it is gone before it becomes furniture.
const undoLinger = Duration(seconds: 4);

/// A one-line message with one way to take it back.
///
/// Floated clear of the tab pill, and gone on its own after [undoLinger].
/// Both of those are the point: the pill is a `Stack` overlay rather than a
/// `bottomNavigationBar`, so the `Scaffold` laying the snackbar out does not
/// know the pill is there and puts the bar underneath it — unreadable, and
/// with UNDO sitting under a tab that swallows the tap. A bar that also had
/// to be dismissed by hand was then a bar that could not be dismissed at all.
///
/// The same [MediaQuery.paddingOf] the pill's own `SafeArea` reads, so the two
/// move together: a floating snackbar takes no bottom inset of its own
/// (`SafeArea(bottom: false)`, in `snack_bar.dart`), and the pill above it
/// does.
void showUndoBar(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  final clearance =
      tabBarHeight + tabBarGap + MediaQuery.paddingOf(context).bottom;

  ScaffoldMessenger.of(context)
    // One at a time. Tapping a pinned chip twice should leave one offer to
    // undo, not two stacked bars racing each other out.
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: undoLinger,
        // `SnackBar.persist` defaults to `action != null`, so a bar with an
        // UNDO on it ignores its own duration and waits to be dismissed by
        // hand. That default plus a bar laid out under the pill is what made
        // these undismissable, and a `duration:` that reads as if it works is
        // why it looked like something else.
        persist: false,
        margin: EdgeInsets.fromLTRB(16, 0, 16, clearance + 8),
        action: SnackBarAction(label: 'UNDO', onPressed: onUndo),
      ),
    );
}

/// The add button, floating at the bottom right beside the tab pill.
///
/// A `FloatingActionButton` rather than another `RoundIconButton`: it is the
/// one control that floats over a scrolling page, and the platform widget
/// already brings the elevation, the tooltip, the semantics and the shuffle
/// out of a snackbar's way. Sized to the pill it sits beside — a 56 default
/// next to a 54 bar reads as a mistake at a glance.
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          sizeConstraints: BoxConstraints.tightFor(
            width: dockButton,
            height: dockButton,
          ),
        ),
      ),
      // The pill's own soft shadow rather than Material's: the theme sets no
      // shadow colour, so an elevated FAB draws a hard black ring next to a
      // pill that floats on a wash of navy at 6%.
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: cardShadow(isDark(context)),
        ),
        child: FloatingActionButton(
          onPressed: onPressed,
          tooltip: tooltip,
          backgroundColor: sproutOf(context),
          // Computed, not white: white on the sprout measures 2.57:1.
          foregroundColor: onAccent(context),
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(),
          // The label rides on the icon: a FAB's tooltip is a tooltip, not a
          // semantics label, so a screen reader would otherwise announce an
          // unnamed button.
          child: Icon(LucideIcons.plus, size: 22, semanticLabel: tooltip),
        ),
      ),
    );
  }
}

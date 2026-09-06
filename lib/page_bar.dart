import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'analytics.dart';
import 'analytics_screen.dart';
import 'icons.dart';
import 'money.dart';
import 'settings.dart';
import 'store.dart';
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

/// `‹  September 2026  ›` — the window being read, and the arrows that move it.
///
/// Shared by the overview and Insights. The two step through the same windows,
/// and a second copy is how they end up disagreeing about where a week starts.
class PeriodNav extends StatelessWidget {
  const PeriodNav({
    super.key,
    required this.period,
    required this.anchor,
    required this.onStep,
  });

  final Period period;
  final DateTime anchor;

  /// -1 for the period before, +1 for the one after.
  final ValueChanged<int> onStep;

  /// The next period is only reachable while it is not entirely in the future.
  static bool canGoForward(Period period, DateTime anchor) =>
      rangeFor(period, anchor).to.compareTo(dayKey(today())) < 0;

  static String labelFor(Period period, DateTime anchor) {
    final r = rangeFor(period, anchor);
    final from = parseDay(r.from);
    return switch (period) {
      Period.day => r.from == dayKey(today()) ? 'Today' : longDate(from),
      Period.week => '${shortDate(from)} — ${shortDate(parseDay(r.to))}',
      Period.month => '${months[from.month - 1]} ${from.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final forward = canGoForward(period, anchor);
    final unit = period.label.toLowerCase();

    return Row(
      children: [
        RoundIconButton(
          icon: LucideIcons.chevronLeft,
          tooltip: 'Previous $unit',
          size: 36,
          onPressed: () => onStep(-1),
        ),
        Expanded(
          child: Text(
            labelFor(period, anchor),
            textAlign: TextAlign.center,
            style: mono(
              12.5,
              color: Theme.of(context).colorScheme.secondary,
              weight: FontWeight.w700,
            ),
          ),
        ),
        Opacity(
          // Kept in the layout rather than removed, so the label does not
          // jump sideways at the present period.
          opacity: forward ? 1 : 0.25,
          child: RoundIconButton(
            icon: LucideIcons.chevronRight,
            tooltip: 'Next $unit',
            size: 36,
            onPressed: () => forward ? onStep(1) : null,
          ),
        ),
      ],
    );
  }
}

/// The shell's one bar, above all three tabs.
///
/// The title switches when a swipe *lands* — no crossfade, and nothing that
/// travels with the finger: the pages sliding underneath already say the swipe
/// happened, and a headline recomputed every frame is three pages of cards
/// rebuilt with it. Settings rides here rather than on the Overview page, so
/// it is one tap from wherever you are instead of a swipe home first.
class ShellBar extends StatelessWidget {
  const ShellBar({super.key, required this.store, required this.page});

  final PennyStore store;

  /// The page that has landed — 0, 1 or 2.
  final int page;

  (String, String) _titleFor() {
    switch (page) {
      case 0:
        // `today()` rather than `DateTime.now()` so it moves with the
        // injected clock and the goldens stay still.
        return (greeting(), longDate(today()));
      case 1:
        return ('Ledger', plural(store.txns.length, 'entry', 'entries'));
      default:
        // The page's own hero card carries the total now, and a screen that
        // says the same number twice reads as a screen that has nothing else
        // to say.
        return ('Goals', 'Turn your dreams into progress 🌱');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _titleFor();

    return PageBar(
      title: title,
      subtitle: subtitle,
      actions: [
        // Both on every tab: they are pages you open on purpose, from
        // wherever you are, rather than things this or that tab owns.
        RoundIconButton(
          icon: LucideIcons.chartPie,
          tooltip: 'Insights',
          onPressed: () => openInsights(context, store),
        ),
        RoundIconButton(
          icon: LucideIcons.settings,
          tooltip: 'Settings',
          onPressed: () => openSettings(context, store),
        ),
      ],
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

/// One tab's slot. Equal for all three, because the lit pill is a single box
/// that slides across them and a fraction of the track only lands on a tab if
/// every tab is the same width.
const tabWidth = 56.0;
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
/// The pill is centred on the screen, so on a narrow phone a three-tab pill
/// with its selected tab open (about 232) comes close to the button. Wick
/// floats the same pair and the same numbers have to agree there.
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
          padding: const EdgeInsets.only(bottom: tabBarGap),
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
                  builder: (context, value, _) {
                    // `clamp` does not tame a NaN — it returns one — and a NaN
                    // here is a pill laid out at a nonsense offset. The
                    // listenable is supplied by the caller, so this does not
                    // trust it. Clamped as well as checked: a PageView
                    // overscrolls past both ends.
                    final at = value.isNaN
                        ? 0.0
                        : value.clamp(0.0, shellTabs.length - 1.0);

                    return Stack(
                      children: [
                        // One lit pill that travels, rather than three tabs
                        // each fading their own background in and out — the
                        // same movement `Segmented` makes above. Fading in
                        // place reads as two things blinking; travelling reads
                        // as the selection moving, which is what happened.
                        // Driven by the raw page offset, so it tracks the
                        // finger mid-swipe and eases with the page on a tap.
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment(
                              -1 + 2 * at / (shellTabs.length - 1),
                              0,
                            ),
                            child: FractionallySizedBox(
                              widthFactor: 1 / shellTabs.length,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: sproutDeepOf(context),
                                  borderRadius: BorderRadius.circular(pill),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < shellTabs.length; i++)
                              _Tab(
                                spec: shellTabs[i],
                                // How lit this tab's glyph is, 0 to 1.
                                // Mid-swipe both neighbours are partly inked,
                                // so the glyph crossfades under the pill
                                // arriving over it.
                                weight: (1 - (at - i).abs()).clamp(0.0, 1.0),
                                onTap: () => onSelect(i),
                                scheme: scheme,
                              ),
                          ],
                        ),
                      ],
                    );
                  },
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
    // Colour is never the only signal: the lit pill is a filled shape that
    // arrives under the glyph, and the glyph's own ink crosses to the colour
    // measured against it.
    final ink = Color.lerp(scheme.secondary, onSproutDeep, weight)!;

    return Semantics(
      button: true,
      selected: weight > 0.5,
      label: spec.label,
      excludeSemantics: true,
      onTap: onTap,
      // The name is not on the tab any more — it is a press-and-hold away.
      // Material's tooltip already is long-press on touch and hover on
      // desktop, so there is nothing here to build.
      child: Tooltip(
        message: spec.label,
        preferBelow: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(pill),
          child: SizedBox(
            width: tabWidth,
            height: tabHeight,
            child: Icon(spec.icon, size: 19, color: ink),
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
/// Floated just clear of the tab pill, and gone on its own after [undoLinger].
/// Both of those are the point: the pill is a `Stack` overlay rather than a
/// `bottomNavigationBar`, so the `Scaffold` laying the snackbar out does not
/// know the pill is there. What it does know is the add button, which it
/// lifts a floating bar above — and the button sits on the pill's own line, so
/// that lift clears both. Adding the pill's height on top of it, which this
/// did while the button floated higher up, left the bar hanging a pill and a
/// half above the thing it was clearing.
void showUndoBar(BuildContext context, String message, {VoidCallback? onUndo}) {
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
        // Eight above whatever the `Scaffold` cleared, which is the button
        // and so the pill beside it.
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        // No action when there is nothing to take back — the same bar, in
        // the same place, carrying a sentence instead of an offer.
        action: onUndo == null
            ? null
            : SnackBarAction(label: 'UNDO', onPressed: onUndo),
      ),
    );
}

/// How far the quick-entry row floats above the button, how tall its chips
/// stand, and the margin it keeps from the far edge of the screen — the same
/// one the button keeps on its own side.
const quickGap = 10.0;
const quickChip = 40.0;
const quickEdge = 16.0;

/// The add button, floating at the bottom right beside the tab pill.
///
/// A `FloatingActionButton` rather than another `RoundIconButton`: it is the
/// one control that floats over a scrolling page, and the platform widget
/// already brings the elevation, the semantics and the shuffle out of a
/// snackbar's way. Sized to the pill it sits beside — a 56 default next to a
/// 54 bar reads as a mistake at a glance.
///
/// Tap adds a new thing. Hold, on the pages given a [store], floats that
/// store's quick entries in a row above the button: drag onto one and let go
/// to add it, or let go where you are and tap one. Goals passes no store — a
/// saved transaction is not a goal — and holds nothing.
class AddButton extends StatefulWidget {
  const AddButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.store,
  });

  final String tooltip;
  final VoidCallback onPressed;

  /// Null on a page where a quick entry means nothing.
  final PennyStore? store;

  @override
  State<AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<AddButton> {
  final _portal = OverlayPortalController();

  /// Snapshotted on open, so a chip cannot move out from under the finger
  /// already travelling towards it.
  List<Shortcut> _entries = const [];
  List<GlobalKey> _keys = const [];

  /// The chip the finger is over, or -1. Also the one a release commits.
  int _hot = -1;

  void _open() {
    final entries = widget.store?.shortcuts ?? const <Shortcut>[];
    // Nothing saved is nothing to show: an empty row that opens on every hold
    // is a control that looks broken rather than one that is not set up yet.
    if (entries.isEmpty) return;
    setState(() {
      _entries = List.of(entries);
      _keys = [for (final _ in entries) GlobalKey()];
      _hot = -1;
    });
    _portal.show();
  }

  /// Which chip [global] is inside, by the boxes they actually painted at.
  /// The row scrolls and can overflow, so the rects are asked for rather than
  /// worked out from an index.
  int _chipAt(Offset global) {
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return i;
    }
    return -1;
  }

  /// The pointer that opened the row keeps reporting to the button it went
  /// down on, so the drag up onto a chip needs no gesture of its own there.
  void _track(PointerMoveEvent e) {
    if (!_portal.isShowing) return;
    final at = _chipAt(e.position);
    if (at != _hot) setState(() => _hot = at);
  }

  /// A release over a chip takes it. A release where the finger already was
  /// leaves the row up to be tapped — so the hold opens a menu as well as
  /// swiping through one.
  void _release(PointerUpEvent e) {
    if (!_portal.isShowing || _hot < 0) return;
    _pick(_entries[_hot]);
  }

  /// Added on one gesture, so it has to be undoable on one tap. Without this
  /// the row is a trap: a mis-release costs a trip through the ledger to find
  /// the row and delete it.
  void _pick(Shortcut entry) {
    _portal.hide();
    final store = widget.store!;
    final txn = entry.toTxn();
    store.addTxn(txn);
    showUndoBar(
      context,
      'Added ${rupees(txn.amountMinor)}',
      onUndo: () => store.removeTxn(txn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final holds = widget.store != null;

    // Laid out against the button rather than following it: a
    // `CompositedTransformFollower` establishes its transform only when it is
    // composited, so anything inside it that asks where it is on the screen —
    // a chip's own `Tooltip`, on the first hover — asserts instead. This
    // builder is handed the button's paint transform during layout, which is
    // the same anchoring with none of that.
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, info) {
        final origin = MatrixUtils.transformPoint(
          info.childPaintTransform,
          Offset.zero,
        );
        final button = origin & info.childSize;

        return Stack(
          children: [
            // Anywhere else closes it, the button underneath included.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _portal.hide,
              ),
            ),
            Positioned(
              // Right edges flush with the button's, and the row is only as
              // wide as its chips: a box the width of the screen would eat
              // every tap meant for the scrim behind it.
              right: info.overlaySize.width - button.right,
              bottom: info.overlaySize.height - button.top + quickGap,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: button.right - quickEdge),
                child: _QuickRow(
                  store: widget.store!,
                  entries: _entries,
                  chipKeys: _keys,
                  hot: _hot,
                  onPick: _pick,
                ),
              ),
            ),
          ],
        );
      },
      child: Semantics(
        // A hold is invisible to a screen reader, so the row is also an
        // action on the button rather than only a gesture over it.
        customSemanticsActions: holds
            ? {const CustomSemanticsAction(label: 'Quick entries'): _open}
            : const {},
        child: Listener(
          onPointerMove: holds ? _track : null,
          onPointerUp: holds ? _release : null,
          child: GestureDetector(
            onLongPress: holds ? _open : null,
            child: Theme(
              data: Theme.of(context).copyWith(
                floatingActionButtonTheme: const FloatingActionButtonThemeData(
                  sizeConstraints: BoxConstraints.tightFor(
                    width: dockButton,
                    height: dockButton,
                  ),
                ),
              ),
              // The pill's own soft shadow rather than Material's: the theme
              // sets no shadow colour, so an elevated FAB draws a hard black
              // ring next to a pill that floats on a wash of navy at 6%.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: cardShadow(isDark(context)),
                ),
                child: FloatingActionButton(
                  onPressed: widget.onPressed,
                  // No `tooltip:` where the hold means something: a tooltip
                  // is itself a long press, and the two would fire together.
                  tooltip: holds ? null : widget.tooltip,
                  backgroundColor: sproutDeepOf(context),
                  foregroundColor: onSproutDeep,
                  elevation: 0,
                  focusElevation: 0,
                  hoverElevation: 0,
                  highlightElevation: 0,
                  shape: const CircleBorder(),
                  // The label rides on the icon: a FAB's tooltip is a
                  // tooltip, not a semantics label, so a screen reader would
                  // otherwise announce an unnamed button.
                  child: Icon(
                    LucideIcons.plus,
                    size: 22,
                    semanticLabel: widget.tooltip,
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

/// The quick entries, in a row that grows leftwards out of the button.
///
/// A `Wrap` laid out right to left and bottom to top: the first entry saved
/// sits nearest the thumb, and a row too long for the screen turns up onto a
/// second line rather than scrolling — a line of chips that has to be dragged
/// sideways before it can be picked from is a menu that costs more than typing
/// the thing did.
class _QuickRow extends StatelessWidget {
  const _QuickRow({
    required this.store,
    required this.entries,
    required this.chipKeys,
    required this.hot,
    required this.onPick,
  });

  final PennyStore store;
  final List<Shortcut> entries;
  final List<GlobalKey> chipKeys;
  final int hot;
  final ValueChanged<Shortcut> onPick;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        // Out of the button, rather than onto the screen from nowhere.
        child: Transform.scale(
          scale: t,
          alignment: Alignment.bottomRight,
          child: child,
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        // Both of these, and the children in the order they were saved: the
        // first entry lands at the right of the bottom line, under the thumb
        // that is already there.
        textDirection: TextDirection.rtl,
        verticalDirection: VerticalDirection.up,
        children: [
          for (var i = 0; i < entries.length; i++)
            _QuickChip(
              key: chipKeys[i],
              store: store,
              entry: entries[i],
              hot: i == hot,
              onTap: () => onPick(entries[i]),
            ),
        ],
      ),
    );
  }
}

/// One saved entry: its category's glyph, and what it costs.
///
/// No note on the chip. The row floats a thumb's width above the button, and
/// three words of note per chip is a row that reaches the far edge of the
/// screen before it holds three entries — the name rides in the tooltip and in
/// the semantics, which is where a chip this small can carry it.
class _QuickChip extends StatelessWidget {
  const _QuickChip({
    super.key,
    required this.store,
    required this.entry,
    required this.hot,
    required this.onTap,
  });

  final PennyStore store;
  final Shortcut entry;
  final bool hot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = store.categoryById(entry.categoryId);
    final colour = catColorAt(category?.color ?? defaultCatColor);
    final name = entry.note.isNotEmpty
        ? entry.note
        : category?.name ?? 'Quick entry';
    final amount = entry.kind == TxKind.income
        ? rupeesWhole(entry.amountMinor, signed: true)
        : rupeesWhole(entry.amountMinor);

    return Semantics(
      button: true,
      label: 'Add $name, $amount',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: name,
        preferBelow: false,
        child: Material(
          color: isDark(context) ? darkCard : Colors.white,
          borderRadius: BorderRadius.circular(pill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(pill),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              height: quickChip,
              padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
              decoration: BoxDecoration(
                // The one under the finger fills rather than grows. A chip
                // that swells is a target that moves out from under the
                // finger already travelling towards it, and the one at the
                // end of the line grows off the edge of the screen.
                color: hot ? colour.withValues(alpha: 0.16) : null,
                borderRadius: BorderRadius.circular(pill),
                border: Border.all(
                  color: hot ? colour : colour.withValues(alpha: 0.35),
                  width: hot ? 2 : 1,
                ),
                boxShadow: cardShadow(isDark(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconFor(category?.icon ?? defaultIcon),
                    size: 16,
                    color: colour,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    amount,
                    style: mono(
                      13,
                      color: scheme.onSurface,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

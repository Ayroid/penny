import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'clock.dart';

// ── Penny palette ───────────────────────────────────────────────────────────
// Derived from the mascot art rather than chosen in the abstract. Penny is a
// copper coin with a green sprout, outlined in navy, drawn on warm cream.
//
//   navy   structures — it is the outline colour of every piece of the art
//   sprout is the brand — the leaf, the growth, the primary action
//   coin   is what you spend — completed amounts, expense fills, chart bars
//
// Wick's ground was cream and so is this: the art is drawn on cream, and a
// copper mascot on a green page vibrates (green and orange are opposites).
// Penny differs from Wick in the accent alone, which is exactly what the
// design system says an app owns.
//
// The marketing sheet's orange (#F5883A) is Wick's colour. It stays baked into
// the mascot PNGs and never enters Penny's chrome, or the two apps blur.

const navy = Color(0xFF16295C);
const navySoft = Color(0xFF33487C);
const sprout = Color(0xFF34B863);
const sproutSoft = Color(0xFFE6F6EC);
// The sprout with the lights off — the one green dark enough to carry white
// text (the accent itself is 2.57:1 against white and fails outright).
//
// This is what every FILLED piece of brand chrome is drawn in: the tab pill,
// the segmented pill, the FAB, primary buttons, the Goals hero, the heaviest
// heatmap cell. The lit sprout above stays the *wash* — tints, credit
// amounts, glyphs — so the app reads dark green without the washes going
// grey, which is what a single dark accent would do to them.
//
// Dark mode cannot use the same tone: #10412F on a near-black ground is
// 1.8:1 and the pill disappears. This one clears 3:1 on black and still
// carries white at 5.3:1.
const sproutDeep = Color(0xFF145234);
const sproutDeepDark = Color(0xFF1F7A4D);

const warmBg = Color(0xFFFFF8F1);
const warmSunk = Color(0xFFF4ECE3);
const warmGray = Color(0xFFDED6CC);

// The coin — expense fills and every chart bar.
//
// THE COIN NEVER CARRIES TEXT. That restriction is what makes the rest work.
// Income is the sprout and expense is the coin, side by side in every chart,
// and green-vs-orange is the classic deuteranope confusion pair — so the two
// have to be separated by lightness, not just hue. But the tone that is far
// enough from the sprout is too dark for navy to sit on (4.24:1) and too light
// for white (4.24:1 the other way); the two requirements pull opposite ways
// and no single value satisfies both.
//
// So the coin gives up carrying text and keeps the gap: L=.197 against the
// sprout's L=.359 is a 1.65 ratio, and 4.05:1 against the cream page, which is
// what WCAG 1.4.11 asks of a graphical object. Amounts sit beside a bar in
// ink, never inside it — which is how the charts label things anyway.
//
// The face tone (#EFA76B) fails all of this at 1.10 against the sprout.
// Asserted in test/palette_test.dart.
const coin = Color(0xFFB06A2E);
const coinSoft = Color(0xFFF7EADC);

// Dark is derived, not designed: the same palette on a neutral-black ground
// with each accent lifted until it holds contrast. Navy would read as "unlit
// blue" at night rather than as night, so the ground is truly neutral.
const darkBg = Color(0xFF0A0A0A);
const darkCard = Color(0xFF171717);
const darkSunk = Color(0xFF262626);
const darkInk = Color(0xFFFAFAFA);
const darkMuted = Color(0xFFA3A3A3);
const sproutDark = Color(0xFF45CC7A);
const sproutSoftDark = Color(0xFF10321F);
const coinDark = Color(0xFFC4813F);
const coinSoftDark = Color(0xFF33210F);

const radius = 16.0;
const pill = 999.0;
const fontFamily = 'PlusJakartaSans';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Brand accent — the sprout. Primary actions, balances, anything about the
/// money growing rather than the money leaving.
Color sproutOf(BuildContext c) => isDark(c) ? sproutDark : sprout;
Color sproutSoftOf(BuildContext c) => isDark(c) ? sproutSoftDark : sproutSoft;

/// The deep sprout — every filled piece of brand chrome. See [sproutDeep].
Color sproutDeepOf(BuildContext c) => isDark(c) ? sproutDeepDark : sproutDeep;

/// Ink on a deep-sprout fill. White, and not computed: carrying white is the
/// whole reason the deep tone exists (9.1:1 in light, 5.3:1 in dark).
const onSproutDeep = Colors.white;

/// The green that can carry a figure as *text*: the deep tone on cream, the
/// lit sprout at night.
///
/// The accent itself cannot do this job in light. It is 2.2:1 on the sunk fill
/// and 2.6:1 on its own soft wash, either of which would fail a small bold
/// label; the deep tone clears 7.9 and 8.2. At night the pair inverts — the
/// deep tone disappears into a dark ground and the accent clears 7.3. The same
/// swap [onTint] makes for a category's wash, for the brand's own green.
///
/// A goal's percentage pill and the line under a finished goal's bar. Not the
/// calendar: a figure there sits on the heatmap's own green, and the day's
/// direction is carried by a minus sign rather than by hue.
Color sproutInk(BuildContext c) => isDark(c) ? sproutDark : sproutDeep;

/// The coin. Expense fills and every chart bar — the design system reserves
/// the accent so it never has to fill a chart.
///
/// A fill only: nothing legible goes on top of it. Put the amount beside the
/// bar in ink. See the note on [coin] for why no ink survives on this tone.
Color coinOf(BuildContext c) => isDark(c) ? coinDark : coin;

/// The coin at wash strength — a ground that *does* carry ink.
Color coinSoftOf(BuildContext c) => isDark(c) ? coinSoftDark : coinSoft;

/// Soft shadow, brand-tinted in light and plain black in dark. The brand
/// separates surfaces with tint, not with rules — this is for the few surfaces
/// that genuinely float.
List<BoxShadow> cardShadow(bool dark) => dark
    ? const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 14,
          offset: Offset(0, 3),
        ),
      ]
    : const [
        BoxShadow(
          color: Color(0x1216295C),
          blurRadius: 16,
          offset: Offset(0, 3),
        ),
      ];

ThemeData appTheme({required bool dark}) {
  final bg = dark ? darkBg : warmBg;
  final card = dark ? darkCard : Colors.white;
  final fg = dark ? darkInk : navy;
  final muted = dark ? darkMuted : navySoft;
  final sunk = dark ? darkSunk : warmSunk;
  final border = dark ? darkSunk : warmGray;
  // Filled chrome is the deep tone; the lit sprout stays the wash.
  final fill = dark ? sproutDeepDark : sproutDeep;
  const onFill = onSproutDeep;

  TextStyle t(
    double size,
    FontWeight w, {
    Color? color,
    double spacing = -0.2,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: w,
    color: color ?? fg,
    letterSpacing: spacing,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: bg,
    // InkSparkle is Android's Material 3 splash, and it draws itself with a
    // shader loaded from an asset. That resolves fine on Android; on desktop
    // the lookup can fail after a hot restart and then throws on every single
    // tap. Nothing about the brand depends on which of the two ripples runs,
    // so everywhere else gets the shader-free one.
    splashFactory: defaultTargetPlatform == TargetPlatform.android
        ? InkSparkle.splashFactory
        : InkRipple.splashFactory,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: fill,
      onPrimary: onFill,
      secondary: muted,
      onSecondary: bg,
      tertiary: dark ? coinDark : coin,
      onTertiary: navy,
      surface: card,
      onSurface: fg,
      surfaceContainerHighest: sunk,
      outline: border,
      error: const Color(0xFFDC2626),
      onError: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: t(17, FontWeight.w700),
    ),
    // Insights' range picker. Material fills the days between the two ends
    // from secondaryContainer, which this scheme leaves to fall back on the
    // muted navy — a slab of dark blue with navy numbers on it. The soft
    // sprout is the ends' own green, lightened, so the range reads as one
    // thing and the dates stay legible on it.
    datePickerTheme: DatePickerThemeData(
      rangeSelectionBackgroundColor: dark ? sproutSoftDark : sproutSoft,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: sunk,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: t(14, FontWeight.w400, color: muted),
      border: _softBorder(Colors.transparent),
      enabledBorder: _softBorder(Colors.transparent),
      focusedBorder: _softBorder(fill, width: 1.5),
    ),
    // Primary action only — the brand asks that the sprout stay meaningful.
    //
    // Disabled is stated, not left to Material's onSurface washes: those land
    // a grey slab beside the accent-wash secondary and the pair stops reading
    // as one row. Both buttons go to the sunk ground with a faded ink label —
    // same shape, same ground, obviously inert.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: onFill,
        disabledBackgroundColor: sunk,
        disabledForegroundColor: muted.withValues(alpha: 0.6),
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        textStyle: t(15, FontWeight.w700, color: onFill),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    // Secondary: the accent at wash strength with ink text.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: dark ? sproutSoftDark : sproutSoft,
        disabledBackgroundColor: sunk,
        disabledForegroundColor: muted.withValues(alpha: 0.6),
        minimumSize: const Size.fromHeight(52),
        textStyle: t(15, FontWeight.w700),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: muted,
        textStyle: t(14, FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      // Sheets carry the PAGE ground, not the card ground, so they read as the
      // app rising up rather than a panel landing on it.
      backgroundColor: bg,
      surfaceTintColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: t(18, FontWeight.w700),
      contentTextStyle: t(14, FontWeight.w400, color: muted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? darkCard : navy,
      contentTextStyle: t(14, FontWeight.w600, color: Colors.white),
      actionTextColor: dark ? coinDark : coinSoft,
      // Floating, so `showUndoBar` can margin it clear of the tab pill. A
      // fixed bar is pinned to the bottom edge, which is where the pill is.
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? darkSunk : navy,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: t(11, FontWeight.w600, color: Colors.white),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    textTheme: TextTheme(
      headlineLarge: t(29, FontWeight.w800, spacing: -0.7),
      titleLarge: t(21, FontWeight.w700, spacing: -0.4),
      titleMedium: t(15, FontWeight.w600),
      bodyLarge: t(15, FontWeight.w400),
      bodyMedium: t(14, FontWeight.w400),
      bodySmall: t(13, FontWeight.w400, color: muted),
      labelLarge: t(13, FontWeight.w700),
      labelSmall: t(11.5, FontWeight.w500, color: muted),
    ),
  );
}

OutlineInputBorder _softBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
      borderRadius: BorderRadius.circular(14),
    );

const months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const weekdayShort = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

String longDate(DateTime d) =>
    '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';

String shortDate(DateTime d) =>
    '${monthShort[d.month - 1]} ${d.day}, ${d.year}';

/// `1 account` / `3 accounts`. [many] for words that do not just take an s.
String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : many ?? '${one}s'}';

String greeting() {
  final h = clock().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The landscape behind the balance, picked by the hour the way [greeting] is.
///
/// Four cuts of the same range: sunrise, full sun, dusk and a moon. It moves
/// with the injected clock, so a golden run at a fixed hour draws a fixed sky.
String landingImage() {
  final h = clock().hour;
  if (h < 12) return 'assets/images/morning_landing.png';
  if (h < 17) return 'assets/images/afternoon_landing.png';
  if (h < 20) return 'assets/images/evening_landing.png';
  return 'assets/images/night_landing.png';
}

/// A card the way the brand draws one: no border, soft shadow, large radius.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: cardShadow(isDark(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ── Per-category colour ─────────────────────────────────────────────────────
// Twenty-one swatches. A category owns one; the shell and anything not about a
// specific category falls back to the brand sprout.
//
// Every one of these is a light colour, which is why `gridWell` below exists:
// on cream a lit cell and an unlit one are both light, and no choice of alpha
// gets them 3:1 apart. The grid keeps its own dark well and the gap returns.
// Asserted per swatch in test/palette_test.dart.

class CatColor {
  const CatColor(this.name, this.value);

  final String name;
  final Color value;
}

const catColors = <CatColor>[
  CatColor('Red', Color(0xFFFF6B6B)),
  CatColor('Orange', Color(0xFFFF9138)),
  CatColor('Amber', Color(0xFFFFBE2E)),
  CatColor('Yellow', Color(0xFFFFD11A)),
  CatColor('Lime', Color(0xFFA3E635)),
  CatColor('Green', Color(0xFF4ADE80)),
  CatColor('Emerald', Color(0xFF34D399)),
  CatColor('Teal', Color(0xFF2DD4BF)),
  CatColor('Cyan', Color(0xFF22C7E5)),
  CatColor('Sky', Color(0xFF38B5E8)),
  CatColor('Blue', Color(0xFF60A5FA)),
  CatColor('Indigo', Color(0xFF818CF8)),
  CatColor('Violet', Color(0xFFA78BFA)),
  CatColor('Purple', Color(0xFFC084FC)),
  CatColor('Fuchsia', Color(0xFFD86FE8)),
  CatColor('Pink', Color(0xFFEC6AAE)),
  CatColor('Rose', Color(0xFFF76B83)),
  CatColor('Slate', Color(0xFF94A3B8)),
  CatColor('Gray', Color(0xFF9CA3AF)),
  CatColor('Neutral', Color(0xFFA3A3A3)),
  CatColor('Stone', Color(0xFFA8A29E)),
];

/// Emerald — the palette's sprout-adjacent hue, and what a category is before
/// anyone picks. Out-of-range indexes land here too, so a hand-edited export
/// can never colour a category with a crash.
const defaultCatColor = 6;

Color catColorAt(int index) =>
    catColors[index.clamp(0, catColors.length - 1)].value;

/// Carries one category's colour down its subtree, so a card wraps itself once
/// and its icon tile, chips, bars and border all follow — instead of each of
/// them taking a `Color` that has to be threaded through six widgets.
///
/// Absent — the shell, settings, onboarding — means the brand sprout.
class CategoryAccent extends InheritedWidget {
  const CategoryAccent({super.key, required this.color, required super.child});

  final Color color;

  static Color? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<CategoryAccent>()?.color;

  @override
  bool updateShouldNotify(CategoryAccent old) => old.color != color;
}

/// The colour of whatever we are inside: a category's own, or the brand.
Color accentOf(BuildContext c) => CategoryAccent.maybeOf(c) ?? sproutOf(c);

/// A colour that can carry small text against a tinted well.
///
/// At night that is the accent itself. In light it is not, and cannot be: the
/// palette's light values top out near 3.9:1 against the 12% wells they sit in,
/// short of the 4.5 a 12px label needs. Let the fill and the glyph carry the
/// colour; the text takes the normal foreground and lets weight do the work.
Color onTint(BuildContext c) =>
    isDark(c) ? accentOf(c) : Theme.of(c).colorScheme.onSurface;

/// WCAG relative contrast between two opaque colours.
double contrastBetween(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// What goes *on* a full-strength accent fill — an amount, a glyph.
///
/// Whichever of the two actually wins, not whichever a lightness threshold
/// guesses: the answer flips per swatch per theme, so it cannot be tabulated.
/// For the brand sprout it is navy in both themes, by a wide margin.
Color onAccent(BuildContext c) {
  final a = accentOf(c);
  return contrastBetween(navy, a) >= contrastBetween(Colors.white, a)
      ? navy
      : Colors.white;
}

// ── Tinted surfaces ─────────────────────────────────────────────────────────
// Nine tenths of the surfaces in the app are the accent at some alpha over the
// page ground. A screen picks a role, not a number.

/// The current accent at [alpha]. Everything below builds on it, so wrapping a
/// subtree in [CategoryAccent] recolours all of it at once.
Color tint(BuildContext c, double alpha) =>
    accentOf(c).withValues(alpha: alpha);

/// Card ground. Barely there in light, where a wash on cream goes muddy fast.
Color cardTint(BuildContext c) => tint(c, isDark(c) ? 0.07 : 0.035);

/// The hairline around a card, and around the grid well inside it.
Color cardEdge(BuildContext c) => tint(c, isDark(c) ? 0.16 : 0.13);

/// The panel a heatmap sits in. On cream there is no panel: the grid sits
/// straight on the card so the card's hover and press ink reach it. Dark mode
/// keeps a well; the palette needs a ground darker than the card to be seen.
Color gridWell(BuildContext c) =>
    isDark(c) ? Color.alphaBlend(tint(c, 0.07), darkBg) : Colors.transparent;

/// An unlit grid cell — present, clearly not filled. Always read against
/// [gridWell], never against the page. Heavier on cream, where the well is
/// light and a 16% wash would barely register as a cell.
Color cellEmpty(BuildContext c) => tint(c, isDark(c) ? 0.16 : 0.38);

/// Grid furniture: month names and weekday initials. `secondary` at full
/// strength competes with the cells it labels.
Color gridLabel(BuildContext c) => isDark(c)
    ? Colors.white.withValues(alpha: 0.45)
    : navySoft.withValues(alpha: 0.85);

/// Icon tiles and chips sit one step up from the card ground.
Color chipFill(BuildContext c) => tint(c, isDark(c) ? 0.15 : 0.12);

/// Small labels — amounts, dates, month names, percentages. Monospace on
/// purpose: it is what makes a wall of digits read as data rather than prose,
/// and the family is the platform's own so nothing has to be bundled.
const monoFamily = 'monospace';

TextStyle mono(
  double size, {
  required Color color,
  FontWeight weight = FontWeight.w500,
  double spacing = 0.4,
}) => TextStyle(
  fontFamily: monoFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
);

/// A strut that pins a line's height to the font size, whatever glyphs land
/// in it.
///
/// Needed wherever text swaps between digits and the mask: `•` is not in the
/// platform mono, so it is drawn by a fallback font with its own ascent and
/// descent, and the line grows or shrinks as the amounts are hidden. That
/// moves everything below it on the screen. The same applies to `₹`, which not
/// every mono carries either.
StrutStyle monoStrut(double size) =>
    StrutStyle(fontFamily: monoFamily, fontSize: size, forceStrutHeight: true);

/// A round icon button in a soft well — the only chrome shape used for
/// navigation.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.filled = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  /// Primary action — the accent disc rather than the neutral well.
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        // The disc is 40 (or 36 for the period arrows), but the thing you can
        // hit is never below 48 — the one rule the design system calls
        // non-negotiable. The extra is invisible padding around the circle.
        child: SizedBox(
          width: size < 48 ? 48 : size,
          height: size < 48 ? 48 : size,
          child: Center(
            child: Material(
              color: filled
                  ? sproutDeepOf(context)
                  : (isDark(context) ? darkSunk : const Color(0xFFF0E7DC)),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    icon,
                    size: size * 0.5,
                    color: filled ? onSproutDeep : scheme.onSurface,
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

/// The card content lives in: tinted ground, hairline edge, no shadow. Cards
/// are told apart from the page by tint, not by elevation.
class TintCard extends StatelessWidget {
  const TintCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.onLongPress,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overrides the tinted ground while keeping the accent's hairline — for a
  /// card that wants the colour at its edge but not under its content.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Over the *page* ground, not the raised surface colour: starting a
        // step lighter would undo the tint that does the separating.
        color:
            color ??
            Color.alphaBlend(
              cardTint(context),
              Theme.of(context).scaffoldBackgroundColor,
            ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardEdge(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A pill of mutually exclusive choices — the one picker shape. More than
/// three options is a list, not a segmented control.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// Choice -> label, in the order they should read.
  final Map<T, String> options;

  /// A value that is not among [options] lights nothing — for when the thing
  /// chosen came from elsewhere. Null is a real option where T allows it.
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys = options.keys.toList();
    final index = keys.indexWhere((k) => k == value);
    final accent = sproutDeepOf(context);
    const ink = onSproutDeep;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(pill),
      ),
      child: Stack(
        children: [
          // The pill slides between positions rather than each segment fading
          // its own background in and out — the same movement the tab bar
          // makes, and the same 250ms easeOut it animates a page change with.
          // A pill that fades in place reads as two things blinking; one that
          // travels reads as the selection moving, which is what happened.
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                alignment: keys.length == 1
                    ? Alignment.center
                    : Alignment(-1 + 2 * index / (keys.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / keys.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(pill),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final key in keys)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: key == value,
                    label: options[key]!,
                    excludeSemantics: true,
                    onTap: () => onChanged(key),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(key),
                      child: ConstrainedBox(
                        // A floor rather than tuned padding: the label's
                        // height depends on the font, and 48 is the one
                        // number the design system calls non-negotiable.
                        // minHeight, so it still grows if the person
                        // scales their text up.
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            style: TextStyle(
                              fontFamily: fontFamily,
                              fontSize: 13,
                              // Weight as well as colour, so the selection is
                              // legible without relying on colour alone.
                              fontWeight: key == value
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: key == value ? ink : scheme.secondary,
                            ),
                            child: Text(
                              options[key]!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small pill: tinted well, accent glyph, mono label.
class TintChip extends StatelessWidget {
  const TintChip({
    super.key,
    required this.icon,
    required this.label,
    this.semanticsLabel,
    this.dim = false,
  });

  final IconData icon;
  final String label;
  final String? semanticsLabel;

  /// Nothing to report yet — a zero reads muted rather than lit.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // The unlit cell's own ground, with the accent as ink for both glyph and
    // label, so the pill and any grid below it read as one surface.
    // Deliberately below the 4.5:1 a 12px label normally wants on cream: the
    // semantics label carries the same words for anyone who cannot read them.
    final ground = dim ? scheme.surfaceContainerHighest : cellEmpty(context);
    final ink = dim ? scheme.secondary : onTint(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: dim ? scheme.secondary : accentOf(context),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            semanticsLabel: semanticsLabel,
            strutStyle: monoStrut(12),
            style: mono(12, color: ink, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

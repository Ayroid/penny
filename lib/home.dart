import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'analytics.dart';
import 'entry_sheet.dart';
import 'icons.dart';
import 'money.dart';
import 'penny.dart';
import 'page_bar.dart';
import 'store.dart';
import 'theme.dart';
import 'txn_row.dart';

/// The overview: what you have, what moved this period, and the last few rows.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final PennyStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Period _period = Period.month;

  /// Which day, week or month is being looked at. Moving the arrows moves this
  /// rather than a separate offset, so switching period keeps roughly the
  /// place you were in.
  DateTime _anchor = today();

  /// The day tapped in the grid, or null for the whole period. Cleared when
  /// the period or the anchor moves: a day picked in March has nothing to say
  /// about April, and a list showing rows from outside the period on screen
  /// is worse than losing the selection.
  String? _picked;

  void _step(int by) => setState(() {
    _anchor = shiftAnchor(_period, _anchor, by);
    _picked = null;
  });

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final text = Theme.of(context).textTheme;
    final range = rangeFor(_period, _anchor);
    final totals = totalsIn(store.txns, range);
    final rows = within(store.txns, range);
    // The whole period's last few, or everything that happened on the day
    // tapped in the grid — all of it, since a day is a short list by nature.
    final shown = _picked == null
        ? rows.take(8).toList()
        : rows.where((t) => t.day == _picked).toList();

    // The recent list carries the same day headers the ledger does, built up
    // front rather than inside the children list: a day changes on a row, and
    // spotting that mid-list is what an index-fiddling loop gets wrong.
    final recent = <Widget>[];
    String? lastDay;
    for (final t in shown) {
      if (t.day != lastDay) {
        lastDay = t.day;
        recent.add(
          Padding(
            padding: EdgeInsets.only(
              left: 8,
              bottom: 4,
              top: recent.isEmpty ? 0 : 14,
            ),
            child: Text(dayHeader(t.day), style: text.labelSmall),
          ),
        );
      }
      recent.add(
        TxnRow(
          store: store,
          txn: t,
          onTap: () => showEntrySheet(context, store, existing: t),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: AddButton(
        tooltip: 'Add a transaction',
        onPressed: () => showEntrySheet(context, store),
        // Held rather than tapped, it floats the quick entries.
        store: store,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        children: [
          _BalanceCard(store: store),

          // A brand-new ledger skips the period controls entirely.
          // Three cards of zeroes and an unlit heatmap push the one
          // thing there is to do below the fold, and the empty state
          // is the screen most people see first.
          if (store.txns.isEmpty) ...[
            PennyMessage(
              headline: 'Nothing tracked yet',
              body: 'Add what you spent or earned and it will show up here.',
              actionLabel: 'Add a transaction',
              onAction: () => showEntrySheet(context, store),
              size: 132,
            ),
          ] else ...[
            const SizedBox(height: 12),

            Segmented<Period>(
              options: {for (final p in Period.values) p: p.label},
              value: _period,
              onChanged: (p) => setState(() {
                _period = p;
                _picked = null;
              }),
            ),
            const SizedBox(height: 12),

            PeriodNav(period: _period, anchor: _anchor, onStep: _step),
            const SizedBox(height: 12),

            _FlowCard(totals: totals, hidden: store.hideAmounts),

            // Week and month both get the grid — a week is simply one
            // row of it. A single day would be one cell, which tells
            // you nothing the figures above have not.
            if (_period != Period.day) ...[
              const SizedBox(height: 12),
              _DayGrid(
                spend: spendByDay(store.txns, range),
                net: netByDay(store.txns, range),
                hidden: store.hideAmounts,
                range: range,
                picked: _picked,
                onPick: (day) =>
                    setState(() => _picked = _picked == day ? null : day),
              ),
            ],

            const SizedBox(height: 24),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: PennyMessage(
                  pose: Penny.rest,
                  headline: _picked == null
                      ? 'Nothing this ${_period.label.toLowerCase()}'
                      : 'Nothing on ${dayHeader(_picked!).toLowerCase()}',
                  body: 'A quiet stretch. Nothing moved in or out.',
                  actionLabel: 'Add a transaction',
                  onAction: () => showEntrySheet(context, store),
                  size: 120,
                ),
              )
            else
              ...recent,
          ],
        ],
      ),
    );
  }
}

/// What you have, in total and per account.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.store});

  final PennyStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = store.totalBalance;
    // What is on the card is pinned in settings, up to four. A person with one
    // account gets no tiles at all: the row would say what the balance above
    // it already said.
    final tiles = store.liveAccounts.length > 1
        ? store.pinnedAccounts
        : const <Account>[];

    return TintCard(
      // The card carries its own padding: the landscape behind the numbers
      // has to run to the card's edge, and a margin would frame it as a
      // picture hung on the card rather than the sky behind it.
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // The range behind the numbers, at the hour it actually is. The
          // greeting above the card already moves with the clock; this is the
          // same sentence in a picture. Only the top of the drawing is used —
          // the peaks — so the tiles below sit on clean ground.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              // Sat on the card's bottom edge, which is where a horizon goes:
              // anchored anywhere else it reads as a sticker with a straight
              // cut across it.
              //
              // Faded out at the top, not at the left. The left fade was for
              // tiles that no longer need it — they carry their own ground —
              // and it left a moon sitting behind "₹21,094 free", which is a
              // figure read against whatever the sky happened to be doing
              // there. The ramp ends above the tiles, so the art is only ever
              // under the row that is opaque anyway.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // The art is 137 logical tall against a card of about 173,
                  // so these are the text's own edges in the picture's
                  // coordinates: clear through the balance and the line under
                  // it, at full strength by the time the tiles start.
                  colors: [Colors.transparent, Colors.white],
                  stops: [0.42, 0.64],
                ).createShader(rect),
                child: Image.asset(
                  landingImage(),
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
          Padding(
            // With tiles the row itself is the card's bottom edge and the
            // range runs behind it; without them the strip along the bottom
            // is kept clear — the range is the card's ground line, not
            // something to write over.
            padding: EdgeInsets.fromLTRB(16, 16, 16, tiles.isEmpty ? 88 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL BALANCE', style: text.labelSmall),
                // Scaled down rather than wrapped: a balance in crores is one
                // line at a smaller size, and a second line would push the
                // account row and the range below it down the card.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    store.hideAmounts ? maskedAmount : rupees(total),
                    maxLines: 1,
                    strutStyle: monoStrut(29),
                    style: mono(
                      29,
                      color: scheme.onSurface,
                      weight: FontWeight.w800,
                      spacing: -0.5,
                    ),
                  ),
                ),
                // What the goals have spoken for, and what is left after them. The
                // whole point of a goal is knowing the second number — money set
                // aside is still in the balance above, and without this line the
                // balance quietly overstates what there is to spend.
                // Drawn even with nothing set aside — empty, but the strut
                // holds the line — so the card is one height whether or not
                // there are goals.
                Text(
                  store.totalSetAside > 0
                      ? '${store.show(rupeesWhole(store.totalSetAside))} set aside · '
                            '${store.show(rupeesWhole(total - store.totalSetAside))} free'
                      : '',
                  strutStyle: monoStrut(11.5),
                  style: mono(11.5, color: scheme.secondary),
                ),
                if (tiles.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  // Tiles rather than a wrap of pills: the name and the figure
                  // sit on two lines instead of one long one, so four accounts
                  // fit across the card and each reads as its own small
                  // ledger.
                  LayoutBuilder(
                    builder: (context, box) {
                      final columns = box.maxWidth >= 320 ? 4 : 3;
                      final width =
                          (box.maxWidth - 8 * (columns - 1)) / columns;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in tiles)
                            SizedBox(
                              width: width,
                              child: _AccountTile(
                                name: a.name,
                                icon: iconFor(a.icon),
                                colour: catColorAt(a.color),
                                amount: store.hideAmounts
                                    ? maskedAmount
                                    : rupeesWhole(store.balanceOf(a.id)),
                                semanticsLabel: store.hideAmounts
                                    ? '${a.name}, hidden'
                                    : '${a.name}, '
                                          '${rupees(store.balanceOf(a.id))}',
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          // Masking is a per-device preference, not a lock: it is for a
          // shared desk or someone reading over a shoulder, and it says so
          // by being one tap away in both directions. Pinned to the corner
          // rather than sharing a row with the label: at 32px it was the
          // tallest thing on that line and pushed the words down the card.
          //
          // Last in the stack, not first: the balance line runs under this
          // corner, and the one painted last is the one a tap lands on.
          Positioned(
            top: 12,
            right: 12,
            child: RoundIconButton(
              icon: store.hideAmounts ? LucideIcons.eyeOff : LucideIcons.eye,
              tooltip: store.hideAmounts ? 'Show amounts' : 'Hide amounts',
              size: 32,
              onPressed: () => store.setHideAmounts(!store.hideAmounts),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tile's ground: the account's colour over the card's, then thirty
/// percent darker than that mix.
///
/// The landscape runs behind these tiles rather than stopping at them, and a
/// pale wash with a mountain showing through it is a tile nobody can read a
/// figure off.
Color _tileGround(BuildContext context, Color colour) {
  final mixed = Color.alphaBlend(
    colour.withValues(alpha: isDark(context) ? 0.22 : 0.18),
    Color.alphaBlend(
      cardTint(context),
      Theme.of(context).scaffoldBackgroundColor,
    ),
  );
  final hsl = HSLColor.fromColor(mixed);
  return hsl.withLightness((hsl.lightness * 0.9).clamp(0.0, 1.0)).toColor();
}

/// One account: what it is called, and what is in it.
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.name,
    required this.icon,
    required this.colour,
    required this.amount,
    required this.semanticsLabel,
  });

  final String name;
  final IconData icon;
  final Color colour;
  final String amount;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      // A fixed box, by design: the mask is a different width from a number
      // and every account holds a different figure, so a tile that sized
      // itself would shuffle the row on every tap of the eye. The height is
      // stated here and the amount shrinks into it.
      //
      // Which is also why the scaler is clamped: text can still grow with the
      // system setting, but past this the figure scales down instead of
      // pushing through the bottom of the box.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Container(
          height: 50,
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
          decoration: BoxDecoration(
            color: _tileGround(context, colour),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: colour),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: const StrutStyle(
                        fontFamily: fontFamily,
                        fontSize: 11,
                        forceStrutHeight: true,
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              // A fixed line, whatever the figure: the mask is a different width
              // from a number, and a box that scales its own height moves the
              // whole page when the eye is tapped.
              // Whatever is left of the fixed box, and the figure is scaled
              // down to fit it: a lakh in one account must not make its tile
              // taller or wider than the empty one beside it.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    strutStyle: monoStrut(13),
                    style: mono(
                      12.5,
                      color: scheme.onSurface,
                      weight: FontWeight.w700,
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

/// In, out, and the difference — read at a glance, like a speed meter.
///
/// Three figures on one line rather than three stacked bars. The bars measured
/// the period against itself, which is a comparison nobody needs: what this
/// card is for is the two numbers and their difference. Comparing a period to
/// other periods is the trend chart's job, on Insights.
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.totals, required this.hidden});

  final Totals totals;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TintCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Meter(
            // Credit is money arriving and debit is money leaving — the way
            // a bank statement reads, not the way double-entry bookkeeping
            // does. Down is arriving and up is leaving, the way a network
            // meter reads; direction carries the meaning on its own, so the
            // colour is reinforcement rather than the only signal.
            icon: LucideIcons.arrowDownLeft,
            colour: sproutOf(context),
            label: 'CREDIT',
            amount: totals.income,
            hidden: hidden,
          ),
          _MeterDivider(colour: scheme.outline),
          _Meter(
            icon: LucideIcons.arrowUpRight,
            colour: coinOf(context),
            label: 'DEBIT',
            amount: totals.expense,
            hidden: hidden,
          ),
          _MeterDivider(colour: scheme.outline),
          _Meter(
            label: 'NET',
            amount: totals.net,
            signed: true,
            hidden: hidden,
            // Not red when negative. A period that ended down is ordinary,
            // not a failure — the design system is explicit about this.
            colour: scheme.secondary,
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.amount,
    required this.colour,
    this.icon,
    this.signed = false,
    this.hidden = false,
  });

  final String label;
  final int amount;
  final Color colour;
  final IconData? icon;
  final bool signed;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Expanded(
      child: Semantics(
        label: hidden
            ? '$label, hidden'
            : '$label, ${rupees(amount, signed: signed)}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: colour),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: text.labelSmall),
                ],
              ),
              const SizedBox(height: 3),
              // Scaled down rather than wrapped or clipped: three amounts on
              // one line is tight on a narrow phone, and a lakh is not unusual.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  hidden ? maskedAmount : rupees(amount, signed: signed),
                  strutStyle: monoStrut(14),
                  style: mono(
                    14,
                    color: scheme.onSurface,
                    weight: FontWeight.w700,
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

class _MeterDivider extends StatelessWidget {
  const _MeterDivider({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: colour);
}

/// A month of days, shaded by what was spent, with each day's net written in
/// on request.
///
/// The shading is Wick's contribution grid re-pointed at money — an alpha
/// between the unlit-cell wash and the accent, so a heavy day is solid and a
/// light one barely there. It answers "how much" and never "which way", which
/// is the question a day with a salary in it is actually asking; the figures
/// answer it, in the same cells, and cost a tap.
///
/// One grid rather than two views of one: the toggle used to swap the shading
/// out for a flat card of figures, which made a tap look like a change of
/// subject. The colour stays put and the numbers come and go on top of it.
///
/// Tapping a day sends it up to the page, which shows that day's rows below
/// instead of the period's last few.
class _DayGrid extends StatefulWidget {
  const _DayGrid({
    required this.spend,
    required this.net,
    required this.range,
    required this.hidden,
    required this.picked,
    required this.onPick,
  });

  final Map<String, int> spend;
  final Map<String, int> net;

  /// The days to draw. A month lays out as a calendar with leading blanks; a
  /// week is the same grid with exactly seven cells and none.
  final Range range;
  final bool hidden;
  final String? picked;
  final ValueChanged<String> onPick;

  @override
  State<_DayGrid> createState() => _DayGridState();
}

class _DayGridState extends State<_DayGrid> {
  /// Shading alone is the default: it is the picture you can read without
  /// reading, and the figures are what you turn to when it has caught your
  /// eye. Not persisted — this is a glance, not a setting.
  bool _figures = false;

  @override
  Widget build(BuildContext context) {
    final spend = widget.spend;
    final range = widget.range;
    final hidden = widget.hidden;
    final scheme = Theme.of(context).colorScheme;
    final from = parseDay(range.from);
    final todayKey = dayKey(today());

    // Walked a day at a time rather than by subtracting dates: a Duration is
    // 24 real hours and lands on the wrong calendar day across a DST change.
    final dates = <DateTime>[];
    for (
      var d = from;
      dayKey(d).compareTo(range.to) <= 0;
      d = shiftDays(d, 1)
    ) {
      dates.add(d);
    }

    final peak = spend.values.fold(0, (a, b) => a > b ? a : b);
    final lead = from.weekday - 1;

    return TintCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The shading is spend either way — the figures are the net on
              // top of it, which is what the button's tooltip says.
              Text(
                'SPEND BY DAY',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              // The heaviest day of the month: a fact about the month rather
              // than about the way the grid is drawn, so it stays put when the
              // figures come and go.
              //
              // `Expanded` and no `Spacer`: the two would share the free space
              // between them and leave this half of it, which is how the
              // figure came to read "busiest ₹2…" with room to spare beside
              // it. Right-aligned inside, so it sits against the switch.
              Expanded(
                child: peak == 0
                    ? const SizedBox.shrink()
                    : Text(
                        // Compact, like the chart's axis: the switch beside
                        // it takes the width that spelled the figure out in
                        // full. Masked rather than removed, so the row keeps
                        // its shape either way.
                        'busiest '
                        '${hidden ? maskedAmount : compactRupees(peak)}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: monoStrut(11),
                        style: mono(11, color: scheme.secondary),
                      ),
              ),
              const SizedBox(width: 6),
              RoundIconButton(
                // The state it goes to, not the one it is in.
                icon: _figures ? LucideIcons.grid2x2 : LucideIcons.hash,
                tooltip: _figures ? 'Hide the figures' : 'Show each day\'s net',
                size: 30,
                onPressed: () => setState(() => _figures = !_figures),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final w in weekdayShort)
                Expanded(
                  child: Center(
                    child: Text(w, style: mono(9.5, color: gridLabel(context))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (final d in dates)
                _Cell(
                  day: d.day,
                  amount: spend[dayKey(d)] ?? 0,
                  net: widget.net[dayKey(d)],
                  peak: peak,
                  hidden: hidden,
                  figures: _figures,
                  isToday: dayKey(d) == todayKey,
                  picked: dayKey(d) == widget.picked,
                  onTap: () => widget.onPick(dayKey(d)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One day of the calendar: shaded by what it cost, and — when the figures are
/// on — carrying what it came to.
///
/// [net] is null on a day nothing happened, which is not the same as a day
/// that came out even: one is blank, the other says zero.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.amount,
    required this.net,
    required this.peak,
    required this.hidden,
    required this.figures,
    required this.isToday,
    required this.picked,
    required this.onTap,
  });

  final int day;
  final int amount;
  final int? net;
  final int peak;
  final bool hidden;
  final bool figures;
  final bool isToday;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // An empty day is the unlit wash; the heaviest is the deep sprout the
    // rest of the filled chrome is drawn in; everything between rides the
    // ramp between them, scaled off the month's peak.
    final t = peak == 0 ? 0.0 : (amount / peak).clamp(0.0, 1.0);
    // At night the top of the ramp stays the lit sprout: the deep tone is
    // only 2.5:1 against an unlit cell on black, and the grid is the one
    // place the pair has to be told apart.
    final lit = isDark(context) ? sproutOf(context) : sproutDeepOf(context);
    final colour = amount == 0
        ? cellEmpty(context)
        : Color.lerp(cellEmpty(context), lit, t)!;

    // Everything written in the cell reads against whatever that came out as.
    // The ramp runs from a pale wash to a solid green, so neither ink works at
    // both ends and the choice is measured per cell — the same rule `onAccent`
    // follows.
    //
    // Black rather than the brand's navy, which is the one place in the app
    // that swap is made: navy loses the middle of the ramp — 3.8:1 around the
    // two-thirds mark, where it is too dark for the light end's contrast and
    // too light for the dark end's — and a figure written in the cell is the
    // reading, not furniture. The neutral pair clears 4.7 at every step, in
    // both themes. `palette_test` walks the ramp and asserts both halves of
    // that, so the swap stays a decision.
    //
    // This is also why the figure is not green-and-red: the ink is whatever
    // survives the ground it lands on, so the day's direction is carried by
    // the minus sign instead of by hue.
    //
    // Measured against what the cell is *painted*, not against `colour`: the
    // wash and everything on the ramp below solid are the accent at an alpha,
    // and a translucent green measures as the full-strength one it was mixed
    // from. That is how an unlit cell at night — a whisper of green on black —
    // came out asking for dark ink. The card and the page go under it first.
    final painted = Color.alphaBlend(
      colour,
      Color.alphaBlend(
        cardTint(context),
        Theme.of(context).scaffoldBackgroundColor,
      ),
    );
    final ink =
        contrastBetween(Colors.black, painted) >=
            contrastBetween(Colors.white, painted)
        ? Colors.black
        : Colors.white;
    // The date and today's ring are furniture; the figure is the reading, and
    // keeps the ink at full strength.
    final soft = ink.withValues(alpha: ink == Colors.black ? 0.7 : 0.85);

    return Semantics(
      button: true,
      selected: picked,
      label: [
        'Day $day',
        if (isToday) 'today',
        amount == 0 ? 'nothing spent' : rupees(amount),
        // Signed, so the direction reaches a reader who is not being shown
        // the minus sign in the cell — or any of it, when hidden.
        if (net != null) 'net ${rupees(net!, signed: true)}',
      ].join(', '),
      excludeSemantics: true,
      child: Tooltip(
        message: amount == 0 || hidden ? '$day' : '$day · ${rupees(amount)}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: picked ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(5),
                // Today is ringed in the cell's own ink so it survives both ends
                // of the ramp; the picked day gets the same ring at full weight.
                // A transparent one otherwise, so the grid does not shift by a
                // pixel as the ring moves.
                border: Border.all(
                  // Today's ring stays green even when picked, so the one cell
                  // that is always worth finding never reads as the same black
                  // ring an ordinary picked day gets.
                  color: isToday
                      ? sproutInk(context)
                      : picked
                      ? ink
                      : Colors.transparent,
                  width: picked ? 2 : 1,
                ),
              ),
              // Stacked rather than a column: the date keeps its corner whether
              // or not a figure is under it, and the figure gets the whole width
              // — centred on the cell, the day number took the room a lakh needs.
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Text('$day', style: mono(8.5, color: soft)),
                  ),
                  if (figures && net != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      // Shrunk rather than clipped: a day with a lakh in it is a
                      // narrower string at a smaller size, not an ellipsis.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          // The minus is the direction — `compactRupees` carries
                          // it, and money in has no sign at all. The direction
                          // survives hiding for the same reason a percentage
                          // does: it is not an amount.
                          hidden
                              ? (net! < 0 ? '-••' : '••')
                              : compactRupees(net!),
                          maxLines: 1,
                          strutStyle: monoStrut(9.5),
                          style: mono(9.5, color: ink, weight: FontWeight.w700),
                        ),
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

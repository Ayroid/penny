import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'analytics.dart';
import 'entry_sheet.dart';
import 'icons.dart';
import 'money.dart';
import 'penny.dart';
import 'page_bar.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';
import 'txn_row.dart';

void openInsights(BuildContext context, PennyStore store) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => InsightsPage(store: store)));

/// Where the money went: a trend over recent periods, and the breakdown that
/// explains the biggest bar.
///
/// Opened from the overview rather than swiped to. It is the screen you go to
/// with a question, not one you pass through on the way to the ledger — and a
/// tab pill with four things in it had no room left for the add button.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, required this.store});

  final PennyStore store;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  Period _period = Period.month;

  /// Which day, week or month is being read. Switching period keeps it, so
  /// stepping back three months and asking for the week lands in that month
  /// rather than back at today.
  DateTime _anchor = today();

  /// Each breakdown lists the top five until asked for the rest — a month with
  /// twenty categories in it buries everything under it in small bars.
  final _expanded = <TxKind, bool>{};

  /// A span picked by hand from the label. While it is set it is the window
  /// every figure on the page reads, and no period pill is lit.
  Range? _custom;

  Range get _range => _custom ?? rangeFor(_period, _anchor);

  /// The window the change card compares against: the period before, or the
  /// same number of days before a picked range.
  Range get _before => switch (_custom) {
    final c? => shiftSpan(c, -1),
    null => shiftRange(_period, _anchor, -1),
  };

  String get _previous => switch (_custom) {
    final c? when daysIn(c) == 1 => 'the day before',
    final c? => 'the ${daysIn(c)} days before',
    null => switch (_period) {
      Period.day => 'yesterday',
      Period.week => 'last week',
      Period.month => 'last month',
    },
  };

  /// How many bars the chart carries. A week of days, or half a year of the
  /// longer windows: fewer, wider bars read better than a hairline forest.
  int get _bars => _period == Period.day && _custom == null ? 7 : 6;

  void _step(int by) {
    final c = _custom;
    if (c != null) {
      if (by > 0 && c.to.compareTo(dayKey(today())) >= 0) return;
      setState(() => _custom = shiftSpan(c, by));
      return;
    }
    if (by > 0 && !PeriodNav.canGoForward(_period, _anchor)) return;
    setState(() => _anchor = shiftAnchor(_period, _anchor, by));
  }

  Future<void> _pickRange() async {
    final now = today();
    final r = _range;
    final end = parseDay(r.to);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      currentDate: now,
      initialDateRange: DateTimeRange(
        start: parseDay(r.from),
        // This month runs past today; the picker cannot start there.
        end: end.isAfter(now) ? now : end,
      ),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _custom = (from: dayKey(picked.start), to: dayKey(picked.end)),
    );
  }

  /// One side of the ledger, broken down by category: a heading, the reveal,
  /// and the rows. Income and expense get the identical treatment.
  Widget _section({
    required Range range,
    required TxKind kind,
    required String title,
    required String empty,
  }) {
    final store = widget.store;
    final text = Theme.of(context).textTheme;
    final data = byCategory(store.txns, range, kind);
    final all = _expanded[kind] ?? false;
    final pie = store.pie.contains(kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(title, style: text.labelSmall),
            ),
            const Spacer(),
            if (data.isNotEmpty)
              IconButton(
                tooltip: pie ? 'Show as list' : 'Show as pie chart',
                iconSize: 16,
                color: Theme.of(context).colorScheme.secondary,
                onPressed: () {
                  store.setPie(kind, !pie);
                  setState(() {});
                },
                icon: Icon(pie ? LucideIcons.list : LucideIcons.chartPie),
              ),
            if (data.length > 5)
              TextButton(
                onPressed: () => setState(() => _expanded[kind] = !all),
                child: Text(all ? 'Show less' : 'See all'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (data.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text(empty, style: text.bodySmall)),
          )
        else
          _Breakdown(
            store: store,
            spend: data,
            shown: (all ? data.entries : data.entries.take(5)).toList(),
            total: data.values.fold(0, (a, b) => a + b),
            pie: pie,
            onTap: (id) => showPeriodTxns(
              context,
              store,
              range: range,
              title: store.categoryById(id)?.name ?? 'Category',
              categoryId: id,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final custom = _custom;
    final range = _range;
    final buckets = custom == null
        ? series(store.txns, _period, _anchor, _bars)
        : spanSeries(store.txns, custom, _bars);
    final totals = totalsIn(store.txns, range);
    final spendChange = changeBetween(
      store.txns,
      range,
      _before,
      kind: TxKind.expense,
    );
    final incomeChange = changeBetween(
      store.txns,
      range,
      _before,
      kind: TxKind.income,
    );
    final before = totalsIn(store.txns, _before);
    final unit = custom == null ? _period.label.toLowerCase() : 'range';
    final scope = custom == null
        ? 'THIS ${_period.label.toUpperCase()}'
        : 'IN THIS RANGE';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Stack(
              children: [
                // The same range Goals climbs and the balance card sits in.
                // Bleeding off the top and right so it reads as scenery the
                // bar stands in rather than a picture pasted beside it.
                Positioned(
                  right: -6,
                  bottom: 0,
                  width: 128,
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/images/mountains.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomRight,
                      opacity: const AlwaysStoppedAnimation(0.8),
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                PageBar(
                  title: 'Insights',
                  subtitle: 'What came in, where it went',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            Expanded(
              child: store.txns.isEmpty
                  ? const PennyMessage(
                      pose: Penny.thinking,
                      headline: 'Nothing to read yet',
                      body:
                          'Add a few transactions and the patterns show up here.',
                      size: 120,
                    )
                  : GestureDetector(
                      // The arrows are the obvious way through; the swipe is
                      // the one people try anyway. Horizontal only, so it
                      // never argues with the list scrolling under it.
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 120) return;
                        // Dragged right, the earlier period comes in from the
                        // left — the direction the content would travel.
                        _step(v > 0 ? -1 : 1);
                      },
                      child: ListView(
                        // No tab pill under a pushed page to clear.
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        children: [
                          Segmented<Period>(
                            options: {
                              for (final p in Period.values) p: p.label,
                            },
                            value: custom == null ? _period : null,
                            onChanged: (p) => setState(() {
                              // Back to a period from a picked range lands
                              // on the one the range ended in.
                              if (custom != null) _anchor = parseDay(custom.to);
                              _custom = null;
                              _period = p;
                            }),
                          ),
                          const SizedBox(height: 10),
                          PeriodNav(
                            period: _period,
                            anchor: _anchor,
                            custom: custom,
                            onStep: _step,
                            onPick: _pickRange,
                          ),
                          const SizedBox(height: 10),
                          _TrendCard(
                            store: store,
                            buckets: buckets,
                            totals: totals,
                            // A bar is the period it stands for: tapping one
                            // reads it, which is quicker than the arrows for
                            // anything more than a step away.
                            onPick: (b) => setState(() {
                              if (custom != null) {
                                _custom = b.range;
                              } else {
                                _anchor = parseDay(b.range.from);
                              }
                            }),
                          ),
                          // Both sides of the comparison, in one card and in
                          // the same shape: what changed about the money
                          // coming in matters as much as what changed about
                          // the money going out.
                          if (spendChange != null && incomeChange != null) ...[
                            const SizedBox(height: 12),
                            _ChangeCard(
                              store: store,
                              previous: _previous,
                              spend: spendChange,
                              spendBefore: before.expense,
                              income: incomeChange,
                              incomeBefore: before.income,
                              onTap: () => _step(-1),
                            ),
                          ],
                          // The same section twice, out first because that is
                          // the longer list on most months — not because it
                          // is the more important one.
                          _section(
                            range: range,
                            kind: TxKind.expense,
                            title: 'SPENT $scope',
                            empty: 'Nothing spent yet',
                          ),
                          _section(
                            range: range,
                            kind: TxKind.income,
                            title: 'EARNED $scope',
                            empty: 'Nothing earned yet',
                          ),
                          const SizedBox(height: 12),
                          _LinkCard(
                            icon: LucideIcons.receiptText,
                            title: 'View transactions',
                            subtitle: 'Everything in this $unit',
                            onTap: () => showPeriodTxns(
                              context,
                              store,
                              range: range,
                              title: custom == null
                                  ? PeriodNav.labelFor(_period, _anchor)
                                  : PeriodNav.spanLabel(custom),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every transaction in a window, or in one of its categories — the
/// destination behind the chevrons.
Future<void> showPeriodTxns(
  BuildContext context,
  PennyStore store, {
  required Range range,
  required String title,
  String? categoryId,
}) {
  final rows = [
    for (final t in within(store.txns, range))
      if (categoryId == null || t.categoryId == categoryId) t,
  ];

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SheetFrame(
      title: title,
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nothing here yet',
              textAlign: TextAlign.center,
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
          )
        else
          // Under the same day headers the ledger and the overview use: a row
          // in here has been lifted out of its day, and without one nothing
          // says when any of it happened.
          for (final (i, t) in rows.indexed) ...[
            if (i == 0 || rows[i - 1].day != t.day)
              Padding(
                padding: EdgeInsets.only(
                  left: 8,
                  bottom: 4,
                  top: i == 0 ? 4 : 14,
                ),
                child: Text(
                  dayHeader(t.day),
                  style: Theme.of(sheet).textTheme.labelSmall,
                ),
              ),
            TxnRow(
              store: store,
              txn: t,
              // The sheet closes first: editing a row from on top of a sheet
              // leaves two of them stacked and the wrong one in the way.
              onTap: () {
                Navigator.of(sheet).pop();
                showEntrySheet(context, store, existing: t);
              },
            ),
          ],
      ],
    ),
  );
}

/// In and out, one pair of bars per period, against a labelled axis.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.store,
    required this.buckets,
    required this.totals,
    required this.onPick,
  });

  final PennyStore store;
  final List<Bucket> buckets;
  final Totals totals;
  final ValueChanged<Bucket> onPick;

  /// The plot, the gap under it, and the strip the x labels sit in.
  static const _plot = 110.0;
  static const _labels = 16.0;

  @override
  Widget build(BuildContext context) {
    final peak = buckets.fold<int>(
      1,
      (m, b) => [m, b.income, b.expense].reduce((x, y) => x > y ? x : y),
    );
    final axis = niceAxisMax(peak);

    return TintCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CREDIT AND DEBIT',
            style: Theme.of(context).textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // The window's own figures, not the chart's: what the bars show is
          // the run-up, what this says is where it landed.
          //
          // Side by side at one size, because they are one question. The dot
          // is the chart's key as well — green and orange are the classic
          // confusion pair, so the words carry the meaning and the fills
          // only echo it.
          Row(
            children: [
              Expanded(
                child: _Figure(
                  colour: sproutOf(context),
                  label: 'credit',
                  amount: store.show(rupeesWhole(totals.income)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Figure(
                  colour: coinOf(context),
                  label: 'debit',
                  amount: store.show(rupeesWhole(totals.expense)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _plot + 6 + _labels,
            child: Row(
              children: [
                // The axis: nothing but its three figures, aligned with the
                // lines they belong to.
                SizedBox(
                  width: 42,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final (i, value) in [axis, axis ~/ 2, 0].indexed)
                        Positioned(
                          right: 6,
                          top: i * _plot / 2 - 7,
                          child: Text(
                            store.hideAmounts ? '' : compactRupees(value),
                            strutStyle: monoStrut(10),
                            style: mono(10, color: gridLabel(context)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Positioned(
                          top: i * _plot / 2,
                          left: 0,
                          right: 0,
                          child: Container(height: 1, color: cardEdge(context)),
                        ),
                      Row(
                        children: [
                          for (final (i, b) in buckets.indexed)
                            Expanded(
                              child: _BucketColumn(
                                bucket: b,
                                axis: axis,
                                // The last bar is the window every other
                                // figure on the page is about.
                                selected: i == buckets.length - 1,
                                hidden: store.hideAmounts,
                                labelHeight: _labels,
                                onTap: () => onPick(b),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketColumn extends StatelessWidget {
  const _BucketColumn({
    required this.bucket,
    required this.axis,
    required this.selected,
    required this.hidden,
    required this.labelHeight,
    required this.onTap,
  });

  final Bucket bucket;
  final int axis;
  final bool selected;
  final bool hidden;
  final double labelHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: hidden
          ? '${bucket.label}: hidden'
          : '${bucket.label}: credit ${rupees(bucket.income)}, '
                'debit ${rupees(bucket.expense)}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // A wash behind the read period rather than dimming the other
            // five: a chart of faded bars is a chart nobody can compare.
            color: selected ? tint(context, 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Bar(
                      fraction: bucket.income / axis,
                      colour: sproutOf(context),
                    ),
                    const SizedBox(width: 3),
                    _Bar(
                      fraction: bucket.expense / axis,
                      colour: coinOf(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: labelHeight,
                child: Text(
                  bucket.label,
                  strutStyle: monoStrut(10),
                  style: mono(10, color: gridLabel(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 9,
      child: FractionallySizedBox(
        alignment: Alignment.bottomCenter,
        // A zero bar keeps a sliver so the column still reads as present.
        heightFactor: fraction.clamp(0.012, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: colour,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      ),
    );
  }
}

/// One of the pair over the chart: the key dot, what it is, and how much.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.colour,
    required this.label,
    required this.amount,
  });

  final Color colour;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label, style: mono(11, color: scheme.secondary)),
          ],
        ),
        const SizedBox(height: 3),
        // Two figures share the width a single one used to have, so a lakh
        // shrinks to fit its half rather than pushing into the other.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount,
            maxLines: 1,
            strutStyle: monoStrut(23),
            style: mono(
              23,
              color: scheme.onSurface,
              weight: FontWeight.w800,
              spacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// The tinted square a glyph sits in — the shape the ledger's rows already
/// use, so a category reads the same on both screens.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.colour});

  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: isDark(context) ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 17, color: colour),
    );
  }
}

/// What changed since the period before — for both sides of the ledger, in
/// the same shape and the same size.
///
/// Tapping it goes to the period it is talking about, which is the question
/// the lines tend to raise.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.store,
    required this.previous,
    required this.spend,
    required this.spendBefore,
    required this.income,
    required this.incomeBefore,
    required this.onTap,
  });

  final PennyStore store;

  /// What the comparison is against, as a phrase: "last month".
  final String previous;

  /// The difference against the period before, and what that period held —
  /// the percentage cannot be recovered from the difference alone.
  final int spend;
  final int spendBefore;
  final int income;
  final int incomeBefore;
  final VoidCallback onTap;

  String get _previous => previous;

  /// "₹1,800 more than last month · up 12%". One line of maths,
  /// disproportionate insight.
  (IconData, String) _line(int change, int before) {
    // No percentage of nothing: a rise from zero is not 100%, it is a first.
    final percent = before == 0 ? null : change.abs() * 100 ~/ before;
    if (change == 0) return (LucideIcons.equal, 'Level with $_previous');
    final by = percent == null
        ? ''
        : ' · ${change > 0 ? 'up' : 'down'} $percent%';
    return (
      change > 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
      '${store.show(rupeesWhole(change.abs()))} '
          '${change > 0 ? 'more' : 'less'} than $_previous$by',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (spendIcon, spendLine) = _line(spend, spendBefore);
    final (incomeIcon, incomeLine) = _line(income, incomeBefore);

    return Semantics(
      button: true,
      label: 'Spending, $spendLine. Earning, $incomeLine. Show $_previous',
      excludeSemantics: true,
      onTap: onTap,
      child: TintCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _ChangeLine(
                    icon: spendIcon,
                    title: 'Spending',
                    line: spendLine,
                    colour: coinOf(context),
                  ),
                  const SizedBox(height: 10),
                  _ChangeLine(
                    icon: incomeIcon,
                    title: 'Earning',
                    line: incomeLine,
                    colour: sproutOf(context),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: scheme.secondary),
          ],
        ),
      ),
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({
    required this.icon,
    required this.title,
    required this.line,
    required this.colour,
  });

  final IconData icon;
  final String title;
  final String line;

  /// The side of the ledger this is about — the same two colours the chart
  /// keys. Neither direction is scolded and neither is congratulated: the
  /// glyph reports, it does not judge.
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        _IconTile(icon: icon, colour: colour),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              const SizedBox(height: 2),
              Text(line, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Categories, largest first, each with a share bar in its own colour.
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.store,
    required this.spend,
    required this.shown,
    required this.total,
    required this.pie,
    required this.onTap,
  });

  final PennyStore store;
  final Map<String, int> spend;

  /// A donut over the rows, which then drop their share bars: the ring says
  /// the same thing, and the icon tiles are its key.
  final bool pie;

  /// The rows to draw — the top few, or all of them once asked.
  final List<MapEntry<String, int>> shown;
  final int total;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TintCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          if (pie)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: SizedBox.square(
                dimension: 160,
                child: CustomPaint(
                  painter: _Donut([
                    for (final e in spend.entries)
                      (
                        e.value / (total == 0 ? 1 : total),
                        catColorAt(
                          store.categoryById(e.key)?.color ?? defaultCatColor,
                        ),
                      ),
                  ]),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          store.show(rupeesWhole(total)),
                          strutStyle: monoStrut(18),
                          style: mono(
                            18,
                            color: scheme.onSurface,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          for (final e in shown)
            Builder(
              builder: (context) {
                final c = store.categoryById(e.key);
                final name = c?.name ?? 'Uncategorised';
                final colour = catColorAt(c?.color ?? defaultCatColor);
                // The bar and the figure are one fraction, computed once: of
                // everything in this list, not of the largest row in it. The
                // bar used to scale off the peak, so the biggest category
                // filled the track while its own label said 69%.
                final permille = total == 0
                    ? 0
                    : (e.value * 1000 / total).round();
                final share = (permille / 10).round();

                return Semantics(
                  button: true,
                  label: store.hideAmounts
                      ? '$name, $share percent'
                      : '$name, ${rupees(e.value)}, $share percent',
                  excludeSemantics: true,
                  onTap: () => onTap(e.key),
                  child: InkWell(
                    onTap: () => onTap(e.key),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          _IconTile(
                            icon: iconFor(c?.icon ?? defaultIcon),
                            colour: colour,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '$share%',
                                      style: mono(11, color: scheme.secondary),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      store.show(rupees(e.value)),
                                      style: mono(
                                        13,
                                        color: scheme.onSurface,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!pie) ...[
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(pill),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          // A sliver at minimum: a row that is
                                          // in the list did happen.
                                          flex: permille.clamp(1, 1000),
                                          child: Container(
                                            height: 6,
                                            color: colour,
                                          ),
                                        ),
                                        Expanded(
                                          flex: (1000 - permille).clamp(0, 999),
                                          child: Container(
                                            height: 6,
                                            color:
                                                scheme.surfaceContainerHighest,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: scheme.secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// A ring of (fraction, colour) slices, clockwise from twelve o'clock.
class _Donut extends CustomPainter {
  _Donut(this.slices);

  final List<(double, Color)> slices;

  static const _stroke = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    // A hairline of card between slices so neighbours in similar colours
    // stay two things. None for a lone slice, or the ring would have a notch.
    final gap = slices.length > 1 ? 0.025 : 0.0;
    var start = -math.pi / 2;
    for (final (fraction, colour) in slices) {
      final sweep = fraction * 2 * math.pi;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.01),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = colour,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Donut old) => true;
}

/// A card that is one tap: a glyph, two lines, a chevron.
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: TintCard(
        onTap: onTap,
        child: Row(
          children: [
            _IconTile(icon: icon, colour: sproutOf(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: scheme.secondary),
          ],
        ),
      ),
    );
  }
}

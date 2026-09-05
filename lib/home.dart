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

  void _step(int by) => setState(
    () => _anchor = switch (_period) {
      Period.day => shiftDays(_anchor, by),
      Period.week => shiftDays(_anchor, by * 7),
      Period.month => shiftMonths(_anchor, by),
    },
  );

  /// The next period is only reachable while it is not entirely in the future.
  bool get _canGoForward =>
      rangeFor(_period, _anchor).to.compareTo(dayKey(today())) < 0;

  String get _rangeLabel {
    final r = rangeFor(_period, _anchor);
    final from = parseDay(r.from);
    return switch (_period) {
      Period.day => r.from == dayKey(today()) ? 'Today' : longDate(from),
      Period.week => '${shortDate(from)} — ${shortDate(parseDay(r.to))}',
      Period.month => '${months[from.month - 1]} ${from.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final range = rangeFor(_period, _anchor);
    final totals = totalsIn(store.txns, range);
    final rows = within(store.txns, range);

    // The recent list carries the same day headers the ledger does, built up
    // front rather than inside the children list: a day changes on a row, and
    // spotting that mid-list is what an index-fiddling loop gets wrong.
    final recent = <Widget>[];
    String? lastDay;
    for (final t in rows.take(8)) {
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
              onChanged: (p) => setState(() => _period = p),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                RoundIconButton(
                  icon: LucideIcons.chevronLeft,
                  tooltip: 'Previous ${_period.label.toLowerCase()}',
                  size: 36,
                  onPressed: () => _step(-1),
                ),
                Expanded(
                  child: Text(
                    _rangeLabel,
                    textAlign: TextAlign.center,
                    style: mono(
                      12.5,
                      color: scheme.secondary,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                Opacity(
                  // Kept in the layout rather than removed, so the label
                  // does not jump sideways at the present period.
                  opacity: _canGoForward ? 1 : 0.25,
                  child: RoundIconButton(
                    icon: LucideIcons.chevronRight,
                    tooltip: 'Next ${_period.label.toLowerCase()}',
                    size: 36,
                    onPressed: () => _canGoForward ? _step(1) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _FlowCard(totals: totals, hidden: store.hideAmounts),

            // Week and month both get the grid — a week is simply one
            // row of it. A single day would be one cell, which tells
            // you nothing the figures above have not.
            if (_period != Period.day) ...[
              const SizedBox(height: 12),
              _SpendHeatmap(
                spend: spendByDay(store.txns, range),
                hidden: store.hideAmounts,
                range: range,
              ),
            ],

            const SizedBox(height: 24),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: PennyMessage(
                  pose: Penny.rest,
                  headline: 'Nothing this ${_period.label.toLowerCase()}',
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

    return TintCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TOTAL BALANCE', style: text.labelSmall),
              const Spacer(),
              // Masking is a per-device preference, not a lock: it is for a
              // shared desk or someone reading over a shoulder, and it says so
              // by being one tap away in both directions.
              RoundIconButton(
                icon: store.hideAmounts ? LucideIcons.eyeOff : LucideIcons.eye,
                tooltip: store.hideAmounts ? 'Show amounts' : 'Hide amounts',
                size: 32,
                onPressed: () => store.setHideAmounts(!store.hideAmounts),
              ),
            ],
          ),
          Text(
            store.hideAmounts ? maskedAmount : rupees(total),
            strutStyle: monoStrut(29),
            style: mono(
              29,
              color: scheme.onSurface,
              weight: FontWeight.w800,
              spacing: -0.5,
            ),
          ),
          // What the goals have spoken for, and what is left after them. The
          // whole point of a goal is knowing the second number — money set
          // aside is still in the balance above, and without this line the
          // balance quietly overstates what there is to spend.
          if (store.totalSetAside > 0)
            Text(
              '${store.show(rupeesWhole(store.totalSetAside))} set aside · '
              '${store.show(rupeesWhole(total - store.totalSetAside))} free',
              strutStyle: monoStrut(11.5),
              style: mono(11.5, color: scheme.secondary),
            ),
          if (store.liveAccounts.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in store.liveAccounts)
                  CategoryAccent(
                    color: catColorAt(a.color),
                    child: Builder(
                      builder: (context) => TintChip(
                        icon: iconFor(a.icon),
                        label: store.hideAmounts
                            ? '${a.name}  $maskedAmount'
                            : '${a.name}  ${rupeesWhole(store.balanceOf(a.id))}',
                        semanticsLabel: store.hideAmounts
                            ? '${a.name}, hidden'
                            : '${a.name}, ${rupees(store.balanceOf(a.id))}',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
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

/// A month of days, each shaded by what was spent on it.
///
/// Wick's contribution grid, re-pointed at money. The alpha runs between the
/// unlit-cell wash and the accent at full strength, so a heavy day is solid and
/// a light one barely there.
class _SpendHeatmap extends StatelessWidget {
  const _SpendHeatmap({
    required this.spend,
    required this.range,
    required this.hidden,
  });

  final Map<String, int> spend;

  /// The days to draw. A month lays out as a calendar with leading blanks; a
  /// week is the same grid with exactly seven cells and none.
  final Range range;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final from = parseDay(range.from);

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
              Text(
                'SPEND BY DAY',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              if (peak > 0)
                // Masked rather than removed, so the row keeps its shape
                // either way. Flexible because a large peak plus the label is
                // wider than a narrow phone.
                Flexible(
                  child: Text(
                    'busiest ${hidden ? maskedAmount : rupeesWhole(peak)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: monoStrut(11),
                    style: mono(11, color: scheme.secondary),
                  ),
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
                  peak: peak,
                  hidden: hidden,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.amount,
    required this.peak,
    required this.hidden,
  });

  final int day;
  final int amount;
  final int peak;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    // An empty day is the unlit wash; the heaviest is the accent at full
    // strength; everything between scales linearly off the month's peak.
    final t = peak == 0 ? 0.0 : (amount / peak).clamp(0.0, 1.0);
    final empty = isDark(context) ? 0.16 : 0.26;
    final colour = amount == 0
        ? cellEmpty(context)
        : sproutOf(context).withValues(alpha: empty + (1 - empty) * t);

    return Semantics(
      label: amount == 0
          ? 'Day $day, nothing spent'
          : 'Day $day, ${rupees(amount)}',
      excludeSemantics: true,
      child: Tooltip(
        message: amount == 0 || hidden ? '$day' : '$day · ${rupees(amount)}',
        child: Container(
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}

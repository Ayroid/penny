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
  const HomePage({super.key, required this.store, required this.onSettings});

  final PennyStore store;
  final VoidCallback onSettings;

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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: greeting(),
              // The date, the way Wick's Today page carries it. `today()`
              // rather than `DateTime.now()` so it moves with the injected
              // clock and the goldens stay still.
              subtitle: longDate(today()),
              actions: [
                RoundIconButton(
                  icon: LucideIcons.settings,
                  tooltip: 'Settings',
                  onPressed: widget.onSettings,
                ),
                RoundIconButton(
                  icon: LucideIcons.plus,
                  tooltip: 'Add a transaction',
                  filled: true,
                  onPressed: () => showEntrySheet(context, store),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                children: [
                  _BalanceCard(store: store),

                  // Gated on what is pinned, not on whether there is history:
                  // deleting every transaction should not silently drop the
                  // shortcuts someone chose to keep.
                  if (store.shortcuts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _QuickAddStrip(store: store),
                  ],

                  // A brand-new ledger skips the period controls entirely.
                  // Three cards of zeroes and an unlit heatmap push the one
                  // thing there is to do below the fold, and the empty state
                  // is the screen most people see first.
                  if (store.txns.isEmpty) ...[
                    PennyMessage(
                      headline: 'Nothing tracked yet',
                      body:
                          'Add what you spent or earned and it will show up here.',
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

                    if (_period == Period.month) ...[
                      const SizedBox(height: 12),
                      _SpendHeatmap(
                        spend: spendByDay(store.txns, range),
                        hidden: store.hideAmounts,
                        month: parseDay(range.from),
                      ),
                    ],

                    const SizedBox(height: 24),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: PennyMessage(
                          pose: Penny.rest,
                          headline:
                              'Nothing this ${_period.label.toLowerCase()}',
                          body: 'A quiet stretch. Nothing moved in or out.',
                          actionLabel: 'Add a transaction',
                          onAction: () => showEntrySheet(context, store),
                          size: 120,
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Text('RECENT', style: text.labelSmall),
                      ),
                      for (final t in rows.take(8))
                        TxnRow(
                          store: store,
                          txn: t,
                          onTap: () =>
                              showEntrySheet(context, store, existing: t),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
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
    required this.month,
    required this.hidden,
  });

  final Map<String, int> spend;
  final DateTime month;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final peak = spend.values.fold(0, (a, b) => a > b ? a : b);

    // Monday-first columns, with the leading blanks the month starts on.
    final lead = DateTime(month.year, month.month).weekday - 1;

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
              for (var d = 1; d <= days; d++)
                _Cell(
                  day: d,
                  amount:
                      spend[dayKey(DateTime(month.year, month.month, d))] ?? 0,
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

/// One tap to enter a thing you enter often.
///
/// The point of the whole screen: a money app is abandoned over entry
/// friction, and "chai ₹20" typed once should never need typing again.
class _QuickAddStrip extends StatelessWidget {
  const _QuickAddStrip({required this.store});

  final PennyStore store;

  @override
  Widget build(BuildContext context) {
    final pinned = store.shortcuts;
    if (pinned.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Labelled, because a bare row of chips reads as a filter, and one
        // that silently spends money on a mis-tap is a bad surprise. Same
        // overline as RECENT and SPEND BY DAY.
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Text('PINNED', style: Theme.of(context).textTheme.labelSmall),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: pinned.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) =>
                _QuickAddChip(store: store, shortcut: pinned[i]),
          ),
        ),
      ],
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  const _QuickAddChip({required this.store, required this.shortcut});

  final PennyStore store;
  final Shortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = store.categoryById(shortcut.categoryId);
    final colour = catColorAt(category?.color ?? defaultCatColor);
    final label = shortcut.note.isNotEmpty
        ? shortcut.note
        : category?.name ?? 'Pinned';
    final amount = shortcut.kind == TxKind.income
        ? rupeesWhole(shortcut.amountMinor, signed: true)
        : rupeesWhole(shortcut.amountMinor);

    return Semantics(
      button: true,
      label: 'Add $label, $amount',
      hint: 'Long press to unpin',
      excludeSemantics: true,
      child: Material(
        color: colour.withValues(alpha: isDark(context) ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(pill),
        child: InkWell(
          onTap: _add,
          onLongPress: _unpin,
          borderRadius: BorderRadius.circular(pill),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconFor(category?.icon ?? defaultIcon),
                  size: 15,
                  color: colour,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  amount,
                  style: mono(
                    12,
                    color: scheme.secondary,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _add() {
    // No confirmation and no toast: the row appears at the top of RECENT on
    // the same screen, which is the feedback. Correcting a mis-tap means
    // opening that row and deleting it.
    store.addTxn(shortcut.toTxn());
  }

  void _unpin() => store.removeShortcut(shortcut);
}

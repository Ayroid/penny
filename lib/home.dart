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
              subtitle: 'Your money, on your phone',
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

                  if (store.txns.isNotEmpty) ...[
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

                    _FlowCard(totals: totals),

                    if (_period == Period.month) ...[
                      const SizedBox(height: 12),
                      _SpendHeatmap(
                        spend: spendByDay(store.txns, range),
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
          Text('TOTAL BALANCE', style: text.labelSmall),
          const SizedBox(height: 2),
          Text(
            rupees(total),
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
                        label:
                            '${a.name}  ${rupeesWhole(store.balanceOf(a.id))}',
                        semanticsLabel:
                            '${a.name}, ${rupees(store.balanceOf(a.id))}',
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

/// In, out, and the difference.
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.totals});

  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final peak = [
      totals.income,
      totals.expense,
      1,
    ].reduce((a, b) => a > b ? a : b);

    Widget bar(String label, int value, Color colour) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: text.labelSmall),
              const Spacer(),
              // The amount sits beside the bar, never on it — see the note
              // on `coin` in theme.dart.
              Text(
                rupees(value),
                style: mono(
                  13.5,
                  color: scheme.onSurface,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(pill),
            child: Row(
              children: [
                Expanded(
                  flex: (value / peak * 1000).round().clamp(1, 1000),
                  child: Container(height: 8, color: colour),
                ),
                Expanded(
                  flex: (1000 - value / peak * 1000).round().clamp(0, 999),
                  child: Container(
                    height: 8,
                    color: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return TintCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar('IN', totals.income, sproutOf(context)),
          bar('OUT', totals.expense, coinOf(context)),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text('NET', style: text.labelSmall),
                const Spacer(),
                Text(
                  rupees(totals.net, signed: true),
                  // Not red when negative. A month that ended down is ordinary,
                  // not a failure — the design system is explicit about this.
                  style: mono(
                    15,
                    color: scheme.onSurface,
                    weight: FontWeight.w800,
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

/// A month of days, each shaded by what was spent on it.
///
/// Wick's contribution grid, re-pointed at money. The alpha runs between the
/// unlit-cell wash and the accent at full strength, so a heavy day is solid and
/// a light one barely there.
class _SpendHeatmap extends StatelessWidget {
  const _SpendHeatmap({required this.spend, required this.month});

  final Map<String, int> spend;
  final DateTime month;

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
                Text(
                  'busiest ${rupeesWhole(peak)}',
                  style: mono(11, color: scheme.secondary),
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
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.amount, required this.peak});

  final int day;
  final int amount;
  final int peak;

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
        message: amount == 0 ? '$day' : '$day · ${rupees(amount)}',
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
    final suggestions = quickAdds(store.txns);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Labelled, because a bare row of chips reads as a filter, and one
        // that silently spends money on a mis-tap is a bad surprise. Same
        // overline as RECENT and SPEND BY DAY.
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Text(
            'TAP TO ADD AGAIN',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) =>
                _QuickAddChip(store: store, suggestion: suggestions[i]),
          ),
        ),
      ],
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  const _QuickAddChip({required this.store, required this.suggestion});

  final PennyStore store;
  final QuickAdd suggestion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = store.categoryById(suggestion.categoryId);
    final colour = catColorAt(category?.color ?? defaultCatColor);
    final label = suggestion.note.isNotEmpty
        ? suggestion.note
        : category?.name ?? 'Again';
    final amount = suggestion.kind == TxKind.income
        ? rupeesWhole(suggestion.amountMinor, signed: true)
        : rupeesWhole(suggestion.amountMinor);

    return Semantics(
      button: true,
      label: 'Add $label, $amount',
      excludeSemantics: true,
      child: Material(
        color: colour.withValues(alpha: isDark(context) ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(pill),
        child: InkWell(
          onTap: () => _add(context),
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

  void _add(BuildContext context) {
    final txn = txnFrom(suggestion);
    store.addTxn(txn);

    // Added on one tap, so it has to be undoable on one more. Without this the
    // shortcut is a trap: a mis-tap costs a trip through the ledger to find
    // and delete the row.
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added ${rupees(txn.amountMinor)}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => store.removeTxn(txn),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'analytics.dart';
import 'icons.dart';
import 'money.dart';
import 'penny.dart';
import 'page_bar.dart';
import 'store.dart';
import 'theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final text = Theme.of(context).textTheme;
    final anchor = today();
    final buckets = series(
      store.txns,
      _period,
      anchor,
      _period == Period.day ? 14 : 6,
    );
    final range = rangeFor(_period, anchor);
    final spend = byCategory(store.txns, range, TxKind.expense);
    final change = changeVsPrevious(
      store.txns,
      _period,
      anchor,
      kind: TxKind.expense,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Insights',
              subtitle: 'Where it goes',
              onBack: () => Navigator.of(context).maybePop(),
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
                  : ListView(
                      // No tab pill under a pushed page to clear.
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      children: [
                        Segmented<Period>(
                          options: {for (final p in Period.values) p: p.label},
                          value: _period,
                          onChanged: (p) => setState(() => _period = p),
                        ),
                        const SizedBox(height: 12),
                        _TrendCard(store: store, buckets: buckets),
                        if (change != null) ...[
                          const SizedBox(height: 12),
                          _ChangeCard(
                            store: store,
                            change: change,
                            period: _period,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 6),
                          child: Text(
                            'SPENT THIS ${_period.label.toUpperCase()}',
                            style: text.labelSmall,
                          ),
                        ),
                        if (spend.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Nothing spent yet',
                                style: text.bodySmall,
                              ),
                            ),
                          )
                        else
                          _Breakdown(store: store, spend: spend),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// In and out, one pair of bars per period.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.store, required this.buckets});

  final PennyStore store;
  final List<Bucket> buckets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = buckets.fold<int>(
      1,
      (m, b) => [m, b.income, b.expense].reduce((x, y) => x > y ? x : y),
    );

    return TintCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CREDIT AND DEBIT',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              // A key, because green and orange are the classic confusion
              // pair — the words carry the meaning, the fills only echo it.
              _Key(colour: sproutOf(context), label: 'credit'),
              const SizedBox(width: 10),
              _Key(colour: coinOf(context), label: 'debit'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Semantics(
                      label: store.hideAmounts
                          ? '${b.label}: hidden'
                          : '${b.label}: credit ${rupees(b.income)}, '
                                'debit ${rupees(b.expense)}',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Bar(
                                  fraction: b.income / peak,
                                  colour: sproutOf(context),
                                ),
                                const SizedBox(width: 3),
                                _Bar(
                                  fraction: b.expense / peak,
                                  colour: coinOf(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            b.label,
                            style: mono(10, color: gridLabel(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Biggest bar ${store.show(rupeesWhole(peak))}',
            style: mono(11, color: scheme.secondary),
          ),
        ],
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

class _Key extends StatelessWidget {
  const _Key({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: mono(11, color: Theme.of(context).colorScheme.secondary),
        ),
      ],
    );
  }
}

/// "₹1,800 more than last month." One line of maths, disproportionate insight.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.store,
    required this.change,
    required this.period,
  });

  final PennyStore store;
  final int change;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previous = switch (period) {
      Period.day => 'yesterday',
      Period.week => 'last week',
      Period.month => 'last month',
    };

    final (icon, phrase) = change == 0
        ? (LucideIcons.equal, 'Spending is level with $previous')
        : change > 0
        ? (
            LucideIcons.trendingUp,
            '${store.show(rupeesWhole(change))} more than $previous',
          )
        : (
            LucideIcons.trendingDown,
            '${store.show(rupeesWhole(-change))} less than $previous',
          );

    return TintCard(
      child: Row(
        children: [
          // Neither direction is scolded and neither is congratulated: the
          // glyph reports, it does not judge.
          Icon(icon, size: 18, color: scheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(phrase, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Categories, largest first, each with a share bar in its own colour.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.store, required this.spend});

  final PennyStore store;
  final Map<String, int> spend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = spend.values.fold(0, (a, b) => a + b);
    final peak = spend.values.first;

    return TintCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        children: [
          for (final e in spend.entries)
            Builder(
              builder: (context) {
                final c = store.categoryById(e.key);
                final colour = catColorAt(c?.color ?? defaultCatColor);
                final share = total == 0 ? 0 : (e.value * 100 / total).round();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    label: store.hideAmounts
                        ? '${c?.name ?? 'Uncategorised'}, $share percent'
                        : '${c?.name ?? 'Uncategorised'}, ${rupees(e.value)}, '
                              '$share percent',
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              iconFor(c?.icon ?? defaultIcon),
                              size: 15,
                              color: colour,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c?.name ?? 'Uncategorised',
                                style: Theme.of(context).textTheme.titleMedium,
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
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(pill),
                          child: Row(
                            children: [
                              Expanded(
                                flex: (e.value / peak * 1000).round().clamp(
                                  1,
                                  1000,
                                ),
                                child: Container(height: 6, color: colour),
                              ),
                              Expanded(
                                flex: (1000 - e.value / peak * 1000)
                                    .round()
                                    .clamp(0, 999),
                                child: Container(
                                  height: 6,
                                  color: scheme.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

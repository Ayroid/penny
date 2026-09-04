import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'entry_sheet.dart';
import 'money.dart';
import 'penny.dart';
import 'page_bar.dart';
import 'store.dart';
import 'theme.dart';
import 'txn_row.dart';

/// Every transaction, newest first, grouped by day.
///
/// The mental model people already have for this screen is a bank statement,
/// so it behaves like one: a running balance on every row and a net for each
/// day.
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.store});

  final PennyStore store;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  final _search = TextEditingController();
  TxKind? _kind;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// What one row does to the total across all accounts. A transfer nets to
  /// zero — it moves money without changing how much there is.
  int _effect(Txn t) => switch (t.kind) {
        TxKind.income => t.amountMinor,
        TxKind.expense => -t.amountMinor,
        TxKind.transfer => 0,
      };

  bool _matches(Txn t) {
    if (_kind != null && t.kind != _kind) return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final category = widget.store.categoryById(t.categoryId)?.name ?? '';
    final account = widget.store.accountById(t.accountId)?.name ?? '';
    return t.note.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        account.toLowerCase().contains(q) ||
        rupees(t.amountMinor).contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final text = Theme.of(context).textTheme;
    final all = store.txns;

    // The running balance is the total after each row, so it has to be
    // accumulated from the oldest end even though the list reads newest first.
    final balances = <String, int>{};
    var running = store.totalBalance;
    for (final t in all) {
      balances[t.id] = running;
      running -= _effect(t);
    }

    final rows = [for (final t in all) if (_matches(t)) t];

    // Flatten into day headers followed by their rows, so one ListView can
    // build the whole thing lazily.
    final items = <({String? header, int net, Txn? txn})>[];
    String? lastDay;
    for (final t in rows) {
      if (t.day != lastDay) {
        lastDay = t.day;
        final net = rows
            .where((x) => x.day == t.day)
            .fold(0, (sum, x) => sum + _effect(x));
        items.add((header: t.day, net: net, txn: null));
      }
      items.add((header: null, net: 0, txn: t));
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Ledger',
              subtitle: rows.length == all.length
                  ? '${all.length} ${all.length == 1 ? 'entry' : 'entries'}'
                  : '${rows.length} of ${all.length}',
              actions: [
                RoundIconButton(
                  icon: LucideIcons.plus,
                  tooltip: 'Add a transaction',
                  filled: true,
                  onPressed: () => showEntrySheet(context, store),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search notes, categories, amounts',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              tooltip: 'Clear search',
                              onPressed: () =>
                                  setState(() => _search.clear()),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Three, not four. The design system is explicit that more
                  // than three options is a list rather than a segmented
                  // control, and transfers are rare enough to live under All.
                  Segmented<TxKind?>(
                    options: const {
                      null: 'All',
                      TxKind.expense: 'Out',
                      TxKind.income: 'In',
                    },
                    value: _kind,
                    onChanged: (k) => setState(() => _kind = k),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? PennyMessage(
                      pose: all.isEmpty ? Penny.standing : Penny.thinking,
                      headline:
                          all.isEmpty ? 'Nothing tracked yet' : 'No matches',
                      body: all.isEmpty
                          ? 'Every transaction you add lands here.'
                          : 'Nothing in the ledger fits that.',
                      actionLabel: all.isEmpty ? 'Add a transaction' : null,
                      onAction: all.isEmpty
                          ? () => showEntrySheet(context, store)
                          : null,
                      size: 120,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        if (item.txn == null) {
                          return Padding(
                            padding: EdgeInsets.only(
                                left: 8, right: 8, top: i == 0 ? 4 : 18, bottom: 4),
                            child: Row(
                              children: [
                                Text(_dayHeader(item.header!),
                                    style: text.labelSmall),
                                const Spacer(),
                                Text(rupeesWhole(item.net, signed: true),
                                    style: mono(11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        weight: FontWeight.w700)),
                              ],
                            ),
                          );
                        }
                        return TxnRow(
                          store: store,
                          txn: item.txn!,
                          showBalance: balances[item.txn!.id],
                          onTap: () => showEntrySheet(context, store,
                              existing: item.txn),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _dayHeader(String key) {
    final d = parseDay(key);
    final t = today();
    if (d == t) return 'TODAY';
    if (d == shiftDays(t, -1)) return 'YESTERDAY';
    return longDate(d).toUpperCase();
  }
}

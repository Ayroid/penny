import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'money.dart';
import 'page_bar.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';

/// One transaction, as it appears in every list in the app.
///
/// Shared rather than written twice: the overview's recent rows and the full
/// ledger are the same row, and two that drift apart is how a sign ends up
/// wrong in one place only.
class TxnRow extends StatelessWidget {
  const TxnRow({
    super.key,
    required this.store,
    required this.txn,
    this.onTap,
    this.showBalance,
  });

  final PennyStore store;
  final Txn txn;
  final VoidCallback? onTap;

  /// Running balance after this row, for the ledger. Absent on the overview.
  final int? showBalance;

  /// Hold a row to enter it again, dated today.
  ///
  /// Built into the row rather than passed in, because it should be the same
  /// gesture in the ledger, on the overview and in the sheet Insights opens —
  /// three call sites is three chances to leave one of them out.
  ///
  /// A hold is easy to do by accident on a list that scrolls, so it opens a
  /// sheet and asks rather than writing a row behind the thumb. The sheet
  /// carries what it is about to copy — the same three strings the row itself
  /// is drawn from, so the two cannot describe it differently.
  ///
  /// The copy carries neither [Txn.ruleId] nor [Txn.goalId]: it was not
  /// materialised from a rule, and it is not money a goal counted.
  void _copy(
    BuildContext context,
    String title,
    String subtitle,
    String amount,
  ) => _duplicate(context, title: title, subtitle: subtitle, amount: amount);

  Future<void> _duplicate(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String amount,
  }) async {
    // A goal's own rows are the exception, and there is nothing to confirm:
    // copying one would move money into the goals account without the goal
    // knowing, past the two ceilings `putAside` applies — the hand-made
    // transfer the pickers stopped offering. The goals page is where money is
    // put aside.
    if (txn.goalId != null) {
      showUndoBar(context, 'Put this aside from the goal instead');
      return;
    }

    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SheetFrame(
        title: 'Copy to today',
        pinned: FilledButton(
          onPressed: () => Navigator.pop(sheet, true),
          child: const Text('Copy'),
        ),
        children: [
          Text(
            amount,
            strutStyle: monoStrut(24),
            style: mono(
              24,
              color: Theme.of(sheet).colorScheme.onSurface,
              weight: FontWeight.w800,
              spacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [title, if (subtitle.isNotEmpty) subtitle].join(' · '),
            style: Theme.of(sheet).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Text(
            'Enters this again, dated today. The row it came from is left '
            'alone.',
            style: Theme.of(sheet).textTheme.bodySmall,
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    final copy = Txn(
      kind: txn.kind,
      amountMinor: txn.amountMinor,
      day: dayKey(today()),
      categoryId: txn.categoryId,
      accountId: txn.accountId,
      toAccountId: txn.toAccountId,
      note: txn.note,
    );
    store.addTxn(copy);
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      showUndoBar(
        context,
        'Copied to today',
        onUndo: () => store.removeTxn(copy),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hideAmount = store.hideAmounts;
    final category = store.categoryById(txn.categoryId);
    final account = store.accountById(txn.accountId);

    final isTransfer = txn.kind == TxKind.transfer;
    final isAdjust =
        txn.kind == TxKind.adjustUp || txn.kind == TxKind.adjustDown;
    final colour = isTransfer || isAdjust
        ? scheme.secondary
        : catColorAt(category?.color ?? defaultCatColor);

    // The title is what the money was for; the line under it is where it came
    // from, plus the person's own note if there is one.
    final title = isTransfer
        ? '${account?.name ?? '—'} → ${store.accountById(txn.toAccountId ?? '')?.name ?? '—'}'
        : isAdjust
        ? 'Realigned'
        : category?.name ?? 'Uncategorised';
    final subtitle = [
      if (!isTransfer) account?.name ?? '',
      if (txn.note.isNotEmpty) txn.note,
    ].where((s) => s.isNotEmpty).join(' · ');

    // Signed by kind, never by a negative amount in storage. A transfer takes
    // no sign at all — nothing was earned or spent.
    final amount = hideAmount
        ? maskedAmount
        : switch (txn.kind) {
            TxKind.income ||
            TxKind.adjustUp => rupees(txn.amountMinor, signed: true),
            TxKind.expense ||
            TxKind.adjustDown => '-${rupees(txn.amountMinor)}',
            TxKind.transfer => rupees(txn.amountMinor),
          };

    return Semantics(
      button: onTap != null,
      label: '$title, $amount${subtitle.isEmpty ? '' : ', $subtitle'}',
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: () => _copy(context, title, subtitle, amount),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _copy(context, title, subtitle, amount),
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colour.withValues(
                    alpha: isDark(context) ? 0.15 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isTransfer || isAdjust
                      ? iconFor('arrow-left-right')
                      : iconFor(category?.icon ?? defaultIcon),
                  size: 18,
                  color: colour,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Capped rather than flexed: a `Flexible` here splits the free
              // space with the title's `Expanded` and leaves a gap at the
              // right on every ordinary row. Figures wider than the cap —
              // a crore, which used to overflow the row outright — scale
              // down into it instead.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        amount,
                        strutStyle: monoStrut(13.5),
                        style: mono(
                          13.5,
                          // Income is the brand's own green because it is the thing
                          // the app is for. Spending is the plain foreground, not
                          // red: an ordinary expense is not a failure.
                          color:
                              txn.kind == TxKind.income ||
                                  txn.kind == TxKind.adjustUp
                              ? sproutOf(context)
                              : scheme.onSurface,
                          weight: FontWeight.w700,
                        ),
                      ),
                      if (showBalance != null)
                        Text(
                          hideAmount ? maskedAmount : rupeesWhole(showBalance!),
                          style: mono(11, color: scheme.secondary),
                        ),
                    ],
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

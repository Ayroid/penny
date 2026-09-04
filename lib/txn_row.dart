import 'package:flutter/material.dart';

import 'icons.dart';
import 'money.dart';
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
    this.hideAmount = false,
  });

  final PennyStore store;
  final Txn txn;
  final VoidCallback? onTap;

  /// Running balance after this row, for the ledger. Absent on the overview.
  final int? showBalance;

  /// Mask the figures. Set on the overview, which is the screen glanced at in
  /// public; the ledger is somewhere you go on purpose.
  final bool hideAmount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final category = store.categoryById(txn.categoryId);
    final account = store.accountById(txn.accountId);

    final isTransfer = txn.kind == TxKind.transfer;
    final colour = isTransfer
        ? scheme.secondary
        : catColorAt(category?.color ?? defaultCatColor);

    // The title is what the money was for; the line under it is where it came
    // from, plus the person's own note if there is one.
    final title = isTransfer
        ? '${account?.name ?? '—'} → ${store.accountById(txn.toAccountId ?? '')?.name ?? '—'}'
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
            TxKind.income => rupees(txn.amountMinor, signed: true),
            TxKind.expense => '-${rupees(txn.amountMinor)}',
            TxKind.transfer => rupees(txn.amountMinor),
          };

    return Semantics(
      button: onTap != null,
      label: '$title, $amount${subtitle.isEmpty ? '' : ', $subtitle'}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
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
                  isTransfer
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
              Column(
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
                      color: txn.kind == TxKind.income
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
            ],
          ),
        ),
      ),
    );
  }
}

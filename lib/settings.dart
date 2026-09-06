import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'icons.dart';
import 'money.dart';
import 'recurring.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';

void openSettings(BuildContext context, PennyStore store) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => SettingsScreen(store: store)));

/// Everything that is not a transaction.
///
/// Accounts, categories and rules live here as sheets rather than as their own
/// screens: each is a short list with a small editor, and three more top-level
/// files would be ceremony for what is one settings page.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final PennyStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => _Body(store: store),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.store});

  final PennyStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Text(label.toUpperCase(), style: text.labelSmall),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        section('Appearance'),
        SoftCard(
          child: Segmented<ThemeMode>(
            options: const {
              ThemeMode.light: 'Light',
              ThemeMode.dark: 'Dark',
              ThemeMode.system: 'System',
            },
            value: store.themeMode,
            onChanged: store.setThemeMode,
          ),
        ),
        section('Money'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Counts only. The balance belongs on the overview, where it is
              // the headline figure — repeating it under a settings row makes
              // it look like a setting, and puts the number people most want
              // private on the screen they hand someone else the phone on.
              _Row(
                icon: LucideIcons.wallet,
                label: 'Accounts',
                subtitle: plural(store.liveAccounts.length, 'account'),
                onTap: () => _showAccounts(context, store),
              ),
              _Row(
                icon: LucideIcons.tag,
                label: 'Categories',
                subtitle: plural(
                  store.categories.where((c) => !c.archived).length,
                  'category',
                  'categories',
                ),
                onTap: () => _showCategories(context, store),
              ),
              _Row(
                icon: LucideIcons.repeat,
                label: 'Recurring',
                subtitle: store.rules.isEmpty
                    ? 'Rent, salary, subscriptions'
                    : plural(store.rules.length, 'rule'),
                onTap: () => _showRules(context, store),
              ),
              _Row(
                icon: LucideIcons.bookmark,
                label: 'Quick entries',
                subtitle: store.shortcuts.isEmpty
                    ? 'Hold the add button to use them'
                    : plural(store.shortcuts.length, 'entry', 'entries'),
                onTap: () => _showQuickEntries(context, store),
                last: true,
              ),
            ],
          ),
        ),
        section('Data'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _Row(
                icon: LucideIcons.upload,
                label: 'Export a backup',
                subtitle: 'A JSON file you keep',
                onTap: () => _export(context, store),
              ),
              _Row(
                icon: LucideIcons.download,
                label: 'Import a backup',
                subtitle: 'Replaces everything here',
                onTap: () => _import(context, store),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Penny keeps everything on this phone.\nNo account, no sync, no analytics.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 19, color: scheme.secondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 17, color: scheme.outline),
              ],
            ),
          ),
        ),
        if (!last) Divider(height: 1, indent: 50, color: scheme.outline),
      ],
    );
  }
}

// ── Backup ──────────────────────────────────────────────────────────────────

Future<void> _export(BuildContext context, PennyStore store) async {
  final dir = await Directory.systemTemp.createTemp('penny');
  final file = File('${dir.path}/penny-${dayKey(today())}.json');
  await file.writeAsString(store.exportJson());
  if (!context.mounted) return;
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: 'Penny backup'),
  );
}

Future<void> _import(BuildContext context, PennyStore store) async {
  final picked = await FilePicker.pickFile(
    dialogTitle: 'Choose a Penny backup',
  );
  if (picked == null || !context.mounted) return;

  // utf8.decode, not fromCharCodes: a backup routinely contains a rupee sign
  // and whatever script the notes were typed in, and byte-per-character would
  // turn every one of those into mojibake.
  final raw = utf8.decode(await picked.readAsBytes());
  if (!context.mounted) return;

  // Confirmed before anything is touched: an import replaces the whole ledger,
  // and a mis-tap here costs everything.
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Replace everything?'),
      content: Text(
        'This will replace all ${store.txns.length} transactions, accounts and categories with what is in that file.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Replace',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  // A successful restore announces itself — the ledger behind this screen is
  // suddenly someone else's. A failure has to be told, though: silently doing
  // nothing after "Replace everything?" reads as success, and the person walks
  // away believing a backup was restored when it was not.
  if (store.importJson(raw)) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('That file could not be read'),
      content: const Text(
        'Nothing was changed. Check it is a Penny backup — the JSON file the '
        'export produces.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ── Accounts ────────────────────────────────────────────────────────────────

Future<void> _showAccounts(BuildContext context, PennyStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListSheet(
        title: 'Accounts',
        onAdd: () => _editAccount(context, store, null),
        children: [
          for (final a in store.accounts)
            EditableRow(
              icon: iconFor(a.icon),
              colour: catColorAt(a.color),
              label: a.name,
              trailing: rupees(store.balanceOf(a.id)),
              archived: a.archived,
              // Which are on the overview, without opening each one.
              pinned: store.pinnedAccounts.contains(a),
              onTap: () => _editAccount(context, store, a),
            ),
        ],
      ),
    ),
  );
}

Future<void> _editAccount(
  BuildContext context,
  PennyStore store,
  Account? existing,
) {
  final name = TextEditingController(text: existing?.name ?? '');
  var opening = existing?.openingBalanceMinor ?? 0;
  var colour = existing?.color ?? defaultCatColor;
  var icon = existing?.icon ?? 'wallet';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => EditSheet(
        title: existing == null ? 'New account' : 'Edit account',
        nameController: name,
        nameHint: 'Cash, Bank, Card…',
        colour: colour,
        icon: icon,
        onColour: (c) => setSheet(() => colour = c),
        onIcon: (i) => setSheet(() => icon = i),
        extra: [
          Text(
            'OPENING BALANCE',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          AmountField(
            value: opening,
            onChanged: (v) => setSheet(() => opening = v),
          ),
        ],
        // Pin and archive are the two things that can happen to an account
        // that is not editing it, so they share the row under Save. Pinning
        // is capped: the card holds four tiles, and the button says so when
        // it is full rather than failing quietly on the tap.
        footer: existing == null
            ? null
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: store.canPin(existing)
                          ? () {
                              store.setAccountPinned(
                                existing,
                                !existing.pinned,
                              );
                              Navigator.pop(context);
                            }
                          : null,
                      icon: Icon(
                        existing.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                        size: 18,
                      ),
                      label: Text(
                        existing.pinned
                            ? 'Unpin'
                            : store.canPin(existing)
                            ? 'Pin to home'
                            : '${PennyStore.maxPinned} pinned already',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        store.setAccountArchived(existing, !existing.archived);
                        Navigator.pop(context);
                      },
                      child: Text(existing.archived ? 'Bring back' : 'Archive'),
                    ),
                  ),
                ],
              ),
        onSave: name.text.trim().isEmpty
            ? null
            : () {
                if (existing == null) {
                  store.addAccount(
                    Account(
                      name: name.text.trim(),
                      icon: icon,
                      color: colour,
                      openingBalanceMinor: opening,
                    ),
                  );
                } else {
                  existing
                    ..name = name.text.trim()
                    ..icon = icon
                    ..color = colour
                    ..openingBalanceMinor = opening;
                  store.touch();
                }
                Navigator.pop(context);
              },
      ),
    ),
  );
}

// ── Categories ──────────────────────────────────────────────────────────────

Future<void> _showCategories(BuildContext context, PennyStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListSheet(
        title: 'Categories',
        onAdd: () => _editCategory(context, store, null),
        children: [
          for (final kind in [TxKind.expense, TxKind.income]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text(
                kind == TxKind.expense ? 'SPENDING' : 'INCOME',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            for (final c in store.categories.where((c) => c.kind == kind))
              EditableRow(
                icon: iconFor(c.icon),
                colour: catColorAt(c.color),
                label: c.name,
                archived: c.archived,
                onTap: () => _editCategory(context, store, c),
              ),
          ],
        ],
      ),
    ),
  );
}

Future<void> _editCategory(
  BuildContext context,
  PennyStore store,
  Category? existing,
) {
  final name = TextEditingController(text: existing?.name ?? '');
  var colour = existing?.color ?? defaultCatColor;
  var icon = existing?.icon ?? defaultIcon;
  var kind = existing?.kind ?? TxKind.expense;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => EditSheet(
        title: existing == null ? 'New category' : 'Edit category',
        nameController: name,
        nameHint: 'Groceries, Rent, Salary…',
        colour: colour,
        icon: icon,
        onColour: (c) => setSheet(() => colour = c),
        onIcon: (i) => setSheet(() => icon = i),
        extra: [
          if (existing == null)
            Segmented<TxKind>(
              options: const {
                TxKind.expense: 'Spending',
                TxKind.income: 'Income',
              },
              value: kind,
              onChanged: (k) => setSheet(() => kind = k),
            ),
        ],
        footer: existing == null
            ? null
            : TextButton(
                onPressed: () {
                  store.setCategoryArchived(existing, !existing.archived);
                  Navigator.pop(context);
                },
                child: Text(existing.archived ? 'Bring back' : 'Archive'),
              ),
        onSave: name.text.trim().isEmpty
            ? null
            : () {
                if (existing == null) {
                  store.addCategory(
                    Category(
                      name: name.text.trim(),
                      kind: kind,
                      icon: icon,
                      color: colour,
                    ),
                  );
                } else {
                  existing
                    ..name = name.text.trim()
                    ..icon = icon
                    ..color = colour;
                  store.touch();
                }
                Navigator.pop(context);
              },
      ),
    ),
  );
}

// ── Recurring rules ─────────────────────────────────────────────────────────

Future<void> _showRules(BuildContext context, PennyStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListSheet(
        title: 'Recurring',
        onAdd: () => _editRule(context, store),
        empty: store.rules.isEmpty
            ? 'Rent, salary and subscriptions add themselves when they come due.'
            : null,
        children: [
          for (final r in store.rules)
            EditableRow(
              icon: iconFor(store.categoryById(r.categoryId)?.icon ?? 'repeat'),
              colour: catColorAt(
                store.categoryById(r.categoryId)?.color ?? defaultCatColor,
              ),
              label: r.note.isEmpty
                  ? store.categoryById(r.categoryId)?.name ?? 'Rule'
                  : r.note,
              trailing: '${rupeesWhole(r.amountMinor)} · ${r.freq.name}',
              archived: !r.active,
              onTap: () => _editRule(context, store, r),
            ),
        ],
      ),
    ),
  );
}

/// Stopping a rule removes it. The rows it has already produced are ordinary
/// transactions and stay where they are — a rule is a template, not a claim on
/// its own history.
Future<void> _confirmRemoveRule(
  BuildContext context,
  PennyStore store,
  Rule rule,
) async {
  final go = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Stop this rule?'),
      content: const Text(
        'Transactions it has already added stay in the ledger. Only future ones stop.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Stop',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (go == true) store.removeRule(rule);
}

// ── Quick entries ───────────────────────────────────────────────────────────

/// The entries a hold on the add button floats out.
///
/// A quick entry is a [Rule] with the repeating taken out — same six fields,
/// no frequency, no start day, and it never fires on its own. Kept a separate
/// list rather than a rule that repeats never: half the fields on the row
/// would be dead, and a Recurring list that mixes "this happens to me" with
/// "I might tap this" tells you neither.
Future<void> _showQuickEntries(BuildContext context, PennyStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListSheet(
        title: 'Quick entries',
        onAdd: () => _editQuickEntry(context, store),
        empty: store.shortcuts.isEmpty
            ? 'Chai, the bus fare, the usual round — saved once, then a hold on the add button away.'
            : null,
        children: [
          for (final e in store.shortcuts)
            EditableRow(
              icon: iconFor(
                store.categoryById(e.categoryId)?.icon ?? defaultIcon,
              ),
              colour: catColorAt(
                store.categoryById(e.categoryId)?.color ?? defaultCatColor,
              ),
              label: e.note.isEmpty
                  ? store.categoryById(e.categoryId)?.name ?? 'Quick entry'
                  : e.note,
              trailing: rupeesWhole(e.amountMinor),
              onTap: () => _editQuickEntry(context, store, e),
            ),
        ],
      ),
    ),
  );
}

/// Add a quick entry, or edit [existing].
///
/// The rule editor without the schedule. Deleting one is not confirmed the way
/// stopping a rule is: nothing it has already added goes anywhere, and it is
/// one tap to save the same thing again.
Future<void> _editQuickEntry(
  BuildContext context,
  PennyStore store, [
  Shortcut? existing,
]) {
  final note = TextEditingController(text: existing?.note ?? '');
  var amount = existing?.amountMinor ?? 0;
  var kind = existing?.kind ?? TxKind.expense;
  var categoryId =
      existing?.categoryId ?? store.categoriesOf(TxKind.expense).first.id;
  var accountId = existing?.accountId ?? store.pickableAccounts().first.id;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final categories = store.categoriesOf(kind);
        return SheetFrame(
          title: existing == null ? 'New quick entry' : 'Edit quick entry',
          children: [
            Segmented<TxKind>(
              options: const {
                TxKind.expense: 'Spending',
                TxKind.income: 'Income',
              },
              value: kind,
              onChanged: (k) => setSheet(() {
                kind = k;
                categoryId = store.categoriesOf(k).first.id;
              }),
            ),
            const SizedBox(height: 14),
            AmountField(
              value: amount,
              positiveOnly: true,
              onChanged: (v) => setSheet(() => amount = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              decoration: const InputDecoration(hintText: 'Chai, Bus fare…'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  PickChip(
                    label: c.name,
                    icon: iconFor(c.icon),
                    colour: catColorAt(c.color),
                    selected: c.id == categoryId,
                    onTap: () => setSheet(() => categoryId = c.id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in store.pickableAccounts(accountId))
                  PickChip(
                    label: a.name,
                    icon: iconFor(a.icon),
                    colour: catColorAt(a.color),
                    selected: a.id == accountId,
                    onTap: () => setSheet(() => accountId = a.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: amount <= 0
                  ? null
                  : () {
                      if (existing == null) {
                        store.addShortcut(
                          Shortcut(
                            kind: kind,
                            amountMinor: amount,
                            categoryId: categoryId,
                            accountId: accountId,
                            note: note.text.trim(),
                          ),
                        );
                      } else {
                        existing
                          ..kind = kind
                          ..amountMinor = amount
                          ..categoryId = categoryId
                          ..accountId = accountId
                          ..note = note.text.trim();
                        store.touch();
                      }
                      Navigator.pop(context);
                    },
              child: Text(existing == null ? 'Add entry' : 'Save'),
            ),
            if (existing != null)
              TextButton(
                onPressed: () {
                  store.removeShortcut(existing);
                  Navigator.pop(context);
                },
                child: const Text('Remove'),
              ),
          ],
        );
      },
    ),
  );
}

/// Add a rule, or edit [existing].
///
/// One sheet for both, as the entry sheet is for transactions. Editing changes
/// what the rule produces *next*: rows it has already added are ordinary
/// transactions and are left alone, which is why changing rent no longer means
/// stopping one rule and inventing another.
Future<void> _editRule(
  BuildContext context,
  PennyStore store, [
  Rule? existing,
]) {
  // The list sheet underneath, which outlives this one — a dialog opened from
  // the editor's own context after popping it has no navigator to open in.
  final host = context;
  final note = TextEditingController(text: existing?.note ?? '');
  var amount = existing?.amountMinor ?? 0;
  var kind = existing?.kind ?? TxKind.expense;
  var freq = existing?.freq ?? Freq.monthly;
  var categoryId =
      existing?.categoryId ?? store.categoriesOf(TxKind.expense).first.id;
  var accountId = existing?.accountId ?? store.pickableAccounts().first.id;
  var start = existing != null ? parseDay(existing.startDay) : today();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final categories = store.categoriesOf(kind);
        return SheetFrame(
          title: existing == null ? 'New rule' : 'Edit rule',
          children: [
            Segmented<TxKind>(
              options: const {
                TxKind.expense: 'Spending',
                TxKind.income: 'Income',
              },
              value: kind,
              onChanged: (k) => setSheet(() {
                kind = k;
                categoryId = store.categoriesOf(k).first.id;
              }),
            ),
            const SizedBox(height: 14),
            AmountField(
              value: amount,
              positiveOnly: true,
              onChanged: (v) => setSheet(() => amount = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              decoration: const InputDecoration(hintText: 'Rent, Salary…'),
            ),
            const SizedBox(height: 14),
            Segmented<Freq>(
              options: const {
                Freq.daily: 'Daily',
                Freq.weekly: 'Weekly',
                Freq.monthly: 'Monthly',
              },
              value: freq,
              onChanged: (f) => setSheet(() => freq = f),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  PickChip(
                    label: c.name,
                    icon: iconFor(c.icon),
                    colour: catColorAt(c.color),
                    selected: c.id == categoryId,
                    onTap: () => setSheet(() => categoryId = c.id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in store.pickableAccounts(accountId))
                  PickChip(
                    label: a.name,
                    icon: iconFor(a.icon),
                    colour: catColorAt(a.color),
                    selected: a.id == accountId,
                    onTap: () => setSheet(() => accountId = a.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'First occurrence',
                );
                if (picked != null) setSheet(() => start = picked);
              },
              child: Text('Starts ${shortDate(start)}'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: amount <= 0
                  ? null
                  : () {
                      if (existing == null) {
                        store.addRule(
                          Rule(
                            kind: kind,
                            amountMinor: amount,
                            categoryId: categoryId,
                            accountId: accountId,
                            note: note.text.trim(),
                            freq: freq,
                            startDay: dayKey(start),
                          ),
                        );
                      } else {
                        existing
                          ..kind = kind
                          ..amountMinor = amount
                          ..categoryId = categoryId
                          ..accountId = accountId
                          ..note = note.text.trim()
                          ..freq = freq
                          ..startDay = dayKey(start);
                        store.touch();
                      }
                      // A rule moved into the past owes rows the moment it is
                      // saved, not on the next launch. `lastRunDay` is left
                      // where it is, so nothing already materialised repeats.
                      materialiseDue(store);
                      Navigator.pop(context);
                    },
              child: Text(existing == null ? 'Add rule' : 'Save'),
            ),
            if (existing != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmRemoveRule(host, store, existing);
                },
                child: const Text('Stop this rule'),
              ),
          ],
        );
      },
    ),
  );
}

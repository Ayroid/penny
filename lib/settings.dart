import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'icons.dart';
import 'money.dart';
import 'recurring.dart';
import 'store.dart';
import 'theme.dart';

void openSettings(BuildContext context, PennyStore store) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SettingsScreen(store: store)));

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
              _Row(
                icon: LucideIcons.wallet,
                label: 'Accounts',
                subtitle:
                    '${store.liveAccounts.length} · ${rupees(store.totalBalance)}',
                onTap: () => _showAccounts(context, store),
              ),
              _Row(
                icon: LucideIcons.tag,
                label: 'Categories',
                subtitle: '${store.categories.where((c) => !c.archived).length}',
                onTap: () => _showCategories(context, store),
              ),
              _Row(
                icon: LucideIcons.repeat,
                label: 'Recurring',
                subtitle: store.rules.isEmpty
                    ? 'Rent, salary, subscriptions'
                    : '${store.rules.length} ${store.rules.length == 1 ? 'rule' : 'rules'}',
                onTap: () => _showRules(context, store),
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
                      Text(label,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: Theme.of(context).textTheme.bodySmall),
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
          'This will replace all ${store.txns.length} transactions, accounts and categories with what is in that file.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Replace',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final good = store.importJson(raw);
  messenger.showSnackBar(SnackBar(
    content: Text(good ? 'Backup restored' : 'That file could not be read'),
  ));
}

// ── Accounts ────────────────────────────────────────────────────────────────

Future<void> _showAccounts(BuildContext context, PennyStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => _ListSheet(
        title: 'Accounts',
        onAdd: () => _editAccount(context, store, null),
        children: [
          for (final a in store.accounts)
            _EditableRow(
              icon: iconFor(a.icon),
              colour: catColorAt(a.color),
              label: a.name,
              trailing: rupees(store.balanceOf(a.id)),
              archived: a.archived,
              onTap: () => _editAccount(context, store, a),
            ),
        ],
      ),
    ),
  );
}

Future<void> _editAccount(
    BuildContext context, PennyStore store, Account? existing) {
  final name = TextEditingController(text: existing?.name ?? '');
  var opening = existing?.openingBalanceMinor ?? 0;
  var colour = existing?.color ?? defaultCatColor;
  var icon = existing?.icon ?? 'wallet';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => _EditSheet(
        title: existing == null ? 'New account' : 'Edit account',
        nameController: name,
        nameHint: 'Cash, Bank, Card…',
        colour: colour,
        icon: icon,
        onColour: (c) => setSheet(() => colour = c),
        onIcon: (i) => setSheet(() => icon = i),
        extra: [
          Text('OPENING BALANCE',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          _SignedAmountField(
            value: opening,
            onChanged: (v) => setSheet(() => opening = v),
          ),
        ],
        onArchive: existing == null
            ? null
            : () {
                store.setAccountArchived(existing, !existing.archived);
                Navigator.pop(context);
              },
        archived: existing?.archived ?? false,
        onSave: name.text.trim().isEmpty
            ? null
            : () {
                if (existing == null) {
                  store.addAccount(Account(
                      name: name.text.trim(),
                      icon: icon,
                      color: colour,
                      openingBalanceMinor: opening));
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
      builder: (context, _) => _ListSheet(
        title: 'Categories',
        onAdd: () => _editCategory(context, store, null),
        children: [
          for (final kind in [TxKind.expense, TxKind.income]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text(kind == TxKind.expense ? 'SPENDING' : 'INCOME',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            for (final c in store.categories.where((c) => c.kind == kind))
              _EditableRow(
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
    BuildContext context, PennyStore store, Category? existing) {
  final name = TextEditingController(text: existing?.name ?? '');
  var colour = existing?.color ?? defaultCatColor;
  var icon = existing?.icon ?? defaultIcon;
  var kind = existing?.kind ?? TxKind.expense;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => _EditSheet(
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
                TxKind.income: 'Income'
              },
              value: kind,
              onChanged: (k) => setSheet(() => kind = k),
            ),
        ],
        onArchive: existing == null
            ? null
            : () {
                store.setCategoryArchived(existing, !existing.archived);
                Navigator.pop(context);
              },
        archived: existing?.archived ?? false,
        onSave: name.text.trim().isEmpty
            ? null
            : () {
                if (existing == null) {
                  store.addCategory(Category(
                      name: name.text.trim(),
                      kind: kind,
                      icon: icon,
                      color: colour));
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
      builder: (context, _) => _ListSheet(
        title: 'Recurring',
        onAdd: () => _editRule(context, store),
        empty: store.rules.isEmpty
            ? 'Rent, salary and subscriptions add themselves when they come due.'
            : null,
        children: [
          for (final r in store.rules)
            _EditableRow(
              icon: iconFor(store.categoryById(r.categoryId)?.icon ?? 'repeat'),
              colour: catColorAt(
                  store.categoryById(r.categoryId)?.color ?? defaultCatColor),
              label: r.note.isEmpty
                  ? store.categoryById(r.categoryId)?.name ?? 'Rule'
                  : r.note,
              trailing: '${rupeesWhole(r.amountMinor)} · ${r.freq.name}',
              archived: !r.active,
              onTap: () => _confirmRemoveRule(context, store, r),
            ),
        ],
      ),
    ),
  );
}

Future<void> _confirmRemoveRule(
    BuildContext context, PennyStore store, Rule rule) async {
  final go = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Stop this rule?'),
      content: const Text(
          'Transactions it has already added stay in the ledger. Only future ones stop.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Stop',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ),
  );
  if (go == true) store.removeRule(rule);
}

Future<void> _editRule(BuildContext context, PennyStore store) {
  final note = TextEditingController();
  var amount = 0;
  var kind = TxKind.expense;
  var freq = Freq.monthly;
  var categoryId = store.categoriesOf(TxKind.expense).first.id;
  var accountId = store.liveAccounts.first.id;
  var start = today();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final categories = store.categoriesOf(kind);
        return _SheetFrame(
          title: 'New rule',
          children: [
            Segmented<TxKind>(
              options: const {TxKind.expense: 'Spending', TxKind.income: 'Income'},
              value: kind,
              onChanged: (k) => setSheet(() {
                kind = k;
                categoryId = store.categoriesOf(k).first.id;
              }),
            ),
            const SizedBox(height: 14),
            _SignedAmountField(
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
                  _Chip(
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
                for (final a in store.liveAccounts)
                  _Chip(
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
                      store.addRule(Rule(
                        kind: kind,
                        amountMinor: amount,
                        categoryId: categoryId,
                        accountId: accountId,
                        note: note.text.trim(),
                        freq: freq,
                        startDay: dayKey(start),
                      ));
                      materialiseDue(store);
                      Navigator.pop(context);
                    },
              child: const Text('Add rule'),
            ),
          ],
        );
      },
    ),
  );
}

// ── Shared sheet furniture ──────────────────────────────────────────────────

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children, this.action});

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleLarge)),
                      ?action,
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListSheet extends StatelessWidget {
  const _ListSheet({
    required this.title,
    required this.children,
    required this.onAdd,
    this.empty,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onAdd;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: title,
      action: RoundIconButton(
        icon: LucideIcons.plus,
        tooltip: 'Add',
        filled: true,
        onPressed: onAdd,
      ),
      children: [
        if (empty != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(empty!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ...children,
      ],
    );
  }
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    required this.icon,
    required this.colour,
    required this.label,
    required this.onTap,
    this.trailing,
    this.archived = false,
  });

  final IconData icon;
  final Color colour;
  final String label;
  final String? trailing;
  final VoidCallback onTap;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      // Archived dims rather than disappears — it is still yours, just retired.
      opacity: archived ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: isDark(context) ? 0.15 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: colour),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (trailing != null)
                Text(trailing!, style: mono(12, color: scheme.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditSheet extends StatelessWidget {
  const _EditSheet({
    required this.title,
    required this.nameController,
    required this.nameHint,
    required this.colour,
    required this.icon,
    required this.onColour,
    required this.onIcon,
    required this.onSave,
    this.extra = const [],
    this.onArchive,
    this.archived = false,
  });

  final String title;
  final TextEditingController nameController;
  final String nameHint;
  final int colour;
  final String icon;
  final ValueChanged<int> onColour;
  final ValueChanged<String> onIcon;
  final VoidCallback? onSave;
  final List<Widget> extra;
  final VoidCallback? onArchive;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setSheet) => _SheetFrame(
        title: title,
        children: [
          TextField(
            controller: nameController,
            autofocus: nameController.text.isEmpty,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setSheet(() {}),
            decoration: InputDecoration(hintText: nameHint),
          ),
          const SizedBox(height: 14),
          if (extra.isNotEmpty) ...[...extra, const SizedBox(height: 14)],
          Text('COLOUR', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < catColors.length; i++)
                Semantics(
                  button: true,
                  selected: i == colour,
                  label: catColors[i].name,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onColour(i),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: catColors[i].value,
                        shape: BoxShape.circle,
                        border: i == colour
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2.5)
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('ICON', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 168,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in iconByKey.keys)
                    Semantics(
                      button: true,
                      selected: key == icon,
                      label: key,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => onIcon(key),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: key == icon
                                ? catColorAt(colour)
                                    .withValues(alpha: 0.22)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(iconFor(key),
                              size: 18,
                              color: key == icon
                                  ? catColorAt(colour)
                                  : Theme.of(context).colorScheme.secondary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: nameController.text.trim().isEmpty ? null : onSave,
            child: const Text('Save'),
          ),
          if (onArchive != null)
            TextButton(
              onPressed: onArchive,
              child: Text(archived ? 'Bring back' : 'Archive'),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 9, 13, 9),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: selected ? 0.28 : 0.10),
            borderRadius: BorderRadius.circular(pill),
            border: selected ? Border.all(color: colour, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rupee amount typed as digits.
///
/// Same rule as the entry keypad: the value is built in paise, so there is no
/// decimal separator to parse and no rounding step. The field only ever holds
/// digits, and the label above it shows what they mean.
class _SignedAmountField extends StatefulWidget {
  const _SignedAmountField({
    required this.value,
    required this.onChanged,
    this.positiveOnly = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool positiveOnly;

  @override
  State<_SignedAmountField> createState() => _SignedAmountFieldState();
}

class _SignedAmountFieldState extends State<_SignedAmountField> {
  late final _controller =
      TextEditingController(text: widget.value == 0 ? '' : '${widget.value.abs()}');
  late bool _negative = widget.value < 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit() {
    final digits = int.tryParse(_controller.text) ?? 0;
    widget.onChanged(_negative ? -digits : digits);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!widget.positiveOnly)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: RoundIconButton(
              icon: _negative ? LucideIcons.minus : LucideIcons.plus,
              tooltip: _negative ? 'Negative' : 'Positive',
              onPressed: () {
                setState(() => _negative = !_negative);
                _emit();
              },
            ),
          ),
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(_emit),
            decoration: InputDecoration(
              hintText: '0',
              prefixText: '$rupee ',
              helperText: rupees(widget.value, signed: true),
              helperStyle: mono(11,
                  color: Theme.of(context).colorScheme.secondary),
            ),
          ),
        ),
      ],
    );
  }
}

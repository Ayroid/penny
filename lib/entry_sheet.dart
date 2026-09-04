import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'icons.dart';
import 'money.dart';
import 'store.dart';
import 'theme.dart';

/// Add a transaction, or edit [existing].
///
/// One sheet for both, as in Wick: a create form and an edit form that drift
/// apart is two bugs waiting rather than one screen.
Future<void> showEntrySheet(
  BuildContext context,
  PennyStore store, {
  Txn? existing,
  TxKind initialKind = TxKind.expense,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _EntrySheet(
      store: store,
      existing: existing,
      initialKind: existing?.kind ?? initialKind,
    ),
  );
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    required this.store,
    required this.existing,
    required this.initialKind,
  });

  final PennyStore store;
  final Txn? existing;
  final TxKind initialKind;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late TxKind _kind = widget.initialKind;

  late final _amount = TextEditingController(
    text: amountFieldText(widget.existing?.amountMinor ?? 0),
  );
  late DateTime _day = widget.existing != null
      ? parseDay(widget.existing!.day)
      : today();
  late String? _categoryId = widget.existing?.categoryId;
  late String _accountId =
      widget.existing?.accountId ?? widget.store.liveAccounts.first.id;
  late String? _toAccountId = widget.existing?.toAccountId;
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  /// Whether this should be kept one tap away on the overview. Reflects what
  /// is already pinned when editing, so the toggle is never a lie.
  late bool _pinned =
      widget.existing != null &&
      widget.store.shortcutFor(widget.existing!) != null;

  /// Paise. The amount is a string only while it is being typed — it is
  /// parsed exactly once, here, and is an integer everywhere else.
  int get _minor => parseRupees(_amount.text) ?? 0;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Categories for the current kind. A transfer borrows the expense list
  /// purely so the row has something to group under; the breakdowns ignore it.
  List<Category> get _categories => widget.store.categoriesOf(
    _kind == TxKind.income ? TxKind.income : TxKind.expense,
  );

  Category? get _category {
    final list = _categories;
    if (list.isEmpty) return null;
    for (final c in list) {
      if (c.id == _categoryId) return c;
    }
    return list.first;
  }

  bool get _valid =>
      _minor > 0 &&
      _category != null &&
      (_kind != TxKind.transfer ||
          (_toAccountId != null && _toAccountId != _accountId));

  void _save() {
    final t = widget.existing;
    if (t == null) {
      widget.store.addTxn(
        Txn(
          kind: _kind,
          amountMinor: _minor,
          day: dayKey(_day),
          categoryId: _category!.id,
          accountId: _accountId,
          toAccountId: _kind == TxKind.transfer ? _toAccountId : null,
          note: _note.text.trim(),
        ),
      );
    } else {
      // Un-pin against the row as it was, before the edits land — otherwise a
      // changed amount leaves the old shortcut orphaned on the overview.
      final existing = widget.store.shortcutFor(t);
      if (existing != null) widget.store.removeShortcut(existing);

      t
        ..kind = _kind
        ..amountMinor = _minor
        ..day = dayKey(_day)
        ..categoryId = _category!.id
        ..accountId = _accountId
        ..toAccountId = _kind == TxKind.transfer ? _toAccountId : null
        ..note = _note.text.trim();
      widget.store.touch();
    }

    if (_pinned) {
      widget.store.addShortcut(
        Shortcut(
          kind: _kind,
          amountMinor: _minor,
          categoryId: _category!.id,
          accountId: _accountId,
          toAccountId: _kind == TxKind.transfer ? _toAccountId : null,
          note: _note.text.trim(),
        ),
      );
    }

    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: today(),
      helpText: 'When did the money move?',
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final category = _category;

    return Padding(
      // The sheet must ride above the software keyboard, which is up as soon
      // as it opens — the amount field autofocuses.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          // Without a ceiling the sheet runs off
          // a short screen — a small phone in landscape, or a desktop window —
          // and overflows instead of scrolling.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: scheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Segmented<TxKind>(
                    options: const {
                      TxKind.expense: 'Spent',
                      TxKind.income: 'Earned',
                      TxKind.transfer: 'Moved',
                    },
                    value: _kind,
                    onChanged: (k) => setState(() {
                      _kind = k;
                      _categoryId = null;
                      if (k == TxKind.transfer) {
                        _toAccountId ??= widget.store.liveAccounts
                            .firstWhere(
                              (a) => a.id != _accountId,
                              orElse: () => widget.store.liveAccounts.first,
                            )
                            .id;
                      }
                    }),
                  ),
                  const SizedBox(height: 24),

                  // The amount, typed on the platform's own numeric keyboard.
                  //
                  // The rupee sign is a sibling of the field rather than its
                  // `prefixText`: a prefix sits at the input's left edge while
                  // a centred value centres in whatever is left of it, so the
                  // two drift apart across the screen. Sized to its content
                  // instead, so the pair stays centred together as digits are
                  // typed.
                  Center(
                    // A maximum amount is 11 mono characters at 40px, which is
                    // within a hair of the sheet's width on a narrow phone.
                    // Scaling down beats overflowing.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(rupee, style: _amountStyle(scheme.secondary)),
                          const SizedBox(width: 4),
                          IntrinsicWidth(
                            child: TextField(
                              controller: _amount,
                              autofocus: widget.existing == null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [amountInputFormatter],
                              onChanged: (_) => setState(() {}),
                              style: _amountStyle(scheme.onSurface),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: '0',
                                hintStyle: _amountStyle(scheme.secondary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_kind != TxKind.transfer)
                        _Pick(
                          icon: category == null
                              ? LucideIcons.tag
                              : iconFor(category.icon),
                          label: category?.name ?? 'Category',
                          color: category == null
                              ? null
                              : catColorAt(category.color),
                          onTap: _pickCategory,
                        ),
                      _Pick(
                        icon: iconFor(
                          widget.store.accountById(_accountId)?.icon ??
                              'wallet',
                        ),
                        label:
                            widget.store.accountById(_accountId)?.name ?? '—',
                        onTap: () => _pickAccount(
                          current: _accountId,
                          onPicked: (id) => setState(() {
                            _accountId = id;
                            if (_toAccountId == id) _toAccountId = null;
                          }),
                        ),
                      ),
                      if (_kind == TxKind.transfer)
                        _Pick(
                          icon: LucideIcons.arrowRight,
                          label: _toAccountId == null
                              ? 'To…'
                              : widget.store.accountById(_toAccountId!)!.name,
                          onTap: () => _pickAccount(
                            current: _toAccountId,
                            exclude: _accountId,
                            onPicked: (id) => setState(() => _toAccountId = id),
                          ),
                        ),
                      _Pick(
                        icon: LucideIcons.calendar,
                        label: _dayLabel(_day),
                        onTap: _pickDate,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Note (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pinning is opt-in and explicit: the overview's strip is
                  // what the person chose to keep, never what the app guessed
                  // they meant.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _Pick(
                      icon: _pinned
                          ? LucideIcons.bookmarkCheck
                          : LucideIcons.bookmark,
                      label: _pinned
                          ? 'Pinned to the overview'
                          : 'Pin to the overview',
                      color: _pinned ? null : scheme.secondary,
                      onTap: () => setState(() => _pinned = !_pinned),
                    ),
                  ),
                  const SizedBox(height: 12),

                  FilledButton(
                    onPressed: _valid ? _save : null,
                    child: Text(widget.existing == null ? 'Add' : 'Save'),
                  ),
                  if (widget.existing != null)
                    TextButton(
                      onPressed: () {
                        widget.store.removeTxn(widget.existing!);
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Delete',
                        style: text.labelLarge?.copyWith(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The headline figure's type. Shared so the sign, the value and the hint
  /// cannot drift out of step.
  TextStyle _amountStyle(Color color) =>
      mono(40, color: color, weight: FontWeight.w700, spacing: -0.5);

  String _dayLabel(DateTime d) {
    final t = today();
    if (d == t) return 'Today';
    if (d == shiftDays(t, -1)) return 'Yesterday';
    return shortDate(d);
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PickerSheet(
        title: 'Category',
        items: [
          for (final c in _categories)
            (
              id: c.id,
              label: c.name,
              icon: iconFor(c.icon),
              color: catColorAt(c.color),
            ),
        ],
        current: _category?.id,
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  Future<void> _pickAccount({
    required String? current,
    String? exclude,
    required ValueChanged<String> onPicked,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PickerSheet(
        title: 'Account',
        items: [
          for (final a in widget.store.liveAccounts)
            if (a.id != exclude)
              (
                id: a.id,
                label: a.name,
                icon: iconFor(a.icon),
                color: catColorAt(a.color),
              ),
        ],
        current: current,
      ),
    );
    if (picked != null) onPicked(picked);
  }
}

/// A pill that opens a picker. Reads as a value, not as a form control.
class _Pick extends StatelessWidget {
  const _Pick({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? sproutOf(context);

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: accent.withValues(alpha: isDark(context) ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(pill),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: accent),
                const SizedBox(width: 7),
                // Flexible, because a pill's label is whatever the person
                // named their category — a long one has to ellipsize rather
                // than push the row past its bounds.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Item = ({String id, String label, IconData icon, Color color});

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.current,
  });

  final String title;
  final List<_Item> items;
  final String? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in items)
                      CategoryAccent(
                        color: i.color,
                        child: Builder(
                          builder: (context) => _Pick(
                            icon: i.icon,
                            label: i.label,
                            color: i.id == current ? null : i.color,
                            onTap: () => Navigator.of(context).pop(i.id),
                          ),
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

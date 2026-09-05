import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'icons.dart';
import 'money.dart';
import 'theme.dart';

// The bottom-sheet furniture shared by settings and goals: a frame, a list
// with an add button, a row in that list, a name/colour/icon editor, a
// selectable chip and an amount field. Lifted out of settings.dart when goals
// needed the same five things — a second copy is how two editors drift apart.

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.children,
    this.action,
    this.pinned,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  /// Buttons held at the bottom, outside the scroll.
  ///
  /// A sheet with a tall picker in it can outgrow the screen, and then the one
  /// thing that has to stay reachable — Save — is the thing that scrolls away
  /// first, behind a grid that eats the drag meant for the sheet.
  final Widget? pinned;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Nine tenths rather than the old .85: the edit sheet carries a
            // four-row icon grid now, and the strip of page left showing
            // above it is still enough to read as a sheet.
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      pinned == null ? 20 : 12,
                    ),
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
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
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
              if (pinned != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: pinned,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ListSheet extends StatelessWidget {
  const ListSheet({
    super.key,
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
    return SheetFrame(
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
            child: Text(
              empty!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ...children,
      ],
    );
  }
}

class EditableRow extends StatelessWidget {
  const EditableRow({
    super.key,
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
                  color: colour.withValues(
                    alpha: isDark(context) ? 0.15 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: colour),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (trailing != null)
                Text(trailing!, style: mono(12, color: scheme.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class EditSheet extends StatelessWidget {
  const EditSheet({
    super.key,
    required this.title,
    required this.nameController,
    required this.nameHint,
    required this.colour,
    required this.icon,
    required this.onColour,
    required this.onIcon,
    required this.onSave,
    this.extra = const [],
    this.footer,
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

  /// What sits under Save: archiving, for a category; deleting, for a goal.
  /// The caller words its own button — a label chosen from a flag here is a
  /// knob that grows one more option every time something new reuses this.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setSheet) => SheetFrame(
        title: title,
        pinned: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: nameController.text.trim().isEmpty ? null : onSave,
              child: const Text('Save'),
            ),
            if (footer != null) const SizedBox(height: 10),
            ?footer,
          ],
        ),
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
          // Two rows deep and scrolling past that: twenty-one swatches wrapped
          // in full cost a third of the sheet, and that height belongs to the
          // icon grid under them.
          SizedBox(
            height: 68,
            child: SingleChildScrollView(
              child: Wrap(
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    width: 2.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('ICON', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _IconPicker(selected: icon, colour: colour, onPick: onIcon),
        ],
      ),
    );
  }
}

class PickChip extends StatelessWidget {
  const PickChip({
    super.key,
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
            color: colour.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(pill),
            // The ring is always drawn, transparent when unselected: a border
            // that appears on selection grows the pill by 3px and shoves the
            // row along. Selection is the outline and nothing else.
            border: Border.all(
              color: selected ? colour : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon grid, with the whole of Lucide behind a search box.
///
/// A grid rather than a `Wrap`, and lazily built: the shortlist is a few dozen
/// icons but the list behind it is two thousand, and building all of them for
/// a 168-high window is work nobody sees.
class _IconPicker extends StatefulWidget {
  const _IconPicker({
    required this.selected,
    required this.colour,
    required this.onPick,
  });

  final String selected;
  final int colour;
  final ValueChanged<String> onPick;

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    // Lucide's names are the search index — they are kebab-case, so a space
    // typed between words still finds `piggy-bank`.
    final needle = q.replaceAll(' ', '-');
    final keys = needle.isEmpty
        ? iconKeys
        : [
            for (final k in iconKeys)
              if (k.contains(needle)) k,
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ${iconKeys.length} icons',
            prefixIcon: Icon(
              LucideIcons.search,
              size: 16,
              color: scheme.secondary,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 38),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          // Three rows, whatever the width: a cell is 48 at its widest and the
          // gaps are 8, so 3 x 48 + 2 x 8 is the tallest three rows can be.
          height: 160,
          child: keys.isEmpty
              ? Center(
                  child: Text(
                    'No icon called "$_query"',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 48,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final key = keys[i];
                    final picked = key == widget.selected;
                    return Semantics(
                      button: true,
                      selected: picked,
                      label: key,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => widget.onPick(key),
                        child: Container(
                          decoration: BoxDecoration(
                            color: picked
                                ? catColorAt(
                                    widget.colour,
                                  ).withValues(alpha: 0.22)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            iconFor(key),
                            size: 18,
                            color: picked
                                ? catColorAt(widget.colour)
                                : scheme.secondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A rupee amount, typed on the platform's numeric keyboard.
///
/// Rupees with an optional decimal, the way the field's own ₹ implies — this
/// used to read the digits as paise, so typing 100 showed "₹ 100" and meant
/// ₹1.00. Parsed once by [parseRupees] and held as an int thereafter.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.value,
    required this.onChanged,
    this.positiveOnly = false,
    this.trailing,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool positiveOnly;

  /// Sits at the right end of the field — a warning about the amount, say.
  final Widget? trailing;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final _controller = TextEditingController(
    text: amountFieldText(widget.value.abs()),
  );
  late bool _negative = widget.value < 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit() {
    final minor = parseRupees(_controller.text) ?? 0;
    widget.onChanged(_negative ? -minor : minor);
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [amountInputFormatter],
            onChanged: (_) => setState(_emit),
            // No helper line echoing the figure back: the field already shows
            // it, with the ₹ in front, and a second formatted copy underneath
            // is one more thing to read on a sheet that is mostly reading.
            decoration: InputDecoration(
              hintText: '0',
              prefixText: '$rupee ',
              // Inside the field's own ground rather than beside it: the note
              // is about this number, and a row that grows a widget when
              // something is wrong shoves the whole sheet down.
              suffixIcon: widget.trailing,
              suffixIconConstraints: const BoxConstraints(minWidth: 40),
            ),
          ),
        ),
      ],
    );
  }
}

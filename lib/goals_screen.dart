import 'package:flutter/material.dart';

import 'entry_sheet.dart';
import 'icons.dart';
import 'money.dart';
import 'page_bar.dart';
import 'penny.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';

/// What you are saving for, and how far along it is.
///
/// A page rather than a settings sheet because this is the one screen you open
/// to feel good about money you have not spent — the rest of the app is a
/// record of money that has already moved.
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.store});

  final PennyStore store;

  @override
  Widget build(BuildContext context) {
    final goals = store.goals;

    return Scaffold(
      floatingActionButton: AddButton(
        tooltip: 'Add a goal',
        onPressed: () => _editGoal(context, store, null),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Goals',
              subtitle: goals.isEmpty
                  ? 'What you are saving for'
                  : '${plural(goals.length, 'goal')} · '
                        '${store.show(rupeesWhole(store.totalSetAside))} set aside',
            ),
            Expanded(
              child: goals.isEmpty
                  ? PennyMessage(
                      // The pose that shipped in the APK for months without
                      // ever being drawn. This is what it was for.
                      pose: Penny.focus,
                      headline: 'Nothing saved for yet',
                      body:
                          'Put money aside as you go. Nothing moves between '
                          'accounts — a goal only marks what is spoken for.',
                      actionLabel: 'Add a goal',
                      onAction: () => _editGoal(context, store, null),
                      size: 132,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                      itemCount: goals.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) =>
                          _GoalCard(store: store, goal: goals[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.store, required this.goal});

  final PennyStore store;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final colour = catColorAt(goal.color);
    final status = store.statusOf(goal);
    final percent = (status.progress * 100).round();

    return Semantics(
      button: true,
      label: store.hideAmounts
          ? '${goal.name}, $percent percent saved'
          : '${goal.name}, ${rupees(status.saved)} of '
                '${rupees(goal.targetMinor)}, $percent percent',
      excludeSemantics: true,
      child: TintCard(
        onTap: () => _showGoal(context, store, goal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colour.withValues(
                      alpha: isDark(context) ? 0.15 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(iconFor(goal.icon), size: 17, color: colour),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    goal.name,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // "Ready" rather than "100%": the number is the same either
                // way, and one of them tells you what to do about it.
                Text(
                  status.reached ? 'READY' : '$percent%',
                  style: mono(
                    11,
                    color: status.reached
                        ? sproutOf(context)
                        : scheme.secondary,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: status.progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(pill),
              color: colour,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            // Whole rupees: three exact figures wrap onto a second line on a
            // narrow phone, and nobody saves for a trip to the paise.
            Text(
              '${store.show(rupeesWhole(status.saved))} of '
              '${store.show(rupeesWhole(goal.targetMinor))}'
              '${status.reached ? '' : ' · ${store.show(rupeesWhole(status.remaining))} to go'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: monoStrut(11.5),
              style: mono(11.5, color: scheme.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the contribute sheet is asking its caller to do.
enum _Ask { put, take, bought, edit }

/// Put money aside, take it back out, edit the goal, or close it.
///
/// The sheet itself decides nothing: it pops what the person asked for and the
/// caller applies it, because the celebration that follows a contribution has
/// to be shown from a context that outlives the sheet.
Future<void> _showGoal(
  BuildContext context,
  PennyStore store,
  Goal goal,
) async {
  final asked =
      await showModalBottomSheet<({_Ask ask, int amount, String accountId})>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _ContributeSheet(store: store, goal: goal),
      );
  if (asked == null || !context.mounted) return;

  switch (asked.ask) {
    case _Ask.edit:
      return _editGoal(context, store, goal);
    case _Ask.bought:
      return _confirmBought(context, store, goal);
    case _Ask.take:
      // Taking money back out never celebrates, and never un-celebrates: the
      // milestones already seen stay claimed.
      store.takeOut(goal, asked.amount, asked.accountId);
      return;
    case _Ask.put:
      store.putAside(goal, asked.amount, asked.accountId);
  }

  final milestone = store.claimMilestone(goal);
  if (milestone == null || !context.mounted) return;

  await showPennyMoment(
    context,
    // The other pose that never had a caller. A finished goal is the one
    // moment in a money app that is unambiguously worth drawing.
    pose: milestone == 100 ? Penny.complete : Penny.celebrate,
    headline: switch (milestone) {
      100 => 'That is the whole thing',
      75 => 'Three quarters of the way',
      50 => 'Halfway there',
      _ => 'A quarter of the way',
    },
    body: milestone == 100
        ? '${store.show(rupees(store.statusOf(goal).saved))} sitting in Goals '
              'for ${goal.name}. Go and get it.'
        : '${store.show(rupees(store.statusOf(goal).saved))} of '
              '${store.show(rupees(goal.targetMinor))} for ${goal.name}.',
    action: milestone == 100 ? 'Nice' : 'Keep going',
  );
}

class _ContributeSheet extends StatefulWidget {
  const _ContributeSheet({required this.store, required this.goal});

  final PennyStore store;
  final Goal goal;

  @override
  State<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends State<_ContributeSheet> {
  int _amount = 0;

  /// Where the money comes from, or goes back to. Never the goals account
  /// itself: a transfer that starts and ends in the same place is not a
  /// movement of anything.
  late String _accountId = widget.store.liveAccounts
      .firstWhere((a) => !a.forGoals, orElse: () => widget.store.accounts.first)
      .id;

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final status = store.statusOf(goal);
    final accounts = [
      for (final a in store.liveAccounts)
        if (!a.forGoals) a,
    ];

    return SheetFrame(
      title: goal.name,
      children: [
        Text(
          status.reached
              ? '${store.show(rupeesWhole(status.saved))} in Goals. This one is ready.'
              : '${store.show(rupeesWhole(status.saved))} of '
                    '${store.show(rupeesWhole(goal.targetMinor))} · '
                    '${store.show(rupeesWhole(status.remaining))} to go',
          style: mono(12, color: scheme.secondary),
        ),
        const SizedBox(height: 14),
        AmountField(
          value: _amount,
          positiveOnly: true,
          onChanged: (v) => setState(() => _amount = v),
        ),
        const SizedBox(height: 14),
        // The money has to come out of something real. This is the account the
        // transfer leaves — or arrives back in, when it is being taken out.
        Text(
          status.saved > 0 ? 'FROM, OR BACK TO' : 'FROM',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in accounts)
              PickChip(
                label: a.name,
                icon: iconFor(a.icon),
                colour: catColorAt(a.color),
                selected: a.id == _accountId,
                onTap: () => setState(() => _accountId = a.id),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _amount <= 0
              ? null
              : () => Navigator.pop(context, (
                  ask: _Ask.put,
                  amount: _amount,
                  accountId: _accountId,
                )),
          child: const Text('Put it aside'),
        ),
        if (status.saved > 0)
          TextButton(
            // Capped at what the goal holds: it cannot hand back money that
            // was never put in it.
            onPressed: _amount <= 0 || _amount > status.saved
                ? null
                : () => Navigator.pop(context, (
                    ask: _Ask.take,
                    amount: _amount,
                    accountId: _accountId,
                  )),
            child: const Text('Take it back out'),
          ),
        if (status.reached)
          TextButton(
            onPressed: () => Navigator.pop(context, (
              ask: _Ask.bought,
              amount: 0,
              accountId: _accountId,
            )),
            child: const Text('Bought it'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, (
            ask: _Ask.edit,
            amount: 0,
            accountId: _accountId,
          )),
          child: const Text('Edit goal'),
        ),
      ],
    );
  }
}

/// Closing a goal by buying the thing.
///
/// The money is already sitting in the goals account, so the purchase is an
/// ordinary expense *out of* that account — the entry sheet opens with the
/// amount, the name and the account filled in. The goal itself goes; the
/// transfers that filled it stay in the ledger, because they happened.
/// Cancelling the sheet costs the goal but not the money, which is the
/// harmless way round.
Future<void> _confirmBought(
  BuildContext context,
  PennyStore store,
  Goal goal,
) async {
  final saved = store.statusOf(goal).saved;
  final go = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Bought it?'),
      content: Text(
        '${goal.name} closes. The spend goes in the ledger next, out of Goals '
        '— the amount and the name are already filled in.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not yet'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Bought it'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final vault = store.goalsAccount().id;
  final name = goal.name;
  store.removeGoal(goal);
  await showEntrySheet(
    context,
    store,
    initialAmountMinor: saved,
    initialNote: name,
    initialAccountId: vault,
  );
}

/// Add a goal, or edit [existing]. The same editor accounts and categories
/// use, with a target instead of an opening balance.
Future<void> _editGoal(BuildContext context, PennyStore store, Goal? existing) {
  final host = context;
  final name = TextEditingController(text: existing?.name ?? '');
  var target = existing?.targetMinor ?? 0;
  var colour = existing?.color ?? defaultCatColor;
  var icon = existing?.icon ?? 'piggy-bank';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => EditSheet(
        title: existing == null ? 'New goal' : 'Edit goal',
        nameController: name,
        nameHint: 'A phone, a trip, a rainy day…',
        colour: colour,
        icon: icon,
        onColour: (c) => setSheet(() => colour = c),
        onIcon: (i) => setSheet(() => icon = i),
        extra: [
          Text('TARGET', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          AmountField(
            value: target,
            positiveOnly: true,
            onChanged: (v) => setSheet(() => target = v),
          ),
        ],
        footer: existing == null
            ? null
            : TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmDeleteGoal(host, store, existing);
                },
                child: const Text('Delete goal'),
              ),
        onSave: name.text.trim().isEmpty || target <= 0
            ? null
            : () {
                if (existing == null) {
                  store.addGoal(
                    Goal(
                      name: name.text.trim(),
                      targetMinor: target,
                      icon: icon,
                      color: colour,
                    ),
                  );
                } else {
                  existing
                    ..name = name.text.trim()
                    ..targetMinor = target
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

Future<void> _confirmDeleteGoal(
  BuildContext context,
  PennyStore store,
  Goal goal,
) async {
  final go = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Delete this goal?'),
      content: Text(
        'The ${store.show(rupeesWhole(store.statusOf(goal).saved))} stays in '
        'the Goals account and the transfers stay in the ledger — only the '
        'goal goes. Take it back out first if you want it somewhere else.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (go == true) store.removeGoal(goal);
}

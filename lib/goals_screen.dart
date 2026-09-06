import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'entry_sheet.dart';
import 'icons.dart';
import 'money.dart';
import 'penny.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';

/// What you are saving for, and how far along it is.
///
/// A page rather than a settings sheet because this is the one screen you open
/// to feel good about money you have not spent — the rest of the app is a
/// record of money that has already moved.
class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key, required this.store});

  final PennyStore store;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

/// Which goals the page is showing.
enum _Show { all, going, done }

class _GoalsPageState extends State<GoalsPage> {
  _Show _show = _Show.all;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    // A goal that is ready is the loudest thing this page has to say, so it
    // says it first. Two passes rather than a comparator: `List.sort` is not
    // stable, and the order the goals were made in is the order underneath.
    final live = store.liveGoals;
    final all = [
      for (final g in live)
        if (store.statusOf(g).reached) g,
      for (final g in live)
        if (!store.statusOf(g).reached) g,
    ];
    final goals = switch (_show) {
      _Show.all => all,
      _Show.going => [
        for (final g in all)
          if (!store.statusOf(g).reached) g,
      ],
      _Show.done => [
        for (final g in all)
          if (store.statusOf(g).reached) g,
      ],
    };

    final rows = <Widget>[
      _Hero(store: store, goals: all),
      // The filter replaces a label that only ever said the obvious. Kept
      // even when it would change nothing, so it does not appear and
      // disappear as goals are finished.
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Segmented<_Show>(
          options: const {
            _Show.all: 'All',
            _Show.going: 'In progress',
            _Show.done: 'Completed',
          },
          value: _show,
          onChanged: (v) => setState(() => _show = v),
        ),
      ),
      if (goals.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
            _show == _Show.done
                ? 'Nothing finished yet.'
                : 'Every goal is finished.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      else ...[
        for (final g in goals) _GoalCard(store: store, goal: g),
        // Penny reads the whole page, not the slice the filter left.
        _Footer(store: store, goals: all),
      ],
      _AddGoal(onTap: () => _editGoal(context, store, null)),
      // The way back to what was put away. A row rather than a fourth chip on
      // the filter: `Segmented` says three options is where a pill stops being
      // a pill, and this is a door, not a view of the same page.
      if (store.archivedGoals.isNotEmpty)
        _ArchivedLink(
          count: store.archivedGoals.length,
          onTap: () => _showArchived(context, store),
        ),
    ];

    // No floating button on this page: a goal is not a thing you add in a
    // hurry from the corner of the screen, it is a decision, and the button
    // for it says so in words at the end of the list.
    return Scaffold(
      body: all.isEmpty
          // The link below the message rather than inside it: an empty page
          // with goals in the archive still has somewhere to go, and the
          // message is not the place to say so twice.
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: PennyMessage(
                    // The pose that shipped in the APK for months without
                    // ever being drawn. This is what it was for.
                    pose: Penny.focus,
                    headline: store.archivedGoals.isEmpty
                        ? 'Nothing saved for yet'
                        : 'Nothing on the go',
                    body:
                        'Put money aside as you go. Nothing moves between '
                        'accounts — a goal only marks what is spoken for.',
                    actionLabel: 'Add a goal',
                    onAction: () => _editGoal(context, store, null),
                    size: 132,
                  ),
                ),
                if (store.archivedGoals.isNotEmpty)
                  _ArchivedLink(
                    count: store.archivedGoals.length,
                    onTap: () => _showArchived(context, store),
                  ),
              ],
            )
          // The hero, the filter and Penny are rows of the list rather than
          // furniture around it: on a page with one goal the whole thing has
          // to scroll as one, and on a page with nine the hero should scroll
          // away like everything else. Built as a list rather than switched on
          // by index — the index arithmetic grew a second Add button the first
          // time a row became conditional.
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => rows[i],
            ),
    );
  }
}

/// The page's own add button, in words rather than a plus in the corner.
class _AddGoal extends StatelessWidget {
  const _AddGoal({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: sproutDeepOf(context),
            foregroundColor: Colors.white,
            // Hugs its label instead of spanning the page: it closes the list
            // rather than acting as the page's own footer.
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          icon: const Icon(LucideIcons.plus, size: 18),
          label: const Text('Add a new goal'),
        ),
      ),
    );
  }
}

/// The way into the archive, under the add button.
class _ArchivedLink extends StatelessWidget {
  const _ArchivedLink({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(LucideIcons.archive, size: 16),
        label: Text(plural(count, 'archived goal')),
      ),
    );
  }
}

/// What was put away, and the way to bring it back.
///
/// The sheet kit's own list, dimmed the way archived accounts and categories
/// are in settings — tapping a row opens the same editor, where Restore sits.
Future<void> _showArchived(BuildContext context, PennyStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => ListenableBuilder(
      listenable: store,
      builder: (sheet, _) {
        final archived = store.archivedGoals;
        return SheetFrame(
          title: 'Archived goals',
          children: [
            // Left open rather than dismissing itself once the last goal is
            // restored: the editor closes over this sheet, and a pop racing
            // that one pops whichever route happens to be on top.
            if (archived.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Nothing archived.',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheet).textTheme.bodySmall,
                ),
              ),
            for (final g in archived)
              EditableRow(
                icon: iconFor(g.icon),
                colour: sproutDeepOf(sheet),
                label: g.name,
                archived: true,
                trailing: store.show(rupeesWhole(store.statusOf(g).saved)),
                onTap: () => _editGoal(context, store, g),
              ),
          ],
        );
      },
    ),
  );
}

/// Everything set aside, across every goal.
///
/// The page's own answer to "how am I doing", above the goal-by-goal detail —
/// the shell's subtitle can only afford a line of small print.
class _Hero extends StatelessWidget {
  const _Hero({required this.store, required this.goals});

  final PennyStore store;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = sproutDeepOf(context);
    // White, which the deep green carries at 9:1 and the accent itself cannot
    // carry at all. Asserted in test/palette_test.dart.
    const ink = Colors.white;

    var saved = 0;
    var target = 0;
    var ready = 0;
    for (final g in goals) {
      final s = store.statusOf(g);
      saved += s.saved;
      target += g.targetMinor;
      if (s.reached) ready++;
    }
    final progress = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    final remaining = target - saved;

    return Semantics(
      label: store.hideAmounts
          ? '${(progress * 100).round()} percent of everything saved for'
          : '${rupees(saved)} of ${rupees(target)} set aside',
      excludeSemantics: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // Two stops of the one green rather than a flat fill: the panel is
          // the only thing on the page that is not a tinted card, and a
          // gradient is what keeps it from reading as a slab.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent,
              Color.alphaBlend(sprout.withValues(alpha: 0.16), accent),
            ],
          ),
        ),
        child: Stack(
          children: [
            // The climb, behind the numbers. Bottom-right and bleeding off
            // both edges, so it reads as scenery the panel is sitting in
            // rather than a picture pasted into it.
            Positioned(
              right: -12,
              bottom: -10,
              width: 250,
              child: Image.asset(
                'assets/images/mountains.png',
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                // Scenery, not a subject: it sits under the numbers and never
                // competes with them for the eye.
                opacity: const AlwaysStoppedAnimation(0.85),
                excludeFromSemantics: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SET ASIDE',
                          style: text.labelSmall?.copyWith(
                            color: ink.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                      if (ready > 0) ...[
                        _Pill(
                          '${plural(ready, 'goal')} ready',
                          ground: ink.withValues(alpha: 0.18),
                          ink: ink,
                        ),
                        const SizedBox(width: 6),
                      ],
                      _Pill(
                        '${(progress * 100).round()}%',
                        ground: ink.withValues(alpha: 0.18),
                        ink: ink,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          store.show(rupeesWhole(saved)),
                          style: text.headlineLarge?.copyWith(color: ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'of ${store.show(rupeesWhole(target))}',
                        style: mono(12, color: ink.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Grow(
                    value: progress,
                    builder: (context, t) => _Bar(
                      value: t,
                      colour: ink,
                      track: ink.withValues(alpha: 0.22),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    remaining > 0
                        ? '${store.show(rupeesWhole(remaining))} to go across '
                              '${plural(goals.length, 'goal')}'
                        : 'Every goal is funded.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: monoStrut(11.5),
                    style: mono(11.5, color: ink.withValues(alpha: 0.78)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small rounded count — a percentage, or how many goals are ready.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.ground, required this.ink});

  final String text;
  final Color ground;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(pill),
      ),
      child: Text(
        text,
        strutStyle: monoStrut(11),
        style: mono(11, color: ink, weight: FontWeight.w700),
      ),
    );
  }
}

/// Penny, at the bottom of the page, saying where it stands.
///
/// She was only ever drawn on the empty state — which is the one moment on
/// this page with nothing to be pleased about. Here she is holding the pig
/// for the money that is actually in it.
class _Footer extends StatelessWidget {
  const _Footer({required this.store, required this.goals});

  final PennyStore store;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final done = goals.every((g) => store.statusOf(g).reached);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          PennyImage(
            done ? Penny.celebrate : Penny.rest,
            size: 96,
            semanticLabel: 'Penny',
          ),
          const SizedBox(height: 10),
          Text(
            done ? 'All of it is ready.' : 'Nothing here has been spent yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            done
                ? 'Pick one and go and get it.'
                : 'Choose a goal to start saving, or add a new one.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Grows a value from nothing the first time it is built, and from wherever
/// it stood whenever it changes after that.
///
/// The bar used to be drawn at its final length before the page had finished
/// arriving, which is the difference between a page that reports a number and
/// a page that shows it moving.
class _Grow extends StatelessWidget {
  const _Grow({required this.value, required this.builder});

  final double value;
  final Widget Function(BuildContext, double) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// The progress bar.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.colour, this.track});

  final double value;
  final Color colour;

  /// The unfilled remainder — the page's own sunk tone unless the caller is
  /// the hero, which is not sitting on the page ground.
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: value,
      minHeight: 6,
      borderRadius: BorderRadius.circular(pill),
      color: colour,
      backgroundColor:
          track ?? Theme.of(context).colorScheme.surfaceContainerHighest,
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
    // A goal has no colour of its own. Categories and accounts do, because a
    // ledger row has to be told apart from the one above it at a glance; a
    // goal is a thing the whole app is pulling towards, and the brand's own
    // green is what that looks like.
    final colour = sproutDeepOf(context);
    final status = store.statusOf(goal);
    final percent = (status.progress * 100).round();

    return Semantics(
      button: true,
      label:
          '${goal.name}, ${goal.paused ? 'paused, ' : ''}'
          '${store.hideAmounts ? '' : '${rupees(status.saved)} of '
                    '${rupees(goal.targetMinor)}, '}'
          '$percent percent',
      excludeSemantics: true,
      child: TintCard(
        onTap: () => _showGoal(context, store, goal),
        // A funded goal takes the brand's own ground. It has stopped being one
        // of the things on the list and become the thing to act on.
        color: status.reached ? sproutSoftOf(context) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filled rather than tinted: this is the one glyph on the
                // card, and the deep green carries white — the same pairing
                // the FAB and the tab pill are drawn in.
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    iconFor(goal.icon),
                    size: 18,
                    color: onSproutDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Whole rupees: three exact figures wrap onto a second
                      // line on a narrow phone, and nobody saves for a trip to
                      // the paise.
                      Text(
                        '${store.show(rupeesWhole(status.saved))} of '
                        '${store.show(rupeesWhole(goal.targetMinor))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: monoStrut(11.5),
                        style: mono(11.5, color: scheme.secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // "Ready" rather than "100%": the number is the same either
                // way, and one of them tells you what to do about it. Paused
                // outranks both — the percentage is not going to move.
                // Ready is filled and the percentage is a wash of the same
                // green, so the two are told apart by weight rather than by
                // hue. Paused is neither — it is the one state with nothing
                // to be pleased about.
                _Pill(
                  goal.paused
                      ? 'PAUSED'
                      : status.reached
                      ? 'READY'
                      : '$percent%',
                  ground: goal.paused
                      ? scheme.surfaceContainerHighest
                      : status.reached
                      ? colour
                      : sproutSoftOf(context),
                  ink: goal.paused
                      ? scheme.secondary
                      : status.reached
                      ? onSproutDeep
                      : onSproutSoft(context),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronRight, size: 16, color: scheme.outline),
              ],
            ),
            const SizedBox(height: 12),
            _Grow(
              value: status.progress,
              builder: (context, t) => _Bar(value: t, colour: colour),
            ),
            const SizedBox(height: 8),
            Text(
              goal.paused
                  ? 'Paused · ${store.show(rupeesWhole(status.saved))} '
                        'still set aside'
                  : status.reached
                  ? 'Ready to spend'
                  : '${store.show(rupeesWhole(status.remaining))} to go',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: monoStrut(11.5),
              style: mono(
                11.5,
                // The ink the soft green ground carries: the deep tone on
                // cream, where the accent is barely darker than what it is
                // written on, and the accent at night, where the deep tone
                // disappears into the wash.
                color: status.reached && !goal.paused
                    ? onSproutSoft(context)
                    : scheme.secondary,
              ),
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
      return _confirmTakeOut(
        context,
        store,
        goal,
        asked.amount,
        asked.accountId,
      );
    case _Ask.put:
      // Null when there was no room left after all — nothing moved, so
      // nothing is celebrated.
      if (store.putAside(goal, asked.amount, asked.accountId) == null) return;
      // The bar grows on the way back to the page; this is the same moment,
      // felt rather than seen.
      HapticFeedback.mediumImpact();
  }

  final milestone = store.claimMilestone(goal);
  if (milestone == null || !context.mounted) return;

  await showPennyMoment(
    context,
    // Arms up and confetti for the finished goal — the one moment in a money
    // app that is unambiguously worth drawing. The ticked clipboard marks the
    // quarters along the way: progress noted, not the party.
    pose: milestone == 100 ? Penny.celebrate : Penny.complete,
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
  late String _accountId = widget.store.pickableAccounts().first.id;

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final status = store.statusOf(goal);
    final accounts = store.pickableAccounts();

    final account = store.accountById(_accountId);
    final balance = store.balanceOf(_accountId);
    final room = store.roomToPutAside(goal, _accountId);

    return SheetFrame(
      title: goal.name,
      children: [
        Text(
          // Paused first: Add is disabled below, and a button that will not
          // press has to say why on the same screen or it reads as broken.
          goal.paused
              ? '${store.show(rupeesWhole(status.saved))} in Goals, and paused '
                    '— resume it in Edit goal to put more in.'
              : status.reached
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
          // What the typed amount will actually do, before it does it. The two
          // ceilings read differently on purpose: the account is a wall — that
          // money is not there — while the goal's is a trim.
          trailing: _amount > balance
              ? _Warning(
                  '${account?.name ?? 'That account'} only has '
                  '${store.show(rupeesWhole(balance < 0 ? 0 : balance))}',
                  colour: scheme.error,
                )
              : _amount > status.remaining && status.remaining > 0
              ? _Warning(
                  '${store.show(rupeesWhole(status.remaining))} is all this '
                  'goal needs — only that much moves',
                  colour: scheme.secondary,
                )
              : null,
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
        // Withdraw sits left, Add right: the sheet's default action lands
        // under the thumb, and the two share one row instead of stacking.
        Row(
          children: [
            if (status.saved > 0) ...[
              Expanded(
                child: OutlinedButton(
                  // Capped at what the goal holds: it cannot hand back money
                  // that was never put in it.
                  onPressed: _amount <= 0 || _amount > status.saved
                      ? null
                      : () => Navigator.pop(context, (
                          ask: _Ask.take,
                          amount: _amount,
                          accountId: _accountId,
                        )),
                  child: const Text('Withdraw'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                // Never more than the account holds, and never into a goal
                // that is already funded. Overshooting the *target* is fine
                // and stays enabled: the store trims it to what is needed.
                onPressed: _amount <= 0 || _amount > balance || room <= 0
                    ? null
                    : () => Navigator.pop(context, (
                        ask: _Ask.put,
                        amount: _amount,
                        accountId: _accountId,
                      )),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
        if (status.reached) ...[
          const SizedBox(height: 10),
          // The coin at wash strength, with ink on it — the one pairing the
          // palette sanctions for this tone, and the right one here: buying
          // the thing is money leaving, which is what the coin has always
          // meant. Full width like everything else on the sheet, because it
          // is the point of a finished goal and not a footnote to it.
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: coinSoftOf(context),
            ),
            onPressed: () => Navigator.pop(context, (
              ask: _Ask.bought,
              amount: 0,
              accountId: _accountId,
            )),
            child: const Text('Bought it'),
          ),
        ],
        const SizedBox(height: 10),
        // The same 52-high full-width shape as Add, at wash strength
        // rather than filled: the two are the sheet's actions, and one of them
        // reading as a footnote made the sheet look like it had one.
        OutlinedButton(
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

/// A warning inside the amount field, which says why when it is pressed.
///
/// A tooltip rather than a line of text under the field: the reason is worth
/// one tap when the amount looks wrong and worth no space at all the rest of
/// the time.
class _Warning extends StatelessWidget {
  const _Warning(this.message, {required this.colour});

  final String message;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Icon(LucideIcons.triangleAlert, size: 18, color: colour),
    );
  }
}

/// Closing a goal by buying the thing.
///
/// The money is already sitting in the goals account, so the purchase is an
/// ordinary expense *out of* that account — the entry sheet opens with the
/// amount, the name and the account filled in. The goal closes only once that
/// row is actually in the ledger; the transfers that filled it stay, because
/// they happened.
///
/// The goal used to close before the sheet opened, on the grounds that losing
/// a goal is harmless next to losing money. It is not harmless: backing out of
/// the sheet left the money in Goals with nothing pointing at it, and the goal
/// had to be typed again from memory. Nothing is decided until the ledger says
/// something happened.
/// Taking money back out asks first.
///
/// Not because it is destructive — the transfer is an ordinary row and is
/// undoable like any other — but because it is the one action on the sheet
/// that undoes progress, and it sits a thumb's width from the button that
/// makes it. The dialog names the amount and where it lands, which is the part
/// a mis-tap gets wrong.
Future<void> _confirmTakeOut(
  BuildContext context,
  PennyStore store,
  Goal goal,
  int minor,
  String accountId,
) async {
  final into = store.accountById(accountId)?.name ?? 'the account';
  final go = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Withdraw from this goal?'),
      content: Text(
        '${store.show(rupees(minor))} moves out of ${goal.name} and into '
        '$into, as an ordinary transfer in the ledger.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Leave it'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Withdraw'),
        ),
      ],
    ),
  );
  if (go == true) store.takeOut(goal, minor, accountId);
}

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
        'The spend goes in the ledger next, out of Goals — the amount and the '
        'name are already filled in. ${goal.name} closes once you save it.',
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
  // What the ledger holds before the sheet opens. The sheet reports what it
  // deleted, not what it saved, and this is the whole question here: a row
  // arrived, or the sheet was backed out of. Nothing else adds a transaction
  // while a modal is up.
  final before = store.txns.length;
  await showEntrySheet(
    context,
    store,
    initialAmountMinor: saved,
    initialNote: goal.name,
    initialAccountId: vault,
  );
  if (store.txns.length > before) store.removeGoal(goal);
}

/// Add a goal, or edit [existing]. The same editor accounts and categories
/// use, with a target instead of an opening balance.
Future<void> _editGoal(BuildContext context, PennyStore store, Goal? existing) {
  final host = context;
  final name = TextEditingController(text: existing?.name ?? '');
  var target = existing?.targetMinor ?? 0;
  var icon = existing?.icon ?? 'piggy-bank';

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => EditSheet(
        title: existing == null ? 'New goal' : 'Edit goal',
        nameController: name,
        nameHint: 'A phone, a trip, a rainy day…',
        icon: icon,
        // No colour picker: goals are the brand's green, all of them.
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
        // What can happen to a goal that is not editing it: set it down, put
        // it away, or give up on it. All three live here rather than on the
        // contribute sheet, which is about money moving.
        //
        // Delete keeps the 52-high full-width shape as Save, filled with the
        // error colour at wash strength rather than at full: the entry sheet's
        // Delete pairs with its Save exactly this way, and a destructive
        // action should be findable, not the loudest thing on the sheet. The
        // two reversible actions sit above it, sharing a row, in plain ink —
        // nothing about pausing is destructive.
        footer: existing == null
            ? null
            : Builder(
                builder: (context) {
                  final scheme = Theme.of(context).colorScheme;
                  void set(GoalState state) {
                    store.setGoalState(existing, state);
                    Navigator.pop(context);
                  }

                  return Column(
                    children: [
                      if (existing.archived)
                        OutlinedButton.icon(
                          onPressed: () => set(GoalState.active),
                          icon: const Icon(
                            LucideIcons.archiveRestore,
                            size: 18,
                          ),
                          label: const Text('Restore goal'),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => set(
                                  existing.paused
                                      ? GoalState.active
                                      : GoalState.paused,
                                ),
                                icon: Icon(
                                  existing.paused
                                      ? LucideIcons.play
                                      : LucideIcons.pause,
                                  size: 18,
                                ),
                                label: Text(
                                  existing.paused ? 'Resume' : 'Pause',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => set(GoalState.archived),
                                icon: const Icon(LucideIcons.archive, size: 18),
                                label: const Text('Archive'),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _confirmDeleteGoal(host, store, existing);
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: scheme.error.withValues(alpha: 0.10),
                          foregroundColor: scheme.error,
                        ),
                        child: const Text('Delete goal'),
                      ),
                    ],
                  );
                },
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
                    ),
                  );
                } else {
                  existing
                    ..name = name.text.trim()
                    ..targetMinor = target
                    ..icon = icon;
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
        'goal goes. Take it out first if you want it somewhere else.',
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

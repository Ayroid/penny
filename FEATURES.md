# Penny — feature checklist

Working checklist for what's built, what's broken, and what's next. Tick a box
when it ships. Keep entries one line; the reasoning lives in the code comments.

**Status:** 20 source files · 12,101 lines · 297 tests · 14 goldens · 4 runtime deps
**Verified on:** Android device — runs, rupee and mono render, data survives a cold
kill. That was *before* Goals and the bottom dock, and before the deep-green
chrome and the rebuilt Insights; all four are covered by tests and goldens and
have not been on hardware yet
**Last release:** 0.3.0, in `releases/0.3.0/` and — for the first time —
published, at `github.com/Ayroid/penny/releases/tag/v0.3.0`, three APKs on the
tag. 0.1.0 was signed with the debug key, so nothing can update it; everything
since is cut from `android/penny-release.jks` and `apksigner` reports `CN=Penny`
**Current build:** arm64 **20.9 MB**, armeabi-v7a 18.2 MB, x86_64 22.4 MB
(`--split-per-abi --obfuscate --split-debug-info`, the flags `tool/release.sh`
uses). Measured at 0.3.0

**On build size:** ship `--split-per-abi` or the `.aab`, never the plain APK.
A fat `app-release.apk` carries all three ABIs and roughly doubles what anyone
downloads.

| Optimisation | Bought |
|---|---|
| Mascot poses downscaled 1254 → 512 px, palette-quantised | **5.29 MB** |
| Character sheet moved out of `assets/` into `art/` | ~1.4 MB |
| `--obfuscate --split-debug-info` (in `tool/release.sh`) | still not isolated — the 19.5 MB above includes it, but no plain build was made alongside to subtract |
| `lucide_icons_flutter` for ~250 icons | costs ~0.7 MB — see `lib/icons.dart` |
| Landscape art requantised — one 588 KB landing page became four skies, and `mountains.png` 494 → 133 KB | ~170 KB, and four times the art |

---

## Design decisions — settled, don't re-litigate

- **Money is an integer number of paise, never a double.** `0.1 + 0.2 != 0.3`,
  and a ledger that drifts by a paise per hundred entries is worse than no
  ledger. Nothing converts an amount to `double` — not to store it, total it,
  or draw it. Charts scale integers to pixels at the last moment, which is the
  only place a fraction is allowed to appear.

- **A typed amount is rupees, not paise.** `parseRupees` in `money.dart` is the
  one place a string becomes money. The keypad this replaced built paise-first,
  so `5·0·0` meant ₹5.00 — a field prefixed with `₹` cannot work that way.
  Length is checked *before* parsing, because `int.tryParse` gives up past 19
  digits and would make a long paste read as garbage rather than as "too big".

- **Transfers are a kind, not a category.** Without them, withdrawing cash from
  the bank reads as an expense and overstates the month by exactly the amount
  withdrawn. Every income and expense total excludes them; a transfer nets to
  zero across the ledger.

- **A realignment is a kind, not an expense.** After weeks of unlogged cash, the
  gap between the app and the wallet is not a purchase. `adjustUp` and
  `adjustDown` move the account balance and nothing else: every income, spend,
  breakdown and trend excludes them, as it does transfers. Two kinds rather
  than one signed amount, because an amount is never negative. Settings →
  Accounts → Realign balance asks what is actually there and writes the
  difference; a row can only be deleted, since there is nothing else to edit.

- **Days are `'YYYY-MM-DD'` strings, and day arithmetic goes through the
  `DateTime` constructor.** A `Duration` is 24 real hours and lands on the wrong
  calendar day across a DST change — which would drop or double a heatmap cell
  twice a year. Zero-padded, so lexical order is chronological order.

- **The clock is injected, in one place.** `lib/clock.dart` holds
  `DateTime Function() clock = DateTime.now`; `today()`, `greeting()` and
  `landingImage()` are its only callers, and production never reassigns it.
  Without it every golden that renders a date drifts as the calendar moves and
  the suite starts failing on its own. Wick had exactly this bug: 21 of its
  goldens were red and the failures read as noise.

- **Filled brand chrome is the deep sprout; the lit sprout stays the wash.**
  White on `#34B863` measures **2.57:1** and fails a 15px/700 button label. The
  first answer was to compute the ink and land on navy; the better one is to
  darken the fill. Everything filled — the tab pill, the segmented pill, the
  FAB, primary buttons, the Goals hero, the busiest heatmap cell — is
  `sproutDeep`, carrying white at 9.1:1. Everything *washed* — tints, credit
  figures, glyphs — stays the lit sprout, because a single dark accent turns
  those grey. Dark mode needs its own deep tone: `#10412F` on the near-black
  ground is 1.8:1 and the pill vanishes into it.

- **`onAccent` is still computed — for the 21 category swatches.** They are
  user-chosen and span the palette, so nothing may hardcode their ink.
  Asserted per swatch in `palette_test.dart`, and pinned to the widget in
  `a11y_test.dart` so the two cannot drift apart.

- **The coin carries no text.** Income is the sprout and expense the coin, and
  green-vs-orange is the classic deuteranope confusion pair, so the two must be
  separated by lightness. The tone far enough from the sprout is too dark for
  navy (4.24) and too light for white — no single value satisfies both. The coin
  gives up text and keeps the gap; amounts sit *beside* a bar.

- **A sprout bar cannot reach 3:1 on cream, and that is arithmetic.** Navy on
  the sprout needs luminance ≥ .2889; 3:1 against cream needs ≤ .2824. The
  window is empty by .0065. The button wins, and every bar carries its amount as
  text and sits against a labelled axis. Asserted as a bounded exception so it
  cannot drift silently. The heatmap used to be the second half of this
  exception — accent against a wash of itself topped out near 1.90 — and is not
  any more: the busy end of the ramp is drawn in the deep tone and measures 6:1.

- **Colours are stored as palette indexes, icons as string keys.** So the
  palette can be retuned and the icon package upgraded without rewriting saved
  data. Out-of-range indexes clamp — a hand-edited export must not crash.

- **Migrations are defensive reads inside `fromJson`,** not a version chain.
  `_repair()` adopts orphaned rows rather than dropping them, because losing a
  row loses money. A transfer with a dangling destination degrades to an
  expense — left alone it would move money out of the ledger entirely.

- **A dangling *shortcut* is dropped, not adopted.** The one exception to the
  rule above: adopting it would spend from the wrong account on a single tap,
  and a shortcut is a convenience rather than a record worth rescuing.

- **Shortcuts are curated, never inferred.** Guessing them from history looked
  helpful and behaved badly: two entries differing only by account render as
  identical chips, and something entered twice by accident outranked the thing
  worth a shortcut.

- **Ids are monotonic, not bare timestamps.** Recurring rows are materialised in
  a tight loop where two calls land in the same microsecond.

- **Monthly recurrence counts from the start day, never from the last run.**
  Computing March from a February clamped to the 28th would pin the rule to the
  28th forever.

- **The bottom of the screen is a dock: the pill, and the add button.** The
  add button used to be a filled disc in the top bar of every page. It is now a
  `FloatingActionButton` at the bottom right, where the thumb is and where Wick
  keeps its own — one per page, adding the thing that page is about. The pill
  centres itself in what is *left* of the width rather than in all of it:
  centred on the screen a three-tab pill reaches ~232 and the button starts at
  284, so the two would overlap on a narrow phone.

- **`endFloat` already lands on the pill's line, and a test can hide that.**
  A floating FAB's margin is measured from `minViewPadding`, so on a device
  with a gesture strip it sits exactly where the pill's `SafeArea` puts the
  pill. A custom location "fixing" this was written and thrown away: the only
  thing wrong was the harness. `tester.view.padding` alone leaves `viewPadding`
  at zero, which the pill reads but the FAB does not — set **both**, or the
  golden shows a button 48px below where it lands on a phone.

- **Insights is a page you open, not a tab you swipe to.** It is where you go
  with a question; the ledger and the goals are where you go to do something.
  It sits next to Settings in the bar of every tab, which is also what made
  room for a fourth destination without a fourth tab — and a question does not
  wait until you have swiped back to the overview to be asked.

- **No scrollbars.** Flutter draws one beside every scroll view on a desktop
  platform. Penny is a phone app whose longest list is an icon grid; the
  `scrollBehavior` on the `MaterialApp` turns them off everywhere, and nothing
  about the scrolling changes.

- **An undo lives in a snackbar above the tab pill, and leaves on its own.**
  The pill is a `Stack` overlay, so the `Scaffold` laying a floating snackbar
  out does not know it is there and puts the bar underneath it. On top of that,
  `SnackBar.persist` defaults to `action != null` — a bar with UNDO on it
  ignores its own `duration` and waits to be dismissed by a hand that cannot
  reach it. Both are why the toasts were pulled the first time. `showUndoBar`
  in `page_bar.dart` is the only place either is decided, and `undo_test.dart`
  measures the bar against the pill rather than trusting a golden, which the
  pill paints over.

- **A contribution says when, like every other row.** It was always dated
  today, on the grounds that money set aside is set aside now — which is true
  right up until someone catches up a month of saving in one sitting and gets
  four rows all stamped with the day they remembered. The goal itself never
  cared: `statusOf` counts by tag, not by date. The ledger did, because the
  ledger is the record of *when*. So the sheet carries the same day pill the
  entry sheet does, and `dayLabel` and `pickDay` moved into `sheets.dart` so
  the two cannot disagree about what to call a day or how far back to allow.
  The ceiling is still measured against what the account holds *now* — the one
  balance this app computes — because backdating a row does not backdate the
  money.

- **Putting money aside moves it, and the ledger records that.** Goals shipped
  first as an earmark — a `savedMinor` on the goal, no transaction — on the
  grounds that a jar in the real world is not a ledger entry. That was wrong in
  practice: the account you spend from still showed the money as available, so
  the promise had no teeth. A contribution is now an ordinary **transfer** out
  of the account it came from and into a **Goals** account, tagged with
  `Txn.goalId`. The source account is genuinely lighter, the total balance does
  not move (a transfer nets to zero), and the row is in the ledger to find,
  edit and delete like any other.

- **The page says when its own figures disagree.** Two sums come off the same
  rows: what the goals claim, and what the goals account holds. They can only
  come apart in one direction — money leaving that account without the goal
  counting it, which nothing in the app offers any more but an imported backup
  can still carry in, because dropping a row on import loses money. `statusOf`
  floors each goal at zero so the page keeps drawing, and `goalsShortfall` is
  what says the drawing is wrong: a line above the goals naming the gap, in the
  coin's wash rather than in red, with no button on it — the app cannot know
  which of the two figures is the one to keep. A balance *larger* than the
  claims is not reported: deleting a goal leaves its money behind on purpose.

- **A goal holds no number of its own.** What is in it is summed from those
  transfers by `statusOf` — into the goals account counts up, out of it counts
  down. Two places for one figure is two places to disagree: delete a
  contribution in the ledger and the goal is simply smaller, with nothing to
  reconcile. Same reasoning as `balanceOf`, and the same ponytail note about
  caching if a very long ledger ever stutters.

- **The Goals account is made on first use, never seeded.** An empty "Goals"
  chip on a fresh ledger answers a question nobody asked. It is an ordinary
  account otherwise — it has a balance, appears on the overview, and is where
  "Bought it" spends from — marked only by `Account.forGoals`, which is how the
  app finds it again after someone renames it.

- **Deleting a goal does not move money.** The transfers stay, the money stays
  in Goals, and the dialog says so. Guessing which account it should go back to
  would be inventing a transaction nobody asked for; "Withdraw" is
  right there for the person who wants it elsewhere.

- **A moment is claimed once ever, not once a day.** `claimMoment` was built
  as a daily guard and its only real caller is goal milestones, which are
  crossed once. `claimMilestone` claims every milestone at or below where a
  goal stands and returns only the highest new one, so nothing to full in one
  contribution celebrates once — and taking money back out and putting it in
  again does not replay it.

- **Deleting asks *and* offers an undo.** The dialog stops a mis-tap on the
  wrong row and carries the amount for that reason; the four-second undo
  catches the mistake you only see once the row is gone. `insertTxnAt` puts it
  back at its index rather than appending, because the ledger sorts by day and
  then by entry order.

- **Hiding covers every screen, and the row decides for itself.** `TxnRow`
  reads `store.hideAmounts` rather than taking a parameter — the ledger used
  to pass nothing, so "hide amounts" masked the overview and left every figure
  one swipe away. `store.show(...)` is the one place a figure becomes a mask.

- **One sheet kit, in `sheets.dart`.** The frame, the list with its add button,
  the row, the name/colour/icon editor, the chip and the amount field started
  out private to `settings.dart`. Goals needed the same five things, and a
  second copy is how two editors drift into disagreeing about what "Save" does.
  The amount field echoes nothing back under itself either — the figure is
  already in the field, with the ₹ in front of it.

- **Nothing scolds.** Red is for destructive confirmation, never for spending:
  a month that ended down is ordinary, and there is no disappointed mascot
  pose, deliberately. The calendar was briefly the exception — green up, red
  down, colour standing in for the sign — and it is not any more: a day's
  figure is written in whichever neutral ink survives the cell it sits on, and
  a minus sign carries the direction. Red-versus-green is the classic
  confusion pair, and a sign is not a hue.

- **Holding a row *offers* to copy it to today; the Copy button does it.** A
  hold is easy to do by accident on a list that scrolls, so the gesture opens a
  sheet carrying the amount, what it was and where it came from — the same
  three strings the row itself is drawn from, so the two cannot describe it
  differently — and nothing is written until Copy is pressed. The undo bar
  stays behind it: the sheet catches the accidental hold, the undo catches the
  deliberate press on the wrong row.

- **The copy is yesterday's chai, dated today.** The cheapest entry shortcut
  left, and it is built into `TxnRow` rather than passed in at each call site,
  because it has to be the same gesture in the ledger, on the overview and in
  the sheet Insights opens — three call sites is three chances to leave one
  out. The copy carries
  neither `ruleId` nor `goalId`: it was not materialised from a rule, and it is
  not money a goal counted. A goal's own row refuses and says where to go
  instead — copying one would move money into the goals account past the two
  ceilings `putAside` applies, which is the hand-made transfer the pickers
  stopped offering.

- **CSV is an export, not a backup.** JSON is the backup and the only thing
  `importJson` reads; the spreadsheet goes out and does not come back. So it is
  written for the reader on the other end: oldest first, names instead of ids,
  every cell quoted with its own quotes doubled, and amounts as plain decimal
  rupees — `₹1,20,450.00` is a *string* in every spreadsheet there is. The sign
  is the kind's, so a column of amounts totals to something meaningful, and a
  transfer is `0.00` there with its own figure in a column of its own: it moved
  money without spending or earning it.

- **The calendar is one grid, and the figures land inside it.** Shading
  answers "how much" and never "which way", which is the question a day with a
  salary in it is actually asking; the button writes each day's net into the
  cells that are already there rather than swapping the grid for a second one.
  It used to be two readings on a switch — the same seven columns over the same
  days, drawn twice — which made a tap look like a change of subject and gave
  the leading blanks a second place to be wrong. Shading alone stays the
  default: it is the picture you can read without reading.

  The ink is measured per cell, because the ramp runs from a pale wash to a
  solid green and no one ink survives both ends — and measured against what the
  cell is *painted*, card and page resolved underneath, since every tone on the
  ramp is the accent at an alpha and a translucent green otherwise measures as
  the full-strength one it was mixed from. Black and white rather than the
  brand's navy: navy loses the middle of the ramp at 3.8:1, and a figure in a
  cell is the reading rather than furniture. That is also why the direction is
  a minus sign — an ink chosen for contrast cannot also mean a direction — and
  the sign survives hiding as a bare `-••`, because a direction is not an
  amount. The semantics label carries the figure signed whatever is on screen.

- **Today is ringed; tapping a day holds it.** The ring is the cell's own ink,
  so it survives both ends of the ramp, and every other cell carries a
  transparent one so the grid does not shift by a pixel as it moves. Tapping a
  day puts that day's rows below the calendar in place of the period's last
  few — all of them, since a day is a short list by nature — and tapping the
  same cell again lets it go, which has to be the way back because the ring is
  the only thing saying a day is held. Moving the period or the arrows drops
  the held day: a day picked in March has nothing to say about April, and rows
  from outside the period on screen are worse than losing a selection.

- **Insights reads a window, and the window is the page's state.** It opened
  on today and could only look at today, which made it a summary rather than a
  tool. It now holds an anchor: arrows step it, a horizontal fling steps it,
  and tapping a bar jumps to the period that bar stands for. Switching Day /
  Week / Month keeps the anchor, so stepping back three months and asking for
  the week lands in that month rather than back at the present.

- **The overview and Insights step through the same windows, from one widget.**
  `PeriodNav` in `page_bar.dart` owns the label, the arrows and the
  "not entirely in the future" rule. Two copies is how two pages end up
  disagreeing about where a week starts.

- **A share bar is the same fraction as the figure beside it.** Bars used to
  be drawn against the largest row, which reads as a share of the whole and is
  not one: the top category always filled the bar, whether it was 90% of the
  month or 12%. They are drawn against the list's total now, so a long tail
  looks like a long tail.

- **An axis label is `₹1.2L`, not `₹1,20,450`.** `compactRupees` rounds to one
  decimal in Indian scale words for the same reason `groupIndian` exists: a
  chart that says ₹120K beside a ledger that says ₹1,20,450 is two apps. The
  axis maximum is rounded up to a 1, 2 or 5 at its own magnitude, so the chart
  tops out at ₹80K rather than at whatever the busiest week happened to be.

- **A card holds its height and its boxes, whatever the figures are.** Three
  layouts used to break on a big number: the balance wrapped to a second line,
  an account pill grew and pushed its neighbour out of the row, and a ledger
  row with a crore in it overflowed outright. All three are the same fix — a
  stated box with `FittedBox` inside it, so a large figure shrinks rather than
  pushing. The "set aside · free" line is drawn even when it is empty, so the
  card is one height with goals and without.

- **The card holds four account tiles, and which four is a choice.** A phone
  fits four across at the width a tile is drawn; a fifth wraps and pushes the
  card past the height the rest of the overview is laid out around. So accounts
  are pinned to the card from their own editor in settings, capped at four, and
  the button says "4 pinned already" when it is full rather than failing
  quietly on the tap. Nothing pinned means the app picks the first four — which
  is what the card did before, and what a fresh ledger with three seeded
  accounts wants. Pin one and the choice is yours entirely: there is no "these
  four plus mine", because a card that adds accounts you did not ask for is the
  thing pinning exists to stop. In the list the four take the brand's soft
  green ground — the same wash a funded goal's card takes — rather than a pin
  glyph beside the name: being on the card is a property of the row, and four
  coloured bands are found faster than four small icons among ten.

- **The goals account is not a pickable account.** Money gets into it by
  putting some aside, and out of it by withdrawing or by buying the thing —
  every route goes through a goal, which then knows about it. An ordinary
  expense entered against it spends what a goal has already spoken for, and the
  goals go on claiming money the account no longer holds. So it is off the
  entry sheet's picker, off the recurring-rule and quick-entry editors, and off
  the goal contribution sheet's own chips: one `pickableAccounts` on the store,
  which every picker in the app now reads. It stays visible on the sheet that
  is already sitting on it — the prefilled "Bought it" spend, a contribution
  opened from the ledger — because a picker that cannot show the current value
  is a picker that silently changes it.

- **The sky behind the balance moves with the clock, like the greeting.** Four
  cuts of the same range — sunrise, full sun, dusk, a moon — chosen by
  `landingImage()` on the same hour boundaries `greeting()` reads, and pinned
  to those boundaries in `palette_test.dart` so a card cannot say good evening
  under a midday sun. It sits on the card's bottom edge, because that is where
  a horizon goes, and it runs *behind* the account tiles rather than stopping
  at them — which is why a tile's ground is its own colour darkened, not a pale
  wash a mountain shows through. It is faded out at the *top*, not at the left
  as it first was: the left fade was for tiles that carry their own ground now,
  and it left a moon sitting behind "₹21,094 free" — a figure read against
  whatever the sky happened to be doing there, which no contrast rule can
  cover. The art is 137 logical tall against a card of about 173, so the ramp
  runs from 0.42 to 0.64 of the picture: clear through the balance and the line
  under it, at full strength by the time the tiles start. The cost is the moon
  and the sun, which sit high in the drawing; moving them down the 960×410
  canvas would bring them back.

- **In a `Stack`, the one painted last is the one a tap lands on.** The eye was
  pinned to the balance card's corner and put in the stack before the balance
  line, which runs under that corner: it was drawn correctly, looked right in
  every golden, and could not be tapped at all.

- **The eye lives on the overview, and only there.** It was listed as a gap —
  masked on the ledger means swiping back to unmask — and it is not one. The
  switch belongs to the balance card it hides, the way a light switch belongs
  to the room. Insights and Settings moved into every tab's bar because they
  are destinations; a toggle is not.

- **Insights and the overview keep separate windows.** Both step through
  periods with the same `PeriodNav`, and each holds its own anchor on purpose:
  Insights is where you go to read back through past months, while the overview
  is where this month — or whichever month you left it on — is being kept. One
  shared anchor means reading March in Insights quietly moves the page you
  come back to.

- **A goal has no colour of its own.** Categories and accounts do, because a
  ledger row has to be told from the one above it at a glance. A goal is a
  thing the whole app is pulling towards, so it is drawn in the brand's green
  wherever it appears: a filled deep-sprout tile with a white glyph, the same
  pairing as the FAB and the tab pill. The editor drops the swatches with it —
  a picker nobody was choosing between. `EditSheet` hides that block when it is
  handed no `onColour`, rather than growing a second flag that says the same
  thing, and `Goal.color` is gone from the model; an older file's `color` is
  simply read past.

- **The green that carries a figure is not the accent.** `sproutInk` is the
  deep tone on cream and the lit sprout at night, and it is what a goal's
  percentage pill and the line under a finished goal's bar are drawn in. The
  accent itself measures 2.2:1 on the sunk fill and 2.6:1 on its own soft wash
  — either would fail a small bold label — while the deep tone clears 7.9 and
  8.2, and at night the pair inverts. The calendar takes neither: its figures
  sit on the heatmap's own green, so `palette_test.dart` walks the ramp in both
  themes and asserts the neutral pair clears 4.5 at every step — and that navy
  does not, so the one place the brand ink is swapped out stays a decision
  rather than an oversight.

- **A goal is active, paused or archived — one field, three states.** Pausing
  stops money going in and says so on the card; archiving takes it off the page
  entirely. Neither moves a paise: what is set aside is in the goals account,
  and only a transfer takes it out again. Stored as one `GoalState` rather than
  two booleans, because paused-and-archived is not a thing and a pair of flags
  is a pair that can say it. The pause is enforced in `putAside`, not only on
  the button — one guard where every caller routes through.

- **The archive is a door, not a fourth filter chip.** `Segmented` says three
  options is where a pill stops being a pill, and the archive is not a view of
  the same list: it is a room you go into. A row under the add button opens the
  sheet kit's own list, dimmed exactly as archived accounts and categories are
  in settings. It stays open when it empties rather than dismissing itself: the
  editor opens over it, and a pop racing that one pops whichever route happens
  to be on top.

- **Nothing is decided until the ledger says something happened.** "Bought it"
  used to close the goal and *then* open the entry sheet, on the grounds that
  losing a goal is harmless next to losing money. Backing out of that sheet
  left the money sitting in Goals with nothing pointing at it and a goal to
  re-type from memory. The goal now closes only once the row is actually in.

- **The mask is a fixed six dots.** One dot per digit would give away the order
  of magnitude, which is most of what hiding the balance was for. Every place
  that swaps between digits and the mask carries `forceStrutHeight`, because
  `•` is not in the platform mono and a fallback font's metrics would move the
  whole screen.

- **One file cannot serve both launcher platforms.** Android guarantees only the
  centre 2/3 of an adaptive foreground survives the mask; iOS shows the whole
  square. `image_path` and `adaptive_icon_foreground` point at different files.

- **Trimming art is thresholded at `alpha > 8`.** `Image.getbbox()` trims on
  `alpha > 0`, and the source carries near-invisible noise at the canvas edge —
  it centred a box that was not there.

---

## Shipped

### Foundations
- [x] Local-only storage, one JSON blob, fire-and-forget saves
- [x] `PennyStore` / `ListenableBuilder`, no state package
- [x] String day keys + DST-proof arithmetic
- [x] Injected clock (`lib/clock.dart`) so dates are testable
- [x] Corrupt-blob tolerance — starts empty, doesn't crash
- [x] Orphaned rows adopted, not dropped; dangling transfers degrade safely
- [x] Once-ever guard (`claimMoment`, persisted), called by goal milestones
- [x] Three platform targets (android, ios, linux)

### Brand & mascot
- [x] Penny palette + light/dark, sprout `#34B863` on cream `#FFF8F1`
- [x] Plus Jakarta Sans bundled (variable, offline)
- [x] Six mascot poses, sheet names mapped to the family's pose vocabulary
- [x] `CoinMark` — drawn coin-and-sprout, fallback and splash mark
- [x] `tool/make_icon.py` — both launcher framings, splash mark, pose downscale
- [x] Adaptive icon oversized 1.21× past the guaranteed box, deliberately
- [x] Android 12+ splash (`values-v31`), cream in both themes

### Shell
- [x] Three swipeable pages under a floating tab pill
- [x] Insights and Settings in every tab's bar, opened from wherever you are
- [x] Add button at the bottom right, on the pill's line, one per page
- [x] Tab pill tracks the swipe fraction, not just the settled page
- [x] Tab pill sits above the system gesture strip, not inside it
- [x] Splash gate → onboarding or shell
- [x] Recurring rules catch up on launch and on resume

### Overview
- [x] Total balance, scaled down rather than wrapped when it is large
- [x] Up to four pinned account tiles across the card's bottom edge
- [x] Pinned from the account's own editor, capped; pinned rows take the
      brand's soft green ground in the list
- [x] A landscape behind the balance, at the hour it actually is
- [x] Eye toggle — masks every amount in the app, persisted
- [x] Quick entries, held out of the add button — drag onto one and let go, or
      tap it once the row is up; adds dated today
- [x] Undoable for four seconds, from a bar that clears the pill
- [x] Day / Week / Month segmented, pill slides between positions
- [x] Period arrows, forward disabled at the present
- [x] Credit / debit / net meter on one line
- [x] Spend grid — a calendar for the month, one row for the week
- [x] The same calendar with each day's net written into it — a minus sign for
      a debit, ink measured against the shade under it
- [x] Today ringed in the grid; tapping a day puts its rows below the calendar
- [x] Recent rows grouped under day headers
- [x] Empty state leads with the action, not with three zero cards

- [x] Realign an account to what it actually holds, from its edit sheet
- [x] Realignments move the balance, never the spend or income totals

### Goals
- [x] A page of what you are saving for, target and progress each
- [x] Putting money aside is a real transfer, out of the account you pick
- [x] A Goals account, made on first use, holding what has been put aside
- [x] Taking it back out picks a destination, and is capped at what is in there
- [x] Both carry a date, so a month of saving can be caught up in one sitting
- [x] Progress summed from the ledger, so deleting a row shrinks the goal
- [x] Milestones at 25/50/75/100% — `showPennyMoment`, claimed once ever
- [x] "Bought it" spends out of Goals, prefilled — and closes the goal only
      once that row is saved, so backing out costs nothing
- [x] Goal cards in the brand's green — filled tile, white glyph, no palette
- [x] Pause a goal — it keeps what it holds and takes nothing more
- [x] Archive a goal — off the page, still in the file, one tap back
- [x] Archived goals behind a row under the add button, restored from the editor
- [x] Set aside and free, under the balance on the overview
- [x] Nothing else can spend the Goals account — it is off every picker
- [x] And when a backup says otherwise, the page names the gap instead of
      quietly drawing a figure it knows is wrong
- [x] Goals ride the backup like everything else

### Ledger
- [x] Every transaction, newest first, grouped by day
- [x] Day net per header, running balance per row
- [x] Search across notes, categories, accounts, amounts
- [x] All / Debit / Credit filter

### Insights
- [x] Opened from any tab's bar, with a back arrow rather than a tab
- [x] Day / Week / Month, and the window it reads is steppable — arrows, a
      horizontal swipe, or a tap on any bar in the chart
- [x] Credit-and-debit trend, 6 periods (7 days), against a labelled axis
- [x] Axis in Indian scale words, rounded up to a 1, 2 or 5
- [x] Both figures at one size — what came in and what went out, one question
- [x] A comparison card that reports both directions against the period before
- [x] A breakdown per side of the ledger, top five and a "See all"
- [x] Share bars are a fraction of the list, not of the largest row
- [x] Tap a category, or the footer, for that period's transactions in a sheet

### Add & edit
- [x] Platform numeric keyboard, autofocused, decimal input formatter
- [x] Spent / Earned / Moved, with the destination account for transfers
- [x] Category, account, date pills; native date picker
- [x] Hold any row, anywhere, to enter it again dated today — a sheet asks
      first, and the copy is undoable for four seconds after it
- [x] Save-for-quick-add toggle, reflecting what is already saved
- [x] Delete matches Save's shape and asks first, with the amount in the question
- [x] And then offers UNDO for four seconds, back at the row's own place

### Settings
- [x] Light / Dark / System
- [x] Accounts, categories, recurring rules and quick entries as sheets
- [x] Recurring rules edited in place, not stopped and rebuilt
- [x] Quick entries listed, edited and removed — the rule editor without a schedule
- [x] Archive rather than delete for accounts and categories
- [x] Colour and icon pickers
- [x] Export a backup (JSON, shared as a file)
- [x] Import a backup — confirmed first, decoded as UTF-8, dialog on failure
- [x] Export a spreadsheet — CSV, oldest first, quoted, plain decimal amounts
- [x] Onboarding — replay the same three screens, and the seed behind them
      stays the no-op it already was

### Release
- [x] `key.properties` + a 4096-bit keystore; release builds are properly signed
- [x] `tool/release.sh` refuses to build without one, rather than shipping debug keys

### Money
- [x] Integer paise throughout
- [x] Indian lakh/crore grouping (`₹1,20,450.00`)
- [x] `parseRupees` — commas, partial decimals, truncation, overflow clamping
- [x] `compactRupees` — `₹80K`, `₹1.2L`, `₹3.4Cr` for an axis, still integer paise

### First run
- [x] Three onboarding pages
- [x] Seeded accounts (Cash · Bank · Wallet) and 18 categories
- [x] Untouched seeded defaults renamed on migration; renamed ones left alone

### Accessibility
- [x] Every icon-only control has a tooltip *and* a semantics label
- [x] 48px tap-target floor, asserted for both platform guidelines
- [x] Rows announce as one thing, not five
- [x] Contrast asserted per swatch, per theme, analytically
- [x] Colour never the only signal — direction, weight and labels carry it too

---

## Known gaps — fix before new features

None right now. The last one went when a contribution learned to carry a date;
before that, the Goals account stopped being spendable and the page learned to
say so when a backup claims otherwise. New ones belong here rather than in the
backlog: a gap is something that is wrong, not something that is missing.

## Backlog

### Next up
All three that were here have shipped — hold a row to copy it, the spreadsheet
export, and the calendar of daily nets. What is below is what is left, still in
rough order of what it buys against what it costs.

### Small — an afternoon, no new dependencies
- Month-over-month per category — "Food is ₹1,800 more than last month"
- Sticky day headers in the ledger
- Financial-year (Apr–Mar) as a fourth period
- Reorder pinned shortcuts by drag
- Archived accounts and categories in their own section rather than dimmed

### Medium — days each
- **Budgets.** Per category, per month. Over budget **dims** and says "₹1,200
  over" in ink — never red, never a warning icon. The most-requested money-app
  feature and the easiest one to get wrong.
- **Bill reminders.** `flutter_local_notifications`; Wick's `reminders.dart`
  ports almost wholesale — schedule 7 ahead, rebuild idempotently, no isolate.
- **Split a transaction.** Do it before there is a lot of data, or not at all.
- **App lock.** `local_auth`. Money is the category where people expect it.

### Large — changes what the product is
- **Investments.** `Holding` (equity/MF/FD/gold), net worth = accounts +
  holdings, absolute and XIRR return. **AMFI publishes a free daily NAV file**
  for every Indian mutual fund scheme — no key, no terms problem — so MF
  valuations can update themselves. Equities stay manual.
- **Home-screen widget.** Today's spend plus a `+` that deep-links into the
  entry sheet. The highest-leverage way to cut entry friction, and friction is
  why people stop tracking.
- **Split-with-friends ledger.** A lightweight IOU that settles into a real
  transaction.

### Deliberately not building
- Cloud sync or accounts — "local, quiet, no account". Backup is a file.
- Bank aggregators (Plaid / AA) — needs a server and someone else's uptime.
- **UPI / SMS auto-import.** Needs SMS permission, breaks the no-permissions
  principle, is a Play policy minefield, and bank formats change constantly.
  Good quick-add gets 90% of the benefit at 5% of the cost.
- Gamification — Wick owns streaks; copying them makes two apps that feel the
  same rather than siblings.
- Red overspending states — see *nothing scolds*.
- Multi-currency conversion — rates need a source and an as-of date on every row.

---

## Commands

```sh
flutter run                       # debug
flutter test                      # 251 unit, widget and golden tests
flutter test --update-goldens     # only when a pixel change is deliberate
flutter analyze
python3 tool/make_icon.py         # after changing anything in art/
dart run flutter_launcher_icons   # after the above
tool/release.sh                   # split-per-abi APKs into releases/, signed
# A new machine needs its own keystore before that will run:
# keytool -genkey -v -keystore android/penny-release.jks -keyalg RSA \
#   -keysize 4096 -validity 10000 -alias penny
# then android/key.properties with storePassword / keyPassword / keyAlias /
# storeFile=penny-release.jks. Both files are gitignored; back up the .jks —
# lose it and no future build can update an installed Penny.
```

Source art lives in `art/` and is never bundled; everything in `assets/icon/`,
`assets/splash/` and `assets/mascot/` is generated. Keep `app_icon.png` RGB or
RGBA, **never palette-mode**: the generator throws `RangeError` on an indexed
PNG, and only on the iOS step, so Android looks like it worked.

The original plan — and the record of where it was wrong — lives in the git
history of `PLAN.md`, removed once this file replaced it. `git log --follow --
PLAN.md` if you want to read what was expected against what shipped.

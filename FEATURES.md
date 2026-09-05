# Penny — feature checklist

Working checklist for what's built, what's broken, and what's next. Tick a box
when it ships. Keep entries one line; the reasoning lives in the code comments.

**Status:** 19 source files · 7,177 lines · 234 tests · 13 goldens · 4 runtime deps
**Verified on:** Android device — runs, rupee and mono render, data survives a cold
kill. That was *before* Goals and the bottom dock; those two are covered by tests
and goldens and have not been on hardware yet
**Last release:** none yet, but release builds are signed — `android/penny-release.jks`
exists and `apksigner` reports `CN=Penny`, not the debug key
**Current build:** arm64 **19.5 MB**, armeabi-v7a 16.7 MB, x86_64 21.0 MB
(`--split-per-abi --obfuscate --split-debug-info`, the flags `tool/release.sh` uses)

**On build size:** ship `--split-per-abi` or the `.aab`, never the plain APK.
A fat `app-release.apk` carries all three ABIs and roughly doubles what anyone
downloads.

| Optimisation | Bought |
|---|---|
| Mascot poses downscaled 1254 → 512 px, palette-quantised | **5.29 MB** |
| Character sheet moved out of `assets/` into `art/` | ~1.4 MB |
| `--obfuscate --split-debug-info` (in `tool/release.sh`) | still not isolated — the 19.5 MB above includes it, but no plain build was made alongside to subtract |
| `lucide_icons_flutter` for ~120 icons | costs ~0.7 MB — see `lib/icons.dart` |

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

- **Days are `'YYYY-MM-DD'` strings, and day arithmetic goes through the
  `DateTime` constructor.** A `Duration` is 24 real hours and lands on the wrong
  calendar day across a DST change — which would drop or double a heatmap cell
  twice a year. Zero-padded, so lexical order is chronological order.

- **The clock is injected, in one place.** `lib/clock.dart` holds
  `DateTime Function() clock = DateTime.now`; `today()` and `greeting()` are its
  only callers, and production never reassigns it. Without it every golden that
  renders a date drifts as the calendar moves and the suite starts failing on
  its own. Wick had exactly this bug: 21 of its goldens were red and the
  failures read as noise.

- **`onAccent` is computed, never assumed.** White on the sprout measures
  **2.57:1** and fails a 15px/700 button label; navy is 5.43. Asserted per
  theme in `palette_test.dart`, and pinned to the widget in `a11y_test.dart` so
  the two cannot drift apart.

- **The coin carries no text.** Income is the sprout and expense the coin, and
  green-vs-orange is the classic deuteranope confusion pair, so the two must be
  separated by lightness. The tone far enough from the sprout is too dark for
  navy (4.24) and too light for white — no single value satisfies both. The coin
  gives up text and keeps the gap; amounts sit *beside* a bar.

- **A sprout bar cannot reach 3:1 on cream, and that is arithmetic.** Navy on
  the sprout needs luminance ≥ .2889; 3:1 against cream needs ≤ .2824. The
  window is empty by .0065. The button wins, and every bar carries its amount as
  text. Asserted as a bounded exception so it cannot drift silently.

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
  It sits next to Settings in the overview's bar, which is also what made room
  for a fourth destination without a fourth tab.

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

- **Putting money aside moves it, and the ledger records that.** Goals shipped
  first as an earmark — a `savedMinor` on the goal, no transaction — on the
  grounds that a jar in the real world is not a ledger entry. That was wrong in
  practice: the account you spend from still showed the money as available, so
  the promise had no teeth. A contribution is now an ordinary **transfer** out
  of the account it came from and into a **Goals** account, tagged with
  `Txn.goalId`. The source account is genuinely lighter, the total balance does
  not move (a transfer nets to zero), and the row is in the ledger to find,
  edit and delete like any other.

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

- **Nothing scolds.** Red is for destructive confirmation only, never for
  spending. A month that ended down is ordinary. There is no disappointed
  mascot pose, deliberately.

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
- [x] Three swipeable pages under a floating tab pill, Insights opened from the bar
- [x] Add button at the bottom right, on the pill's line, one per page
- [x] Tab pill tracks the swipe fraction, not just the settled page
- [x] Tab pill sits above the system gesture strip, not inside it
- [x] Splash gate → onboarding or shell
- [x] Recurring rules catch up on launch and on resume

### Overview
- [x] Total balance + per-account chips
- [x] Eye toggle — masks every amount in the app, persisted
- [x] Quick entries, held out of the add button — drag onto one and let go, or
      tap it once the row is up; adds dated today
- [x] Undoable for four seconds, from a bar that clears the pill
- [x] Day / Week / Month segmented, pill slides between positions
- [x] Period arrows, forward disabled at the present
- [x] Credit / debit / net meter on one line
- [x] Spend grid — a calendar for the month, one row for the week
- [x] Recent rows grouped under day headers
- [x] Empty state leads with the action, not with three zero cards

### Goals
- [x] A page of what you are saving for, target and progress each
- [x] Putting money aside is a real transfer, out of the account you pick
- [x] A Goals account, made on first use, holding what has been put aside
- [x] Taking it back out picks a destination, and is capped at what is in there
- [x] Progress summed from the ledger, so deleting a row shrinks the goal
- [x] Milestones at 25/50/75/100% — `showPennyMoment`, claimed once ever
- [x] "Bought it" closes the goal and spends out of Goals, prefilled
- [x] Set aside and free, under the balance on the overview
- [x] Goals ride the backup like everything else

### Ledger
- [x] Every transaction, newest first, grouped by day
- [x] Day net per header, running balance per row
- [x] Search across notes, categories, accounts, amounts
- [x] All / Debit / Credit filter

### Insights
- [x] Opened from the overview's bar, with a back arrow rather than a tab
- [x] Credit-and-debit trend, 6 periods, with a colour key
- [x] Category breakdown with share bars, largest first
- [x] "₹X more than last month", silent when there is nothing to compare

### Add & edit
- [x] Platform numeric keyboard, autofocused, decimal input formatter
- [x] Spent / Earned / Moved, with the destination account for transfers
- [x] Category, account, date pills; native date picker
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

### Release
- [x] `key.properties` + a 4096-bit keystore; release builds are properly signed
- [x] `tool/release.sh` refuses to build without one, rather than shipping debug keys

### Money
- [x] Integer paise throughout
- [x] Indian lakh/crore grouping (`₹1,20,450.00`)
- [x] `parseRupees` — commas, partial decimals, truncation, overflow clamping

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

- **The eye lives only on the overview.** Hiding now covers every screen, but
  the one switch that turns it off is on the first tab — masked on the ledger
  means swiping back to unmask. A second eye in the ledger's bar, or a row in
  settings, whichever gets asked for first.
- **Cancelling the entry sheet after "Bought it" loses the goal.** The goal
  closes before the sheet opens, so backing out leaves the money sitting in
  Goals with nothing pointing at it. Recoverable by hand, but it is a re-typed
  goal.
- **Insights is only reachable from the overview.** From the ledger or goals
  you swipe back first. Same shape as the eye above, and the same fix if it
  ever grates: put it in the bar of every tab page.
- **A goal cannot be paused or archived**, only deleted. Same shape as rules,
  and the same question: does anything actually want it?
- **A contribution is always dated today.** The sheet has no date picker — the
  row it writes is an ordinary transfer, so the fix is to open it in the ledger
  and change the date there. Fine until someone catches up a month of saving in
  one sitting.
- **Nothing stops a goal being spent out of Goals by accident.** The account is
  ordinary, so an expense can be entered against it like any other, and the
  goals then quietly claim more than the account holds. `statusOf` floors at
  zero rather than going negative; a warning on the page would be the honest
  fix if it ever happens.

## Backlog

### Next up — in order, and why this order
1. **Duplicate a transaction.** *Minutes.* Long press a row → copy it to today.
   The cheapest entry shortcut left, and it needs no new model.
2. **CSV export.** *An hour.* JSON is the backup; CSV is what goes to a
   spreadsheet or an accountant. Ten lines beside `exportJson`.
3. **Calendar month view.** *A day.* A month grid showing each day's net rather
   than shaded spend. The heatmap proves the layout; this is a different cell.
   The highest "oh, *that* is where it went" per unit of work.

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
flutter test                      # 234 unit, widget and golden tests
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

# Penny — feature checklist

Working checklist for what's built, what's broken, and what's next. Tick a box
when it ships. Keep entries one line; the reasoning lives in the code comments.

**Status:** 17 source files · 6,244 lines · 208 tests · 11 goldens · 4 runtime deps
**Verified on:** Android device — runs, rupee and mono render, data survives a cold kill
**Last release:** none — no `key.properties`, so release builds fall back to debug keys
**Current build:** arm64 **18.3 MB** (`tool/release.sh`, obfuscated + split-debug-info)

**On build size:** ship `--split-per-abi` or the `.aab`, never the plain APK.
A fat `app-release.apk` carries all three ABIs and roughly doubles what anyone
downloads.

| Optimisation | Bought |
|---|---|
| Mascot poses downscaled 1254 → 512 px, palette-quantised | **5.29 MB** |
| Character sheet moved out of `assets/` into `art/` | ~1.4 MB |
| `--obfuscate --split-debug-info` (in `tool/release.sh`) | not measured — both builds write to the same path, so it needs measuring on purpose |
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

- **An undo lives in a snackbar above the tab pill, and leaves on its own.**
  The pill is a `Stack` overlay, so the `Scaffold` laying a floating snackbar
  out does not know it is there and puts the bar underneath it. On top of that,
  `SnackBar.persist` defaults to `action != null` — a bar with UNDO on it
  ignores its own `duration` and waits to be dismissed by a hand that cannot
  reach it. Both are why the toasts were pulled the first time. `showUndoBar`
  in `page_bar.dart` is the only place either is decided, and `undo_test.dart`
  measures the bar against the pill rather than trusting a golden, which the
  pill paints over.

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
- [x] Once-a-day guard (`claimMoment`, persisted) — built, not yet called
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
- [x] Tab pill tracks the swipe fraction, not just the settled page
- [x] Tab pill sits above the system gesture strip, not inside it
- [x] Splash gate → onboarding or shell
- [x] Recurring rules catch up on launch and on resume

### Overview
- [x] Total balance + per-account chips
- [x] Eye toggle — masks every amount on the page, persisted
- [x] Pinned shortcuts strip, one tap to add dated today, long press to unpin
- [x] Both of those undoable for four seconds, from a bar that clears the pill
- [x] Day / Week / Month segmented, pill slides between positions
- [x] Period arrows, forward disabled at the present
- [x] Credit / debit / net meter on one line
- [x] Spend grid — a calendar for the month, one row for the week
- [x] Recent rows grouped under day headers
- [x] Empty state leads with the action, not with three zero cards

### Ledger
- [x] Every transaction, newest first, grouped by day
- [x] Day net per header, running balance per row
- [x] Search across notes, categories, accounts, amounts
- [x] All / Debit / Credit filter

### Insights
- [x] Credit-and-debit trend, 6 periods, with a colour key
- [x] Category breakdown with share bars, largest first
- [x] "₹X more than last month", silent when there is nothing to compare

### Add & edit
- [x] Platform numeric keyboard, autofocused, decimal input formatter
- [x] Spent / Earned / Moved, with the destination account for transfers
- [x] Category, account, date pills; native date picker
- [x] Pin toggle, reflecting what is already pinned
- [x] Delete matches Save's shape and asks first, with the amount in the question

### Settings
- [x] Light / Dark / System
- [x] Accounts, categories and recurring rules as sheets
- [x] Archive rather than delete for accounts and categories
- [x] Colour and icon pickers
- [x] Export a backup (JSON, shared as a file)
- [x] Import a backup — confirmed first, decoded as UTF-8, dialog on failure

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

- **Undo covers the one-tap actions, not deleting.** Adding from a pinned chip
  and unpinning one both offer UNDO for four seconds; deleting a transaction
  asks first instead, which is the older and stronger guard. So `insertTxnAt`
  is still the one piece of undo machinery with no caller — an undo on delete
  would use it, and would mean rewriting "this cannot be undone" in the
  confirmation, which is the part to think about rather than the code.
- **Recurring rules cannot be edited** — only added and stopped. Changing rent
  means stopping one rule and creating another.
- **`showPennyMoment` and `claimMoment` are never called,** so `Penny.focus` and
  `Penny.complete` ship in the APK and are never drawn. Savings goals are what
  that machinery is waiting for.
- **Hiding covers the overview only.** The ledger and insights show every
  amount. Defensible — those are screens you go to on purpose — but it is a
  half-promise if someone expects "hide amounts" to mean the app.
- **No release signing.** `android/key.properties` does not exist, so release
  builds fall back to debug keys and cannot be shipped to anyone.
- **`archivesName` in `build.gradle.kts` does not name the APKs.** The Flutter
  Gradle plugin writes `build/app/outputs/flutter-apk/app-<abi>-release.apk`
  itself. `tool/release.sh` renames on copy, so `releases/<version>/` is where
  `penny-<version>-<abi>.apk` comes from. **Wick's comment claims otherwise and
  is wrong there too.**

## Backlog

### Next up — in order, and why this order
1. **Duplicate a transaction.** *Minutes.* Long press a row → copy it to today.
   The cheapest entry shortcut left, and it needs no new model.
2. **CSV export.** *An hour.* JSON is the backup; CSV is what goes to a
   spreadsheet or an accountant. Ten lines beside `exportJson`.
3. **Edit a recurring rule.** *Half a day.* Closes a gap above. The editor
   already exists for creating one — it needs to open on an existing rule.
4. **Calendar month view.** *A day.* A month grid showing each day's net rather
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
- **Savings goals.** A target, a date, a linked account. Celebrates at
  25/50/75/100% — which is what `showPennyMoment` and the two unused poses are
  for.
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
flutter test                      # 205 unit, widget and golden tests
flutter test --update-goldens     # only when a pixel change is deliberate
flutter analyze
python3 tool/make_icon.py         # after changing anything in art/
dart run flutter_launcher_icons   # after the above
tool/release.sh                   # split-per-abi APKs into releases/
```

Source art lives in `art/` and is never bundled; everything in `assets/icon/`,
`assets/splash/` and `assets/mascot/` is generated. Keep `app_icon.png` RGB or
RGBA, **never palette-mode**: the generator throws `RangeError` on an indexed
PNG, and only on the iOS step, so Android looks like it worked.

The original plan — and the record of where it was wrong — lives in the git
history of `PLAN.md`, removed once this file replaced it. `git log --follow --
PLAN.md` if you want to read what was expected against what shipped.

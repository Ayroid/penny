# Penny — personal money + investment tracker

> The plan, kept in the repo, and a record of where it was wrong.
>
> The sections down to **Verification** are the plan as approved. Everything
> after **Changes during the build** is what actually happened, so the two can
> be read against each other. Where a shipped file differs from a planned one
> the table marks it ▲.
>
> Last updated after v1 shipped: 205 tests, 11 goldens, 17 commits.

## Context

`~/Documents/Ayroid/Apps/design-system.html` is an explicit contract for a family of apps.
Wick (habit tracker) is the reference implementation; the design system already has a **Penny
row marked TBD** in its palette registry and names Penny as "next". So this is not a greenfield
design exercise — it is instantiating a contract that already exists.

Penny tracks cash flow: money in, money out, across accounts, with the daily/weekly/monthly
picture. Investments are deliberately **v2** — holdings are a different model (positions and
prices, not dated transactions) and shipping them alongside would delay the part that gets used
every day.

The whole point is that Penny and Wick read as siblings. That means copying Wick's structure
rather than inventing one: flat `lib/`, one `ChangeNotifier`, `theme.dart` with eleven constants
swapped, six mascot poses at the same filenames, goldens as the regression net.

**Decisions already made** (confirmed with the user):

| | |
|---|---|
| Palette | Sprout green — accent `#34B863`, ink `#16295C` navy, ground `#FFF8F1` cream (**revised after seeing the mascot art** — see below) |
| v1 scope | Cash flow only. Investments v2. |
| Model | Transactions + **categories** + **accounts** + **recurring**. Receipt photos later. |
| Currency | ₹ INR, single currency, integer paise, Indian lakh/crore grouping |

---

## Palette — Penny's row in the registry

**Derived from the mascot art, not chosen in the abstract.** The first pass picked emerald
`#00A86B` on a mint ground; the art rules that out:

- Penny's body is copper `~#EFA76B`. Green and orange are complementaries — a copper coin on a
  mint-green page vibrates. **The ground stays warm cream**, which is what the art is drawn on
  (`#FDF6EF`, essentially Wick's `#FFF8F3`).
- Every outline in the art is navy `~#1E2D5C` — Wick's ink. **The ink is navy.** A green ink
  would fight the mascot's own line work.
- The green in the art is the **sprout** (`~#4CC26E`), not a bluish emerald. Sampling the accent
  from the leaf also gets the meaning right: green is the growth, copper is the money.

So Penny differs from Wick in **the accent only**. That is exactly what the design system says
an app owns — accent, mascot, vocabulary — and forcing a different ground to look "distinct"
would actively fight the art.

```dart
// lib/theme.dart — the block that differs from Wick's
const navy       = Color(0xFF16295C);  const navySoft   = Color(0xFF33487C);
const sprout     = Color(0xFF34B863);  // the brand — Penny's leaf
const sproutSoft = Color(0xFFE6F6EC);
const coin       = Color(0xFFC97B3A);  // success / charts — Penny's copper
const coinSoft   = Color(0xFFF9EADC);
const warmBg     = Color(0xFFFFF8F1);  const warmSunk   = Color(0xFFF4ECE3);
const warmGray   = Color(0xFFDED6CC);

const darkBg = Color(0xFF0A0A0A);      const darkCard = Color(0xFF171717);
const darkSunk = Color(0xFF262626);    const darkInk = Color(0xFFFAFAFA);
const darkMuted = Color(0xFFA3A3A3);
const sproutDark = Color(0xFF45CC7A);  const sproutSoftDark = Color(0xFF10321F);
const coinDark = Color(0xFFE0A05F);    const coinSoftDark = Color(0xFF33210F);
```

### One real consequence — white does **not** go on this accent

Measured, not assumed (design system a11y rule 1):

| Pair | Contrast | Verdict |
|---|---|---|
| white on `#34B863` | **2.57** | ✗ fails 4.5 for a 15px/700 button label |
| navy `#16295C` on `#34B863` | **5.43** | ✓ |
| navy on `#45CC7A` (dark) | 6.74 | ✓ |
| navy on `#FFF8F1` | 14.6 | ✓ |
| muted `#33487C` on ground | 8.45 | ✓ |

So `onAccent()` computes to **navy in both themes** — Penny's filled buttons carry navy on green,
the way Wick's yellow fills carry navy. Wick's `theme.dart` hardcodes `Colors.white` in four
places that must therefore change:

- `filledButtonTheme` → `foregroundColor: navy`
- `ColorScheme.onPrimary` → `navy`
- `Segmented` selected label (`wick/lib/theme.dart:602`) → `navy`
- `RoundIconButton` filled glyph (`wick/lib/theme.dart:494`) → `navy`

`test/palette_test.dart` is written first so this fails loudly if the accent is ever nudged.

> Aside worth reporting: Wick has the same latent issue. White on flame `#FD5500` measures
> **3.27**, while its own `onAccent()` correctly computes navy at 4.69 — the theme just never
> calls it for buttons. Not Penny's problem to fix, but the two apps should agree.

### The copper and the green are too close in luminance

`#34B863` measures L=.359, the coin's mid-tone `#EFA76B` measures L=.402 — a **1.10** ratio.
Income and expense bars drawn in those two would be indistinguishable in greyscale and to a
deuteranope. Pushing the copper to its darker rim tone `#C97B3A` (L=.269) gets the gap to
**1.44**, which is why `coin` above is the rim colour rather than the coin face. Assert the
lit-pair gap in `palette_test`, do not eyeball it.

### The art's orange stays out of the chrome

The marketing sheet sets "tomorrow" and the sparkles in `~#F5883A`. **That is Wick's colour.**
It stays baked into the mascot PNGs, where it reads as part of the character, and never enters
Penny's buttons, chips, charts or bars — or the two apps blur into each other.

The sheet's four feature icons (green wallet / amber bars / purple pie / blue target) are four
accents, which the contract forbids for chrome. They map cleanly onto **per-category colours**
instead — Wick already carries 21 swatches and a `CategoryAccent` InheritedWidget for exactly
this.

---

## Architecture — Wick's, unchanged

Every one of these is a settled decision in Wick, re-litigating them costs time and breaks the
family resemblance:

- **`name: penny`** in `pubspec.yaml` from day one, so imports are `package:penny/...`.
  (Wick shipped as `habit_tracker`; renaming later touches every test plus Android
  `namespace`/`applicationId`.)
- **One `ChangeNotifier`** (`PennyStore`) constructed in `_AppState`, passed down as a
  constructor parameter, screens subscribe with `ListenableBuilder`. No Provider/Riverpod/Bloc.
- **Persistence is one JSON blob** in `shared_preferences` under key `ledger`. Fire-and-forget
  `_commit()`; decode failures start empty rather than bricking launch.
- **Day keys are `'YYYY-MM-DD'` strings**, and day arithmetic goes through the `DateTime`
  constructor (`DateTime(y, m, d + n)`), never `add(Duration(days:))` — a Duration is 24 real
  hours and lands on the wrong calendar day across a DST change.
- **Colours stored as an index** into the palette, icons as **stable string keys** into
  `iconGroups`, never ARGB or codepoints — so the palette and the Lucide package can both be
  upgraded without rewriting saved data.
- **Migrations are defensive reads inside `fromJson`**, not a version chain.
- **Navigation** is imperative `Navigator.push` with a top-level `open*`/`show*` function
  exported next to each screen. No route table, no `go_router`.
- **Shell** is a `PageView` with a shared `PageBar` above and a floating `PageTabs` pill in a
  `Stack` — copied from `wick/lib/page_bar.dart` and `main.dart` verbatim.
- **Comments explain why, including rejected alternatives.** That is the house style.

### Money is an integer, always

```dart
/// Paise. Never a double — 0.1 + 0.2 != 0.3 and a ledger that drifts is worthless.
final int amountMinor;
```

The entry sheet uses a **custom keypad, not a `TextField`**, and builds the amount minor-unit
first the way a banking app does:

```dart
void _digit(int d) => setState(() => _minor = (_minor * 10 + d).clamp(0, 99999999999));
void _back()       => setState(() => _minor = _minor ~/ 10);
// display: rupees(_minor)  →  tapping 1,2,3,4,5,6 shows ₹1,234.56
```

This removes locale parsing, `,` vs `.`, and rounding from the hot path entirely — there is no
string to parse because a string is never produced.

Formatting is hand-rolled (~10 lines), not `intl`. Indian grouping is "last three digits, then
pairs":

```dart
/// 12045000 -> '₹1,20,450.00'
String rupees(int minor, {bool signed = false});
```

---

## Data model — `lib/store.dart`

```dart
enum TxKind { income, expense, transfer }

class Txn {
  String id;
  TxKind kind;
  int    amountMinor;      // paise, always positive; kind carries the direction
  String day;              // 'YYYY-MM-DD'
  String categoryId;
  String accountId;        // source account
  String? toAccountId;     // transfers only
  String note;
  String? ruleId;          // set when materialised from a Recurring rule
  String createdAt;
}

class Category { String id, name, icon; int colorIndex; TxKind kind; bool archived; }
class Account  { String id, name, icon; int colorIndex, openingBalanceMinor; bool archived; }
class Rule     { String id; Txn template; String freq;   // daily|weekly|monthly
                 int interval; String startDay; String? endDay, lastRunDay; }
```

```dart
▲ class Shortcut {                 // added after v1
  String id;
  TxKind kind;
  int    amountMinor;
  String categoryId, accountId;
  String? toAccountId;
  String note;
}
```

A shortcut is curated, never inferred, and is its own persisted model rather than a flag on a
transaction — a transaction is a record of something that happened, and pinning is a statement
about the future.

**Transfers must exist in v1.** Without them, withdrawing cash from the bank looks like an
expense and both the bank balance and the month's spend are wrong. `transfer` is excluded from
every income/expense total and only moves balance between accounts — this is the single most
common correctness bug in home-grown money apps.

Defaults seeded on first run: accounts *Cash · Bank · Wallet*; expense categories *Food & Drink,
Groceries, Transport, Rent, Bills, Shopping, Health, Entertainment, Education, Family, Travel,
Other*; income categories *Salary, Freelance, Interest, Gifts, Refunds, Other*.

```
// ponytail: whole ledger is one JSON blob in SharedPreferences, as in Wick.
// ~5 txns/day for 3 years ≈ 650 KB, which loads fine. Move to sqflite when the
// blob passes ~1 MB or cold launch is felt — measure before, not on principle.
```

### Recurring rules

Same shape as Wick's reminders: a **pure function** so the rules are testable without any
clock or plugin, called once on load and once on resume.

```dart
/// Every occurrence between rule.lastRunDay (exclusive) and today (inclusive).
List<Txn> dueOccurrences(Rule rule, DateTime now);
```

Materialised transactions are ordinary rows carrying `ruleId`, so they can be edited or deleted
individually and a rule change never rewrites history. Monthly rules on the 31st clamp to the
last day of shorter months.

---

## Files — flat `lib/`, one file per screen or sheet

17 files, 6,156 lines. Marked ▲ where what shipped differs from what was planned.

| File | Lines | What it holds |
|---|---:|---|
| `settings.dart` | 1071 | ▲ theme, export/import, **and** accounts, categories and rules as sheets — three planned files folded into one, because each is a short list with a small editor |
| `store.dart` | 909 | models + `PennyStore` + persistence + export/import + ▲ `Shortcut` and `dayHeader` |
| `theme.dart` | 781 | palette, `appTheme`, `TintCard`/`SoftCard`/`Segmented`/`TintChip`/`RoundIconButton`, `CategoryAccent`, `monoStrut` |
| `home.dart` | 690 | Overview: balance, pinned strip, period picker, the credit/debit meter, spend grid, recent rows |
| `entry_sheet.dart` | 584 | Add/edit a transaction — the amount field and the pills |
| `analytics_screen.dart` | 382 | trend bars, category breakdown |
| `penny.dart` | 307 | `enum Penny` poses, `PennyImage`, `PennyMessage`, `showPennyMoment`, ▲ `CoinMark` |
| `ledger_screen.dart` | 214 | full list, search, filter, day headers, running balance |
| `page_bar.dart` | 193 | `PageBar` + floating `PageTabs` |
| `analytics.dart` | 174 | pure maths over `List<Txn>`, widget-free |
| `main.dart` | 173 | `App`, splash gate, `RootScreen` PageView, recurring catch-up |
| `txn_row.dart` | 149 | ▲ the shared transaction row — not planned, but the overview and the ledger draw the same thing |
| `icons.dart` | 148 | Lucide keys by group |
| `money.dart` | 137 | `rupees`, `parseRupees`, the input formatter, `maskedAmount` |
| `onboarding.dart` | 131 | three pages |
| `recurring.dart` | 95 | `dueOccurrences`, `materialiseDue` |
| `clock.dart` | 18 | ▲ `DateTime.now` indirected once, so dates are testable |

**Planned and not built:** `grid.dart` — Wick's `GridFrame` was to be copied verbatim, but a
month of day cells is a `GridView` with a `crossAxisCount` of 7. Porting 414 lines of a more
general widget to draw a simpler thing would have been the expensive way round.

**`categories.dart` / `accounts.dart`** were folded into `settings.dart` rather than shipped as
their own screens.

Cross-cutting rule inherited from Wick: **maths lives in `analytics.dart`, out of the screen
that draws it**, so it is tested by calling it rather than by pumping a widget.

### Shell

Three pages: **Overview · Ledger · Insights**. Filled `+` round icon button is the only primary
action on Overview and opens `entry_sheet.dart`.

### Charts, and the colour rule

The design system is explicit that the accent *never fills a chart* — `success` carries progress
so the brand colour stays meaningful. For Penny that resolves to:

- **income** → the accent at the unlit-cell alpha (`cellEmpty`, .26 light / .16 dark) — sprout
  green, the growth
- **expense** → `coin` copper at full strength — money leaving
- **net / balance number** → navy ink, with full-strength green reserved for the primary button

The two must clear the 1.4 luminance gap measured above, so the chart is still readable in
greyscale. Bars also carry a label, never colour alone.

Red (`error #DC2626`) is reserved for destructive confirmation only. **Overspending is never
red** — principle: never scold the user. A blown budget dims the mark.

Wick's contribution grid becomes a **spend heatmap**: `GridFrame` unchanged, the cell builder
maps each day's spend to an alpha between `cellEmpty` and full accent. Free visual continuity
with the sibling app, reusing 414 lines that already work.

---

## Mascot & art

User supplies the art. Same six poses, same filenames, same rules — **no disappointed pose**.

### The supplied sheet already covers all six — no new art needed

| Sheet pose | Contract name | Why |
|---|---|---|
| hero (phone + thumbs-up) | `default` | the standing pose |
| Track (holding a receipt) | `thinking` | reading, considering |
| Invest (wink, flexing at the growth arrow) | `focus` | the effortful one |
| Plan (clipboard, green ticks) | `complete` | ticks = done |
| Celebrate (arms up, confetti) | `celebrate` | — |
| Save (eyes closed, hugging the pig, heart) | `rest` | the quiet, content pose |

None of the six is disappointed, which satisfies the rule by accident — keep it that way if more
are ever drawn.

The app icon on the sheet is **already the prescribed crop** (breathing room above the leaves,
body bleeding off the bottom). It only needs re-grounding: the sheet shows it on white, and the
contract says the launcher icon sits on the app's ground colour — `#FFF8F1`, never white, never
transparent.

One consequence of a copper mascot on a cream ground: the body-vs-ground contrast is low and the
**navy outline is what carries the shape**. No silhouette or single-colour treatment of the
mascot anywhere — splash, empty state and icon all keep the line work.

- `art/mascot-source/penny_<pose>.png` at ~1250 px — outside `assets/`, not bundled.
- `assets/mascot/penny_<pose>.png` downscaled to 512 px and palette-quantised (Wick: 1.35 MB
  saved this way).
- Poses: `default · focus · complete · thinking · celebrate · rest`. `default` is the fallback
  when a pose is missing; a missing pose never leaves a hole.
- `PennyImage` constrains **height only** (`fit: BoxFit.fitHeight`) and decodes at display size
  via `cacheHeight` — poses do not share an aspect ratio and boxing them square renders the wide
  ones short.
- Sizes: 132 empty state · 148 celebration · 72 inline · 512 splash mark.
- Launcher icon is the mascot **cropped** (breathing room above the head, body bleeding off the
  bottom) on `#F5FBF7`, never transparent. Android adaptive only guarantees the centre 2/3, iOS
  shows the whole square, so `image_path` and `adaptive_icon_foreground` point at **different**
  files. Splash mark keeps the whole mascot.
- **`tool/make_icon.py` does not exist in Wick** — the design system describes it but Wick's
  crop was a manual one-off. Writing it for Penny (framing constants: mascot spans 0.52 of the
  visible box, top at 0.11) is a small script and makes both apps reproducible.
- `assets/icon/app_icon.png` must be **RGBA, not palette-mode**, or `flutter_launcher_icons`
  throws `RangeError` on the iOS step only — Android silently looks fine. Documented Wick gotcha.

---

## Dependencies

Same six as Wick, minus notifications for now:

`shared_preferences` · `share_plus` (export) · `file_picker` (import) · `lucide_icons_flutter`
· `flutter_launcher_icons` (dev). Font: `assets/fonts/PlusJakartaSans.ttf`, one variable file.

Deliberately **not** added: `intl` (10 lines of formatter), any charting package (bars and a
donut are `CustomPainter`/`Container` work and a package would fight the palette rules), any
state management, any codegen.

`flutter_local_notifications` + `timezone` come back in v2 with bill reminders.

---

## Build order

0. Fill Penny's `TBD` row in `~/Documents/Ayroid/Apps/design-system.html` (accent `#34B863`
   sprout · ink `#16295C` navy · ground `#FFF8F1` cream · "Money. Navy structures, the sprout is
   the brand, the coin is what you spend.") — the registry is the contract and it currently
   claims Penny is undecided.
1. `pubspec.yaml` + `theme.dart` + **`test/palette_test.dart` first** — the design system says
   write it first because it tells you immediately if the accent needs lifting for dark. Here it
   is what proves the white→ink fixes are needed.
2. `money.dart` + `test/money_test.dart` — paise arithmetic and Indian grouping, before anything
   depends on it.
3. `store.dart` + `test/store_test.dart` — models, seeding, persistence, transfers excluded from
   totals, export/import round-trip.
4. `penny.dart` + `onboarding.dart` + the **empty state** — the screen most people see first.
5. `entry_sheet.dart` — amount field, kind toggle, category, account, date, note.
6. `home.dart` — Day/Week/Month segmented, balance, credit/debit meter, spend grid, recent rows.
7. `ledger_screen.dart` + filters.
8. `analytics.dart` + `analytics_screen.dart`.
9. `categories.dart`, `accounts.dart`, `recurring.dart`, `settings.dart`.
10. Goldens + `a11y_test.dart`, launcher icon, splash, release script.

---

## Verification

```bash
cd ~/Documents/Ayroid/Apps/penny
flutter analyze                       # clean, flutter_lints
flutter test                          # unit + widget + golden
flutter test --update-goldens         # only when a pixel change is deliberate
flutter run -d <device>
```

Test files, named after what they protect (Wick's convention):

| Test | Asserts |
|---|---|
| `palette_test` | every contrast pair above, **per theme** — incl. that `onAccent` resolves to navy, and that `sprout` vs `coin` clear the luminance gap |
| `money_test` | `rupees(12045000) == '₹1,20,450.00'`; `parseRupees` on commas, partial decimals, garbage and overflow; the input formatter; no double anywhere |
| `app_test` | ▲ the whole app end to end — typing an amount, transfers needing two accounts, pinning and unpinning, hiding amounts without the layout moving, delete's confirmation, the week grid, day headers |
| `store_test` | seeding, add/edit/delete, **transfer excluded from income and expense totals**, balance = opening + ins − outs, export→import round-trip, malformed JSON leaves data intact |
| `recurring_test` | `dueOccurrences` across month ends, 31st clamping, DST boundary, no double-materialisation on relaunch |
| `analytics_test` | day/week/month buckets, category totals, week start, empty ranges |
| `a11y_test` | walks the compiled semantics tree; every icon-only control has tooltip + label; tap targets ≥48 |
| `golden_test` | overview, entry sheet, insights, empty state — light and dark |

Manual end-to-end: fresh install → onboarding seeds accounts → add a ₹450 expense with note →
add ₹80,000 salary → transfer ₹5,000 Bank→Cash → check Cash and Bank balances both moved and
the month's income/expense did **not** → switch Day/Week/Month → set a monthly rent rule, force
the clock forward, confirm exactly one row materialises → export, wipe, import, confirm
identical → toggle dark mode on every screen.

---

# Feature suggestions — from what shipping money apps actually do

Surveyed against Money Manager, Wallet by BudgetBakers, Bluecoins, Cashew, Money Lover,
1Money, Spendee, YNAB, Monarch, Copilot, Actual Budget, Firefly III, Walnut, and the Indian
investing apps (INDmoney, Kuvera, Zerodha Coin). Ranked by value per unit of work, with the
ones that clash with the design system called out.

### A. Cheap and high-value — do these soon after v1

| Feature | Why it earns its place |
|---|---|
| **Quick-add from the last entries** | Every app has it in some form. "Chai ₹20" typed once should be one tap forever. Implementation is a `distinct()` over the last 30 txns by (category, amount, note). Highest usage-per-line-of-code of anything on this list. |
| **Search the ledger** | Free-text over note + category + amount. One `where()`. Becomes essential the moment there are 500 rows. |
| **Month navigation with swipe** | Overview swipes between months, not just a segmented control. Cashew and Money Manager both do this and it is what makes review feel effortless. |
| **Calendar month view** | A month grid where each day shows net in/out. `GridFrame` is already there; this is a different cell builder. Very high "oh, that's where the money went" value. |
| **Duplicate a transaction** | Long-press → duplicate to today. Two lines. |
| **CSV export alongside JSON** | JSON is the backup; CSV is what goes into a spreadsheet or to an accountant. Ten lines. |
| **Running balance in the ledger** | Each row shows the balance after it. Turns the list into a bank statement, which is the mental model people already have. |
| **Per-day and per-week totals as list headers** | Sticky section headers in the ledger showing that day's net. Standard in Money Manager, Bluecoins. |

### B. Worth building, real work

| Feature | Notes |
|---|---|
| **Budgets, per category, per month** | The single most-requested money-app feature. In Penny it must follow the never-scold rule: over budget **dims** the bar and says "₹1,200 over" in ink, never red, never a warning icon. YNAB's guilt loop is exactly what to avoid. |
| **Bill reminders** | `flutter_local_notifications` comes back. Reuse Wick's `reminders.dart` almost wholesale — the "schedule 7 ahead, rebuild idempotently, no background isolate" design ports directly. Pairs naturally with recurring rules. |
| **Savings goals** | "₹50,000 by March." A goal is a target amount, a date, and a linked account. Mascot celebrates at 25/50/75/100% via `showPennyMoment` — this is what the celebrate pose is for. |
| **Split a transaction** | ₹2,400 grocery run split across Groceries and Household. Model change: a txn gets optional `splits: [{categoryId, amountMinor}]`. Do it before there is a lot of data, or not at all. |
| **Tags, alongside categories** | Category is "what kind of spend", tag is "which trip / which project". Many-to-one vs many-to-many. Bluecoins and Firefly both carry both, and people do use them differently. |
| **Month-over-month comparison** | "Food is ₹1,800 more than last month." One line of maths, disproportionate insight. Copilot's whole pitch is roughly this. |
| **Home-screen widget** | Today's spend + a `+` that deep-links straight into the entry sheet. Neither Wick nor Penny has one; it is the highest-leverage way to make entry frictionless, and friction is why people stop tracking. |
| **Lock (biometric / PIN)** | `local_auth`. Money is the category where people expect it, and its absence reads as unfinished. |

### C. Investments — the v2 shape

The honest constraint: **no free, reliable, terms-compliant price API for Indian mutual funds
and equities**, and a scraper is a maintenance liability. So:

| Feature | Notes |
|---|---|
| **Holdings, manually valued** | `Holding { name, kind (equity/MF/FD/gold/crypto), units, avgCostMinor, currentValueMinor, lastUpdatedDay }`. You type the current value when you check. Unglamorous, accurate, zero dependencies. |
| **Portfolio + net worth** | Net worth = account balances + holdings. One number on Overview, which is the reason people open investing apps at all. |
| **Absolute and XIRR return** | Absolute is trivial. XIRR needs Newton's method over dated cash flows — ~30 lines, and it is *the* number Indian investors compare. Worth doing properly. |
| **SIP tracking** | A SIP is a recurring rule that produces a *transfer into a holding* rather than an expense. Falls out of the recurring engine almost free. |
| **AMFI NAV import** | AMFI publishes a free daily NAVAll.txt for every Indian mutual fund scheme, no key, no terms problem. One HTTP fetch, parse by scheme code, and MF valuations update themselves. **This is the one price source actually worth wiring up.** Equities stay manual. |
| **Asset allocation** | Equity / debt / gold / cash split. One donut, and the thing that makes the portfolio page more than a list. |

### D. India-specific

| Feature | Notes |
|---|---|
| **Lakh/crore grouping** | Already in v1. Non-negotiable — `₹1,20,450` vs `₹120,450` is the difference between local and foreign. |
| **Financial year (Apr–Mar) as a period option** | Every Indian tax and investment conversation is in FY terms. A calendar-year-only app feels imported. |
| **Split-with-friends ledger** | "Paid ₹1,200, owe me ₹400." A lightweight IOU that settles into a real transaction. Splitwise is a separate app people resent having to open. |
| **UPI / SMS auto-import** | What Walnut built its name on. **Recommend against**: needs SMS read permission, breaks the "local, quiet, no permissions" principle, is a Play Store policy minefield, and bank SMS formats change constantly. Manual entry with good quick-add gets 90% of the benefit at 5% of the cost and none of the risk. |

### E. Deliberately not building

Each of these clashes with a principle already written down, so the decision costs nothing later
if it's recorded now:

- **Cloud sync / accounts.** "Local, quiet, no account." Backup is a JSON file the user exports.
- **Bank aggregator connections (Plaid/AA).** Requires a server, an account, and someone else's
  uptime.
- **Gamification — streaks, scores, badges for saving.** "Recognition, not points." Wick already
  owns streaks; Penny copying them would make two apps that feel the same rather than sibling.
- **Red overspending states, "you failed your budget" nudges.** "Never scold the user."
- **Multi-currency conversion.** Single currency was chosen deliberately; rates need a network
  source and an as-of date on every row, which infects the whole model.
- **Ads or a paywall.** Neither app in the family has one.

### Suggested order after v1

```
v1.1  ~~quick-add~~ ~~search~~ ~~running balance~~ ~~day headers~~ shipped
      CSV export · duplicate
v1.2  calendar month view · month-over-month
v1.3  budgets (dim, never red) · savings goals · bill reminders
v1.4  home-screen widget · app lock
v2.0  holdings · net worth · XIRR · AMFI NAV import · asset allocation
v2.1  SIP tracking · tags · splits · financial-year period
```

---

## Ceilings deliberately accepted

- `ponytail:` single JSON blob in SharedPreferences — revisit at ~1 MB, measure first.
- `ponytail:` no timezone database; day keys are local calendar days, which is correct for a
  personal ledger and wrong only if the user's ledger crosses timezones mid-day.
- `ponytail:` recurring rules materialise on app open, not in the background — a rule that fired
  while the app was closed appears the next time it opens, which is the right trade for a
  tracker with no server.


---

## Changes during the build

Three things the plan got wrong, found by writing the tests first. Each is
recorded here rather than quietly edited above.

### 1. The coin is a fill colour and carries no text

The plan set `coin` to the rim tone `#C97B3A` on the reasoning that it gave a
1.44 luminance gap against the sprout and still carried navy text. Both numbers
were wrong: the gap is **1.28** and navy on it measures **4.24**, short of 4.5.

The two requirements pull against each other — a copper far enough from the
sprout is too dark for navy and too light for white — and no single tone
satisfies both. So the coin gave up the text and kept the gap:

```dart
const coin = Color(0xFFB06A2E);   // L=.197, 1.65 from the sprout, 4.05 on cream
const coinDark = Color(0xFFC4813F);
```

Amounts sit *beside* a bar in ink, never inside it. `palette_test` asserts that
no ink survives on the coin, so the restriction is a decision rather than an
oversight.

### 2. A sprout bar cannot reach 3:1 on cream, and that is arithmetic

Navy on the sprout needs its luminance ≥ .2889 to clear 4.5:1 for a button
label. 3:1 against cream needs it ≤ .2824. **The window is empty by .0065** —
no green satisfies both. Wick's flame slips through at 3.11 only because orange
is the darker hue.

The button wins, because that is where the accent has to be right. A sprout bar
is never the only signal: every bar carries its amount as text against a
labelled axis. Dark mode has no such collision. Asserted as a bounded exception
(`>= 2.4 && < 3.0`) so it cannot drift without failing.

### 3. `design-system.html` overstates what Wick measures

The contract's a11y table claims Wick's lit-vs-unlit grid cells measure
**3.98 light**. Wick's own `test/palette_test.dart` asserts **1.15** in light,
with a written justification: on cream both cells are the same swatch, so the
gap is saturation rather than luminance, and no alpha fixes it. The doc
describes a resolution (a dark well in both themes) that Wick did not ship.

Penny follows Wick's shipped behaviour and measures ~1.90. **The doc is the
thing to correct**, not the code.

### Smaller amendments

- **Ids are monotonic, not bare timestamps.** Wick uses
  `microsecondsSinceEpoch`; Penny materialises a run of recurring rows in one
  tight loop where two calls land in the same microsecond. `newId()` never
  returns a value it has returned before.
- **Monthly recurrence counts from the start day, never from the last run.**
  Computing March from a February clamped to the 28th pins the rule to the 28th
  forever. Guarded by a test.
- **`_repair()` on load and import.** The ledger is hand-editable, so rows can
  name a category or account that does not exist. They are adopted by the first
  account and an "Uncategorised" bucket rather than dropped — losing a row
  loses money. A transfer with a dangling destination degrades to an expense,
  because left alone it would move money out of the ledger entirely.
- **`CoinMark`, a drawn mascot.** The mascot PNGs are not in the repo yet, so
  `PennyImage` falls back to a `CustomPainter` coin-and-sprout. It also serves
  the splash mark, which has to scale and recolour in a way a raster cannot.
  Drop the six PNGs into `assets/mascot/` and it is used automatically.

## Build status

**v1 shipped.** `flutter analyze` clean, **205 tests** across 8 files, 11 goldens, 17 commits.
Private repo at `github.com/Ayroid/penny`.

| Step | State |
|---|---|
| 0. Penny's row in `design-system.html` | done |
| 1. `pubspec` · `theme.dart` · `palette_test` | done — 61 tests |
| 2. `money.dart` · `money_test` | done — 21 tests |
| 3. `store.dart` · `store_test` | done — 36 tests |
| — `recurring.dart` · `analytics.dart` | done — 37 tests, written before any UI |
| 4. `penny.dart` · onboarding · empty state | done |
| 5. `entry_sheet.dart` | done |
| 6. `home.dart` | done |
| 7. `ledger_screen.dart` | done |
| 8. `analytics_screen.dart` | done |
| 9. categories · accounts · recurring · settings | done — folded into `settings.dart` |
| 10. goldens · `a11y_test` · release script · art pipeline | done |

---

## What changed after v1, and why

Everything below was found by using the app or by writing a test, not by planning. The pattern
worth noticing: **six of these were caught by a test written for something else.**

### Input

- **The custom keypad is gone.** Reimplementing a number pad the OS already provides costs the
  person their own keyboard's layout, haptics and accessibility settings. The amount is a
  `TextField` with a decimal numeric keyboard, autofocused.
- **The meaning of a typed amount changed with it.** A keypad can build paise-first (`4·5·0·0·0`
  = ₹450.00); a field prefixed with `₹` cannot — `450` there is four hundred and fifty.
  `parseRupees` is the one place a string becomes money. Length is checked *before* parsing,
  because `int.tryParse` gives up past 19 digits and would make a long paste read as garbage
  rather than as "too big".
- **The opening-balance field had the same bug the other way**: it read its digits as paise, so
  `100` showed `₹ 100` and meant ₹1.00.
- **Delete is Save's shape, and asks first.** It was a bare text button under a full-width Save.
  There is no undo anywhere, so a mis-tap was permanent; the confirmation carries the amount,
  category and note, because "delete this?" is easy to say yes to on the wrong row.

### The overview

- **Pinned shortcuts, not guessed ones.** The strip first inferred chips from recent history.
  Two entries differing only by account render as identical chips, so it filled with apparent
  duplicates, and something entered twice by accident outranked the thing worth a shortcut.
  Pinning is explicit now.
- **The flow card is a meter row**, a third of its old height. Three bars measuring a period
  against itself is a comparison nobody needs — comparing periods is the trend chart's job.
- **Credit and debit** replace in and out, the way a bank statement reads. The entry sheet keeps
  "Spent / Earned / Moved", which describes what you did rather than which column it lands in.
- **An eye masks every amount on the overview**, persisted. Masking the headline while `NET` sits
  two inches below hides nothing. The mask is a fixed six dots — one per digit would give away
  the order of magnitude.
- **The spend grid covers the week too.** It was always a calendar of days shaded by spend, just
  hard-coded to a month's shape.
- **Recent rows carry the ledger's day headers**, via the same function so the two screens
  cannot call a day different things.

### Found while building v1

- **The empty overview buried its own call to action** behind an all-zero flow card and an unlit
  heatmap — on the screen most people see first.
- **The ledger filter had four segments.** The design system says more than three is a list.
- **Tap targets were 39-40px.** `RoundIconButton` and `Segmented` hold a 48 floor now, with the
  visual unchanged. The segmented track ends up 57 tall against the spec's 52; the a11y rule wins.
- **An imported backup was decoded byte-per-character.** `utf8.decode` now — every backup carries
  a rupee sign, and most carry notes that are not ASCII.
- **`textContrastGuideline` misreads a segmented pill**, sampling the accent fill against its
  lighter track (2.19) instead of the navy glyph on it (5.43). `palette_test` measures the real
  pairs analytically; `a11y_test` pins the widget to those same values so the two cannot drift.
- **Ids are monotonic, not bare timestamps** — recurring rows are materialised in a tight loop
  where two calls land in the same microsecond.
- **Monthly recurrence counts from the start day**, never from the last run: computing March from
  a February clamped to the 28th would pin the rule to the 28th forever.
- **`_repair()` adopts orphaned rows rather than dropping them** — losing a row loses money. A
  transfer with a dangling destination degrades to an expense, because left alone it would move
  money out of the ledger entirely. **Shortcuts are the exception**: a dangling one is dropped,
  since adopting it would spend from the wrong account on a single tap.

### Bugs the tests found

- **The app never left its splash.** `late var _shell = (...)` has a *lazy* initialiser: it ran
  on first read, inside `_onStoreChanged`, i.e. after loading had finished — captured the
  post-load values, found them equal to themselves, and never called `setState`. Nothing had
  tested `App` itself; every other test pumped a page with a store already loaded.
- **The tab pill had no `Material` ancestor** and asserted on first build.
- **`PageController.page` is NaN before first layout** (`pixels / viewportDimension`, both zero),
  and **Dart's `clamp` returns NaN rather than clamping it** — so the tab padding and
  `widthFactor` went NaN and the row tried to lay out 299,210px wide.
- **The screen jumped when hiding amounts.** `•` is not in the platform mono, so a fallback font
  drew it with its own ascent and descent. `forceStrutHeight` pins the line to the font size
  whatever glyphs land in it; `₹` has the same exposure.
- **Two overflows** — the heatmap header at five figures, and a pill label with no bound.
- **Goldens rendered the mascot as empty space.** Precaching by hand did not help: `PennyImage`
  passes `cacheHeight`, which wraps the provider in a `ResizeImage` under a different cache key.
- **Goldens needed a pinned clock.** Every screen renders a date or a greeting, so images taken
  today failed tomorrow. `lib/clock.dart` indirects `DateTime.now` once. **The same bug had
  already broken 21 of Wick's goldens**, where the failures read as noise rather than signal.

### The art pipeline

`tool/make_icon.py` regenerates everything derived from `art/`. Sources are never bundled; the
six poses go from ~900 KB each to 27 KB — **5.29 MB off the APK**.

- **One file cannot serve both platforms.** Android guarantees only the centre 2/3 of an adaptive
  foreground survives the mask; iOS shows the whole square. Penny's `adaptive_icon_foreground`
  and `image_path` point at different files. *Wick had them pointing at the same one*, so it was
  shipping the iOS framing on Android.
- **`Image.getbbox()` trims on `alpha > 0`**, and the art carries near-invisible noise at the
  canvas edge — 88px of phantom on Wick's candle. It centred a box that was not there. Trimming
  is thresholded at `alpha > 8`.
- The adaptive foreground is oversized **1.21×** past the guaranteed box, deliberately: framing
  to the guarantee reads small against every other icon on the phone, and a mask tight enough to
  clip it would be clipping the corners off everything else too.

---

## Ceilings still accepted

- `ponytail:` single JSON blob in SharedPreferences — revisit at ~1 MB, measure first.
- `ponytail:` no timezone database; day keys are local calendar days.
- `ponytail:` recurring rules materialise on app open, not in the background.
- **No undo, anywhere.** The snackbars were removed on request, and they carried every undo path.
  Deleting asks; adding from a pinned chip does not, because the row lands at the top of RECENT
  where it can be opened and deleted.
- **Hiding covers the overview only.** The ledger and insights are screens you go to on purpose.
- **Recurring rules cannot be edited**, only added and stopped.
- **`showPennyMoment` and `claimMoment` are unused**, and with them `Penny.focus` and
  `Penny.complete` — two poses that ship and are never drawn. Savings goals are what they are
  for.

## Suggested next

```
next   duplicate a transaction · CSV export · edit a recurring rule
then   calendar month view · month-over-month · budgets (dim, never red)
       savings goals — which is what the celebration machinery is waiting for
v2     holdings · net worth · XIRR · AMFI NAV import · asset allocation
```

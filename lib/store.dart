import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'clock.dart';
import 'icons.dart';
import 'money.dart';
import 'theme.dart';

const _ledgerKey = 'ledger';
const _themeKey = 'themeMode';
const _onboardedKey = 'onboarded';
const _momentsKey = 'moments';
const _hideAmountsKey = 'hideAmounts';

/// Calendar-day key, e.g. "2026-09-04". A transaction happens on a *day*, not
/// at an instant, so days are stored as strings — no DateTime equality or
/// timezone drift to get wrong. Zero-padded, so lexical order is chronological
/// order and the ledger sorts on the string.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Day arithmetic via the constructor, never `add`/`subtract(Duration(days:))`:
/// a Duration is 24 real hours, which lands on the wrong calendar day across a
/// DST transition.
DateTime shiftDays(DateTime d, int by) => DateTime(d.year, d.month, d.day + by);

/// [by] months on, clamped to the target month's length.
///
/// `DateTime(2026, 1, 31 + 1 month)` would roll into March; a rent rule set on
/// the 31st has to land on the 28th in February, not skip the month.
DateTime shiftMonths(DateTime d, int by) {
  final m = DateTime(d.year, d.month + by);
  final lastDay = DateTime(m.year, m.month + 1, 0).day;
  return DateTime(m.year, m.month, d.day < lastDay ? d.day : lastDay);
}

/// Monday of [d]'s week.
DateTime startOfWeek(DateTime d) => shiftDays(d, -(d.weekday - 1));

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime today() {
  final n = clock();
  return DateTime(n.year, n.month, n.day);
}

/// How a day is titled above the rows belonging to it.
///
/// Shared by the ledger and the overview's recent list, so the two cannot
/// drift into calling the same day different things.
String dayHeader(String key) {
  final d = parseDay(key);
  final t = today();
  if (d == t) return 'TODAY';
  if (d == shiftDays(t, -1)) return 'YESTERDAY';
  return longDate(d).toUpperCase();
}

/// A unique, monotonically increasing id.
///
/// Wick uses a bare microsecond timestamp, which is fine when a person taps
/// once. Penny materialises a run of recurring transactions in a single tight
/// loop, where two calls can land in the same microsecond and produce two rows
/// with the same id — so the counter never goes backwards.
int _lastId = 0;
String newId() {
  var t = DateTime.now().microsecondsSinceEpoch;
  if (t <= _lastId) t = _lastId + 1;
  _lastId = t;
  return t.toString();
}

/// Money in, money out, or money moved.
///
/// [transfer] is not a third kind of spending — it is the reason the ledger
/// stays honest. Withdrawing cash from the bank is not an expense; without
/// this the month's spend is overstated and the bank balance is wrong. Every
/// income/expense total in the app excludes transfers.
enum TxKind {
  income,
  expense,
  transfer;

  static TxKind parse(String? s) => TxKind.values.firstWhere(
    (k) => k.name == s,
    orElse: () => TxKind.expense,
  );
}

class Txn {
  Txn({
    String? id,
    required this.kind,
    required this.amountMinor,
    required this.day,
    required this.categoryId,
    required this.accountId,
    this.toAccountId,
    this.note = '',
    this.ruleId,
    this.goalId,
    String? createdAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now().toIso8601String();

  final String id;

  /// When the row was entered, as opposed to [day], which is when the money
  /// moved. Backdating an entry must not reorder yesterday's list.
  final String createdAt;

  TxKind kind;

  /// Paise, always positive. [kind] carries the direction — a negative amount
  /// would give two ways to say the same thing and one of them would be wrong.
  int amountMinor;

  /// Day key. See [dayKey].
  String day;

  String categoryId;

  /// The account the money left, or arrived in for income.
  String accountId;

  /// Transfers only: where the money went.
  String? toAccountId;

  String note;

  /// Set when this row was materialised from a [Rule]. The row is otherwise
  /// ordinary — editable and deletable on its own — so changing a rule never
  /// rewrites history.
  String? ruleId;

  /// Set when this transfer is money put aside for, or taken back out of, a
  /// [Goal]. The row is an ordinary transfer either way; the id is what lets a
  /// goal add up what is in it, and deleting the row here takes the money back
  /// out of the goal rather than leaving the two disagreeing.
  String? goalId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'amount': amountMinor,
    'day': day,
    'category': categoryId,
    'account': accountId,
    if (toAccountId != null) 'toAccount': toAccountId,
    if (note.isNotEmpty) 'note': note,
    if (ruleId != null) 'rule': ruleId,
    if (goalId != null) 'goal': goalId,
    'createdAt': createdAt,
  };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
    id: j['id'] as String?,
    kind: TxKind.parse(j['kind'] as String?),
    // Clamped, not trusted: this is a hand-editable export, and a negative
    // or absurd amount must not be able to invert a balance.
    amountMinor: ((j['amount'] as num?)?.toInt() ?? 0).clamp(0, maxMinor),
    day: j['day'] as String? ?? dayKey(today()),
    categoryId: j['category'] as String? ?? '',
    accountId: j['account'] as String? ?? '',
    toAccountId: j['toAccount'] as String?,
    note: j['note'] as String? ?? '',
    ruleId: j['rule'] as String?,
    goalId: j['goal'] as String?,
    createdAt: j['createdAt'] as String?,
  );
}

class Category {
  Category({
    String? id,
    required this.name,
    required this.kind,
    this.icon = defaultIcon,
    this.color = defaultCatColor,
    this.archived = false,
  }) : id = id ?? newId();

  final String id;
  String name;

  /// Income and expense categories are separate lists; a category never
  /// serves both, or every breakdown has to explain itself.
  TxKind kind;
  String icon;

  /// Index into `catColors`. Stored as an index rather than an ARGB value so
  /// the palette can be retuned without rewriting saved data.
  int color;
  bool archived;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'icon': icon,
    'color': color,
    if (archived) 'archived': true,
  };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String?,
    name: j['name'] as String? ?? 'Untitled',
    kind: TxKind.parse(j['kind'] as String?),
    icon: j['icon'] as String? ?? defaultIcon,
    color: (j['color'] as num?)?.toInt() ?? defaultCatColor,
    archived: j['archived'] as bool? ?? false,
  );
}

class Account {
  Account({
    String? id,
    required this.name,
    this.icon = 'wallet',
    this.color = defaultCatColor,
    this.openingBalanceMinor = 0,
    this.archived = false,
    this.forGoals = false,
    this.pinned = false,
  }) : id = id ?? newId();

  final String id;
  String name;
  String icon;
  int color;

  /// The one account goals are held in. Created the first time money is put
  /// aside rather than seeded — an empty "Goals" chip on a fresh ledger is an
  /// answer to a question nobody asked.
  bool forGoals;

  /// What was in the account the day tracking started. Signed: an account can
  /// legitimately open in the red (a credit card).
  int openingBalanceMinor;
  bool archived;

  /// On the overview's balance card. A phone fits four tiles across, so this
  /// is a choice rather than a list — see [PennyStore.pinnedAccounts].
  bool pinned;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'opening': openingBalanceMinor,
    if (archived) 'archived': true,
    if (forGoals) 'forGoals': true,
    if (pinned) 'pinned': true,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as String?,
    name: j['name'] as String? ?? 'Account',
    icon: j['icon'] as String? ?? 'wallet',
    color: (j['color'] as num?)?.toInt() ?? defaultCatColor,
    openingBalanceMinor: (j['opening'] as num?)?.toInt() ?? 0,
    archived: j['archived'] as bool? ?? false,
    forGoals: j['forGoals'] as bool? ?? false,
    pinned: j['pinned'] as bool? ?? false,
  );
}

enum Freq {
  daily,
  weekly,
  monthly;

  static Freq parse(String? s) =>
      Freq.values.firstWhere((f) => f.name == s, orElse: () => Freq.monthly);
}

/// A transaction that repeats: rent, salary, a subscription.
///
/// The rule is a template, not a ledger entry. It produces ordinary [Txn] rows
/// which then live their own lives.
class Rule {
  Rule({
    String? id,
    required this.kind,
    required this.amountMinor,
    required this.categoryId,
    required this.accountId,
    this.toAccountId,
    this.note = '',
    this.freq = Freq.monthly,
    this.interval = 1,
    required this.startDay,
    this.endDay,
    this.lastRunDay,
    this.active = true,
  }) : id = id ?? newId();

  final String id;
  TxKind kind;
  int amountMinor;
  String categoryId;
  String accountId;
  String? toAccountId;
  String note;
  Freq freq;

  /// Every [interval] periods — 2 weekly is a fortnight.
  int interval;

  /// The day the first occurrence falls on. Monthly rules take their day of
  /// month from here.
  String startDay;
  String? endDay;

  /// The last day already materialised. Null means nothing has run yet, and
  /// the first occurrence is [startDay] itself.
  String? lastRunDay;
  bool active;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'amount': amountMinor,
    'category': categoryId,
    'account': accountId,
    if (toAccountId != null) 'toAccount': toAccountId,
    if (note.isNotEmpty) 'note': note,
    'freq': freq.name,
    'interval': interval,
    'startDay': startDay,
    if (endDay != null) 'endDay': endDay,
    if (lastRunDay != null) 'lastRunDay': lastRunDay,
    if (!active) 'active': false,
  };

  factory Rule.fromJson(Map<String, dynamic> j) => Rule(
    id: j['id'] as String?,
    kind: TxKind.parse(j['kind'] as String?),
    amountMinor: ((j['amount'] as num?)?.toInt() ?? 0).clamp(0, maxMinor),
    categoryId: j['category'] as String? ?? '',
    accountId: j['account'] as String? ?? '',
    toAccountId: j['toAccount'] as String?,
    note: j['note'] as String? ?? '',
    freq: Freq.parse(j['freq'] as String?),
    // Clamped: a zero or negative interval is an infinite loop in
    // `dueOccurrences`, and this file is hand-editable.
    interval: ((j['interval'] as num?)?.toInt() ?? 1).clamp(1, 366),
    startDay: j['startDay'] as String? ?? dayKey(today()),
    endDay: j['endDay'] as String?,
    lastRunDay: j['lastRunDay'] as String?,
    active: j['active'] as bool? ?? true,
  );
}

/// A transaction the person has chosen to keep one hold away — a quick entry,
/// floated out of the add button.
///
/// Curated, never inferred. Guessing at these from recent history sounds
/// helpful and is not: two entries that differ only by account look identical
/// on a chip, so the row fills with apparent duplicates, and a thing you
/// happened to enter twice outranks the one you actually want. This is a thing
/// you save on purpose.
class Shortcut {
  Shortcut({
    String? id,
    required this.kind,
    required this.amountMinor,
    required this.categoryId,
    required this.accountId,
    this.toAccountId,
    this.note = '',
  }) : id = id ?? newId();

  final String id;
  TxKind kind;
  int amountMinor;
  String categoryId;
  String accountId;
  String? toAccountId;
  String note;

  /// The same shortcut, ignoring identity — so saving a thing twice does not
  /// leave two chips that cannot be told apart.
  bool sameAs(Shortcut other) =>
      kind == other.kind &&
      amountMinor == other.amountMinor &&
      categoryId == other.categoryId &&
      accountId == other.accountId &&
      toAccountId == other.toAccountId &&
      note == other.note;

  /// This shortcut as a transaction, dated today.
  Txn toTxn() => Txn(
    kind: kind,
    amountMinor: amountMinor,
    day: dayKey(today()),
    categoryId: categoryId,
    accountId: accountId,
    toAccountId: kind == TxKind.transfer ? toAccountId : null,
    note: note,
  );

  /// The shortcut [txn] would become if it were saved.
  factory Shortcut.of(Txn txn) => Shortcut(
    kind: txn.kind,
    amountMinor: txn.amountMinor,
    categoryId: txn.categoryId,
    accountId: txn.accountId,
    toAccountId: txn.toAccountId,
    note: txn.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'amount': amountMinor,
    'category': categoryId,
    'account': accountId,
    if (toAccountId != null) 'toAccount': toAccountId,
    if (note.isNotEmpty) 'note': note,
  };

  factory Shortcut.fromJson(Map<String, dynamic> j) => Shortcut(
    id: j['id'] as String?,
    kind: TxKind.parse(j['kind'] as String?),
    amountMinor: ((j['amount'] as num?)?.toInt() ?? 0).clamp(0, maxMinor),
    categoryId: j['category'] as String? ?? '',
    accountId: j['account'] as String? ?? '',
    toAccountId: j['toAccount'] as String?,
    note: j['note'] as String? ?? '',
  );
}

/// Something being saved for: a name, a target, and nothing else.
///
/// The goal holds no money. Putting ₹2,000 aside moves ₹2,000 out of the
/// account it came from and into the goals account, as an ordinary transfer in
/// the ledger — so the account you spend from is genuinely lighter by what you
/// have promised elsewhere, and the row is there to find, edit and delete like
/// any other. What a goal has in it is summed from those rows
/// ([PennyStore.statusOf]), never stored here: two places for one number is
/// two places to disagree.
/// Where a goal is in its life.
///
/// One field with three states rather than two booleans: paused-and-archived
/// is not a thing, and a pair of flags is a pair that can say it.
enum GoalState {
  active,
  paused,
  archived;

  static GoalState parse(String? s) => GoalState.values.firstWhere(
    (v) => v.name == s,
    // A state this build does not know about is a goal, not a crash.
    orElse: () => GoalState.active,
  );
}

class Goal {
  Goal({
    String? id,
    required this.name,
    required this.targetMinor,
    this.icon = 'piggy-bank',
    this.state = GoalState.active,
  }) : id = id ?? newId();

  final String id;
  String name;

  /// What the thing costs. Always positive — the editor will not save a zero.
  int targetMinor;

  /// No colour of its own, unlike a category or an account: a goal is drawn in
  /// the brand's green wherever it appears. Saved files from before that carry
  /// a `color`, and it is read past — the palette index was never anything but
  /// decoration on this object.
  String icon;

  /// Paused takes no more money; archived is out of the way entirely. Neither
  /// moves what is already set aside — that is in the goals account, and only
  /// a transfer takes it out again.
  GoalState state;

  bool get paused => state == GoalState.paused;
  bool get archived => state == GoalState.archived;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': targetMinor,
    'icon': icon,
    if (state != GoalState.active) 'state': state.name,
  };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
    id: j['id'] as String?,
    name: j['name'] as String? ?? 'Goal',
    targetMinor: ((j['target'] as num?)?.toInt() ?? 0).clamp(0, maxMinor),
    icon: j['icon'] as String? ?? 'piggy-bank',
    state: GoalState.parse(j['state'] as String?),
  );
}

// ── The store ───────────────────────────────────────────────────────────────

/// The model, the store and the persistence layer, in one object.
///
/// One `ChangeNotifier`, constructed once in `main.dart` and passed down as a
/// constructor parameter. No state-management package: there is exactly one
/// thing to listen to, and a package to deliver it would be ceremony.
class PennyStore extends ChangeNotifier {
  final List<Txn> txns = [];
  final List<Category> categories = [];
  final List<Account> accounts = [];
  final List<Rule> rules = [];
  final List<Shortcut> shortcuts = [];
  final List<Goal> goals = [];

  ThemeMode themeMode = ThemeMode.light;

  /// Whether the balance is masked on the overview. Persisted, because the
  /// reason to hide it — a shared desk, a train, handing someone the phone —
  /// outlasts one launch, and having to hide it again every time is why people
  /// stop bothering.
  bool hideAmounts = false;
  bool onboarded = false;
  bool loaded = false;

  /// Celebrations already shown, by key, against the day they were shown on.
  /// Reopening the app must not replay a moment the person already saw.
  final Map<String, String> _moments = {};

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode
        .values[(prefs.getInt(_themeKey) ?? ThemeMode.light.index).clamp(0, 2)];
    onboarded = prefs.getBool(_onboardedKey) ?? false;
    hideAmounts = prefs.getBool(_hideAmountsKey) ?? false;

    final rawMoments = prefs.getString(_momentsKey);
    if (rawMoments != null) {
      try {
        (jsonDecode(rawMoments) as Map).forEach(
          (k, v) => _moments[k as String] = v as String,
        );
      } catch (_) {
        // A corrupt moments map costs a repeated celebration, nothing more.
      }
    }

    final raw = prefs.getString(_ledgerKey);
    if (raw != null) {
      try {
        _adopt(_decode(raw));
      } catch (e) {
        // Start empty rather than bricking launch. The stored string is left
        // untouched, so a bad read is recoverable by hand.
        debugPrint('ledger: could not read stored data ($e)');
      }
    }

    loaded = true;
    notifyListeners();
  }

  /// Decode a ledger document into fresh lists, without touching the store.
  ///
  /// Used by both [load] and [importJson] — an import that throws must leave
  /// the existing data exactly as it was, so nothing is cleared until this has
  /// returned successfully.
  static ({
    List<Account> accounts,
    List<Category> categories,
    List<Txn> txns,
    List<Rule> rules,
    List<Shortcut> shortcuts,
    List<Goal> goals,
  })
  _decode(String raw) {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    List<T> read<T>(String key, T Function(Map<String, dynamic>) from) => [
      for (final e in (doc[key] as List? ?? const []))
        from(e as Map<String, dynamic>),
    ];

    return (
      accounts: read('accounts', Account.fromJson),
      categories: read('categories', Category.fromJson),
      txns: read('txns', Txn.fromJson),
      rules: read('rules', Rule.fromJson),
      shortcuts: read('shortcuts', Shortcut.fromJson),
      goals: read('goals', Goal.fromJson),
    );
  }

  void _adopt(
    ({
      List<Account> accounts,
      List<Category> categories,
      List<Txn> txns,
      List<Rule> rules,
      List<Shortcut> shortcuts,
      List<Goal> goals,
    })
    doc,
  ) {
    accounts
      ..clear()
      ..addAll(doc.accounts);
    categories
      ..clear()
      ..addAll(doc.categories);
    txns
      ..clear()
      ..addAll(doc.txns);
    rules
      ..clear()
      ..addAll(doc.rules);
    shortcuts
      ..clear()
      ..addAll(doc.shortcuts);
    goals
      ..clear()
      ..addAll(doc.goals);
    _repair();
    _renameUntouchedDefaults();
    _sort();
  }

  /// One-time renames of seeded defaults nobody has touched.
  ///
  /// Changing `seedDefaults` only changes what a *new* ledger starts with —
  /// existing data keeps whatever it already says, which is right for anything
  /// the person named themselves. This is the narrow exception: an account
  /// still sitting at the exact name and icon it was seeded with was never
  /// chosen, so renaming it is finishing the rename rather than overwriting a
  /// decision. An account the person renamed, recoloured or re-iconed is left
  /// alone.
  void _renameUntouchedDefaults() {
    for (final a in accounts) {
      if (a.name == 'Card' && a.icon == 'credit-card') {
        a
          ..name = 'Wallet'
          ..icon = 'wallet';
      }
    }
  }

  /// Point dangling references at something real.
  ///
  /// The ledger is an exportable, hand-editable JSON file, so a row can arrive
  /// naming a category or account that does not exist. Dropping the row would
  /// silently lose money; showing it would crash the renderer. It gets adopted
  /// by the first account and an "Uncategorised" bucket instead, where the
  /// person can see it and fix it.
  void _repair() {
    if (accounts.isEmpty) accounts.add(Account(name: 'Cash', icon: 'wallet'));

    final accountIds = {for (final a in accounts) a.id};
    final categoryIds = {for (final c in categories) c.id};
    final fallbackAccount = accounts.first.id;

    Category? orphanBucket;
    String orphanCategory(TxKind kind) {
      orphanBucket ??= () {
        final existing = categories.where((c) => c.name == 'Uncategorised');
        if (existing.isNotEmpty) return existing.first;
        final c = Category(
          name: 'Uncategorised',
          kind: TxKind.expense,
          icon: 'circle',
        );
        categories.add(c);
        categoryIds.add(c.id);
        return c;
      }();
      return orphanBucket!.id;
    }

    for (final t in txns) {
      if (!accountIds.contains(t.accountId)) t.accountId = fallbackAccount;
      if (t.kind == TxKind.transfer) {
        // A transfer with nowhere to go, or one that arrives where it started,
        // would move money out of the ledger entirely.
        if (t.toAccountId == null ||
            !accountIds.contains(t.toAccountId) ||
            t.toAccountId == t.accountId) {
          t.kind = TxKind.expense;
          t.toAccountId = null;
        }
      } else {
        t.toAccountId = null;
      }
      if (!categoryIds.contains(t.categoryId)) {
        t.categoryId = orphanCategory(t.kind);
      }
    }

    rules.removeWhere(
      (r) =>
          !accountIds.contains(r.accountId) ||
          !categoryIds.contains(r.categoryId),
    );

    // A transfer that named a goal which is no longer here stays in the ledger
    // — it is a real movement of money — but stops claiming to belong to one.
    final goalIds = {for (final g in goals) g.id};
    for (final t in txns) {
      if (t.goalId != null && !goalIds.contains(t.goalId)) t.goalId = null;
    }

    // A shortcut is a convenience, not a record: one pointing at an account or
    // category that no longer exists is dropped rather than adopted, because
    // silently repointing it would spend from the wrong account on one tap.
    shortcuts.removeWhere(
      (s) =>
          !accountIds.contains(s.accountId) ||
          !categoryIds.contains(s.categoryId),
    );
  }

  /// Newest first, and stable within a day by entry order — backdating a row
  /// must not shuffle the ones already there.
  void _sort() {
    txns.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
    });
  }

  void _commit() {
    notifyListeners();
    // Fire-and-forget: the UI never waits on disk.
    //
    // ponytail: the whole ledger is re-encoded on every mutation and written
    // as one blob. ~5 rows/day for 3 years is ~650 KB, which encodes in a few
    // ms. Move to sqflite when the blob passes ~1 MB or a save is felt —
    // measure first.
    SharedPreferences.getInstance().then(
      (p) => p.setString(_ledgerKey, exportJson()),
    );
  }

  // ── First run ─────────────────────────────────────────────────────────────

  /// The accounts and categories a new ledger starts with.
  ///
  /// Seeded rather than left empty because the first thing anyone does is add
  /// a transaction, and being asked to invent a category taxonomy first is how
  /// a money app loses someone in the first minute.
  void seedDefaults() {
    if (accounts.isNotEmpty || categories.isNotEmpty) return;

    accounts.addAll([
      Account(name: 'Cash', icon: 'banknote', color: 2),
      Account(name: 'Bank', icon: 'landmark', color: 10),
      Account(name: 'Wallet', icon: 'wallet', color: 12),
    ]);

    const expenses = [
      ('Food & Drink', 'utensils', 1),
      ('Groceries', 'shopping-basket', 5),
      ('Transport', 'car', 9),
      ('Rent', 'house', 16),
      ('Bills', 'lightbulb', 3),
      ('Shopping', 'shopping-cart', 14),
      ('Health', 'heart-pulse', 0),
      ('Entertainment', 'film', 13),
      ('Education', 'graduation-cap', 11),
      ('Family', 'users', 15),
      ('Travel', 'plane', 7),
      ('Other', 'tag', 18),
    ];
    const incomes = [
      ('Salary', 'briefcase', 6),
      ('Freelance', 'laptop', 8),
      ('Interest', 'trending-up', 4),
      ('Gifts', 'gift', 15),
      ('Refunds', 'arrow-left-right', 17),
      ('Other', 'tag', 18),
    ];

    for (final (name, icon, color) in expenses) {
      categories.add(
        Category(name: name, kind: TxKind.expense, icon: icon, color: color),
      );
    }
    for (final (name, icon, color) in incomes) {
      categories.add(
        Category(name: name, kind: TxKind.income, icon: icon, color: color),
      );
    }
    _commit();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  Future<void> setHideAmounts(bool value) async {
    hideAmounts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideAmountsKey, value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  /// True the first time [key] is claimed, and never again. Persisted, so a
  /// relaunch does not replay a celebration.
  ///
  /// Once ever, not once a day: the things worth a moment here are milestones
  /// — half of a goal, all of it — and a milestone is only crossed once. The
  /// day it happened is stored rather than a bare flag because it costs
  /// nothing and answers "when was that?" from an export.
  bool claimMoment(String key) {
    if (_moments.containsKey(key)) return false;
    _moments[key] = dayKey(today());
    SharedPreferences.getInstance().then(
      (p) => p.setString(_momentsKey, jsonEncode(_moments)),
    );
    return true;
  }

  /// [amount] as it should read on screen: the figure itself, or the mask when
  /// amounts are hidden. One place, so no screen can forget one.
  String show(String amount) => hideAmounts ? maskedAmount : amount;

  // ── Lookups ───────────────────────────────────────────────────────────────

  Account? accountById(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Category? categoryById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Category> categoriesOf(TxKind kind) => [
    for (final c in categories)
      if (c.kind == kind && !c.archived) c,
  ];

  List<Account> get liveAccounts => [
    for (final a in accounts)
      if (!a.archived) a,
  ];

  /// How many account tiles the balance card holds. Four across a phone at
  /// the width the tiles are drawn — a fifth wraps to a second row and pushes
  /// the card past the height the rest of the overview is laid out around.
  static const maxPinned = 4;

  /// What the balance card shows.
  ///
  /// Nothing pinned means the app picks: the first four, which is what the
  /// card did before pinning existed and what a fresh ledger with three seeded
  /// accounts wants anyway. Pin one and the choice becomes yours entirely —
  /// there is no "these four plus mine", because a card that adds accounts you
  /// did not ask for is the thing pinning exists to stop.
  List<Account> get pinnedAccounts {
    final chosen = [
      for (final a in liveAccounts)
        if (a.pinned) a,
    ];
    return chosen.isEmpty
        ? liveAccounts.take(maxPinned).toList()
        : chosen.take(maxPinned).toList();
  }

  /// Whether [a] can go on the card right now: it is already there, or there
  /// is room. The editor reads this to word its own button.
  bool canPin(Account a) =>
      a.pinned ||
      [
            for (final x in liveAccounts)
              if (x.pinned) x,
          ].length <
          maxPinned;

  /// Pins or unpins [a], up to [maxPinned]. Silently does nothing when the
  /// card is full — the caller has [canPin] to ask with.
  void setAccountPinned(Account a, bool value) {
    if (value && !canPin(a)) return;
    a.pinned = value;
    _commit();
  }

  /// The accounts a person can pick by hand.
  ///
  /// Not the goals account: money gets into it by putting some aside and out
  /// of it by withdrawing or by buying the thing, and every one of those routes
  /// goes through a goal that then knows about it. An ordinary expense entered
  /// against it spends what a goal has already spoken for, and the goals go on
  /// claiming money the account no longer holds — which is why this is a
  /// filter on the picker rather than a warning after the fact.
  ///
  /// [keep] is the account a sheet is already sitting on — the prefilled
  /// "Bought it" spend, or a contribution opened from the ledger to edit. It
  /// stays in the list, because a picker that cannot show the current value is
  /// a picker that silently changes it.
  List<Account> pickableAccounts([String? keep]) => [
    for (final a in liveAccounts)
      if (!a.forGoals || a.id == keep) a,
  ];

  /// The goals the page is about. Archived ones keep their money and their
  /// transfers; they are simply not what anyone is saving for any more.
  List<Goal> get liveGoals => [
    for (final g in goals)
      if (!g.archived) g,
  ];

  List<Goal> get archivedGoals => [
    for (final g in goals)
      if (g.archived) g,
  ];

  // ── Balances ──────────────────────────────────────────────────────────────

  /// What is in [accountId] right now: its opening balance plus everything
  /// that has landed in it, minus everything that has left.
  ///
  /// ponytail: a full scan of the ledger per account. Four accounts on the
  /// settings screen is four passes over a few thousand rows, which is
  /// microseconds. Cache per (accountId, txns.length) if a very long ledger
  /// ever makes a list scroll stutter.
  int balanceOf(String accountId) {
    var v = accountById(accountId)?.openingBalanceMinor ?? 0;
    for (final t in txns) {
      switch (t.kind) {
        case TxKind.income:
          if (t.accountId == accountId) v += t.amountMinor;
        case TxKind.expense:
          if (t.accountId == accountId) v -= t.amountMinor;
        case TxKind.transfer:
          // Both sides, so a transfer nets to zero across the whole ledger.
          if (t.accountId == accountId) v -= t.amountMinor;
          if (t.toAccountId == accountId) v += t.amountMinor;
      }
    }
    return v;
  }

  /// Every live account added up. Archived accounts are excluded — archiving
  /// one is how you say "this is no longer part of my money".
  int get totalBalance {
    var v = 0;
    for (final a in liveAccounts) {
      v += balanceOf(a.id);
    }
    return v;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  void addTxn(Txn t) {
    txns.add(t);
    _sort();
    _commit();
  }

  /// Removes [t] and returns where it was, so an undo can put it back.
  int removeTxn(Txn t) {
    final i = txns.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      txns.removeAt(i);
      _commit();
    }
    return i;
  }

  void insertTxnAt(int index, Txn t) {
    txns.insert(index.clamp(0, txns.length), t);
    _commit();
  }

  void addCategory(Category c) {
    categories.add(c);
    _commit();
  }

  void addAccount(Account a) {
    accounts.add(a);
    _commit();
  }

  void addRule(Rule r) {
    rules.add(r);
    _commit();
  }

  /// Save [shortcut], unless the same thing is already saved. Returns whether
  /// anything was added.
  bool addShortcut(Shortcut shortcut) {
    if (shortcuts.any((s) => s.sameAs(shortcut))) return false;
    shortcuts.add(shortcut);
    _commit();
    return true;
  }

  void removeShortcut(Shortcut shortcut) {
    shortcuts.removeWhere((s) => s.id == shortcut.id);
    _commit();
  }

  /// The saved shortcut matching [txn], if there is one.
  Shortcut? shortcutFor(Txn txn) {
    final candidate = Shortcut.of(txn);
    for (final s in shortcuts) {
      if (s.sameAs(candidate)) return s;
    }
    return null;
  }

  void removeRule(Rule r) {
    rules.removeWhere((x) => x.id == r.id);
    _commit();
  }

  void addGoal(Goal g) {
    goals.add(g);
    _commit();
  }

  /// Removes [g]. The transfers it collected stay in the ledger and the money
  /// stays in the goals account — deleting a goal is giving up on the plan,
  /// not spending the money, and the app must not guess where it should go
  /// back to.
  void removeGoal(Goal g) {
    goals.removeWhere((x) => x.id == g.id);
    _repair();
    _commit();
  }

  /// The account goals are held in, made on first use.
  Account goalsAccount() {
    final existing = goalsAccountOrNull;
    if (existing != null) return existing;
    final a = Account(
      name: 'Goals',
      icon: 'piggy-bank',
      color: 4,
      forGoals: true,
    );
    accounts.add(a);
    _commit();
    return a;
  }

  Account? get goalsAccountOrNull {
    for (final a in accounts) {
      if (a.forGoals) return a;
    }
    return null;
  }

  /// A transfer still carries a category — the field is not nullable, and a
  /// dangling id would be adopted into an "Uncategorised" bucket by [_repair].
  /// Every breakdown ignores it, exactly as it ignores the one the entry sheet
  /// puts on a transfer typed by hand.
  String _transferCategoryId() {
    final expense = categoriesOf(TxKind.expense);
    if (expense.isNotEmpty) return expense.first.id;
    return categories.isEmpty ? '' : categories.first.id;
  }

  /// The most that can go from [fromAccountId] into [g] right now.
  ///
  /// Two ceilings, and the lower one wins: what the account actually holds,
  /// and what the goal still needs. Zero or less means nothing can move —
  /// an empty account, or a goal already funded.
  int roomToPutAside(Goal g, String fromAccountId) {
    if (g.state != GoalState.active) return 0;
    final balance = balanceOf(fromAccountId);
    final needed = statusOf(g).remaining;
    return balance < needed ? balance : needed;
  }

  /// Put [minor] aside for [g], out of [fromAccountId].
  ///
  /// An ordinary transfer, dated today, tagged with the goal: the account it
  /// came from is lighter by the amount, the goals account is heavier, and the
  /// total balance does not move — the money is still yours, it is just
  /// somewhere with a name on it.
  ///
  /// The two ceilings are refused differently, because they are different
  /// mistakes. More than the account holds is not money, so nothing moves at
  /// all and this returns null. More than the goal still needs is only an
  /// overshoot, so ₹500 offered to a goal that needs ₹300 moves ₹300 and the
  /// rest stays where it was.
  Txn? putAside(Goal g, int minor, String fromAccountId, {DateTime? on}) {
    final needed = statusOf(g).remaining;
    // Guarded here rather than only on the button: this is where every caller
    // routes through, and a paused goal that quietly accepts money from a
    // second entry point is the bug the pause was added to prevent.
    if (g.state != GoalState.active ||
        minor <= 0 ||
        needed <= 0 ||
        minor > balanceOf(fromAccountId)) {
      return null;
    }
    final capped = minor < needed ? minor : needed;
    final t = Txn(
      kind: TxKind.transfer,
      amountMinor: capped,
      // [on] is when the money moved, for someone catching up a month of
      // saving in one sitting. The ceiling above is still measured against
      // what the account holds *now*, which is the only balance this app
      // computes — backdating a row does not backdate the money.
      day: dayKey(on ?? today()),
      categoryId: _transferCategoryId(),
      accountId: fromAccountId,
      toAccountId: goalsAccount().id,
      note: g.name,
      goalId: g.id,
    );
    addTxn(t);
    return t;
  }

  /// Take [minor] back out of [g], into [toAccountId]. Capped at what the goal
  /// actually holds: a goal cannot hand back money it never had.
  Txn? takeOut(Goal g, int minor, String toAccountId, {DateTime? on}) {
    final capped = minor.clamp(0, statusOf(g).saved);
    if (capped <= 0) return null;
    final t = Txn(
      kind: TxKind.transfer,
      amountMinor: capped,
      day: dayKey(on ?? today()),
      categoryId: _transferCategoryId(),
      accountId: goalsAccount().id,
      toAccountId: toAccountId,
      note: g.name,
      goalId: g.id,
    );
    addTxn(t);
    return t;
  }

  /// What [g] has in it, and how far along that is.
  ///
  /// Summed from the ledger rather than read off the goal, so the rows are the
  /// only record: delete a contribution in the ledger and the goal is smaller,
  /// with nothing to reconcile.
  ///
  /// ponytail: one pass over the ledger per goal, like [balanceOf]. Cache per
  /// (goal, txns.length) if a very long ledger ever makes the page stutter.
  ({int saved, int remaining, double progress, bool reached}) statusOf(Goal g) {
    final vault = goalsAccountOrNull?.id;
    var saved = 0;
    if (vault != null) {
      for (final t in txns) {
        if (t.goalId != g.id || t.kind != TxKind.transfer) continue;
        if (t.toAccountId == vault) {
          saved += t.amountMinor;
        } else if (t.accountId == vault) {
          saved -= t.amountMinor;
        }
      }
    }
    if (saved < 0) saved = 0;
    final remaining = g.targetMinor - saved;
    return (
      saved: saved,
      remaining: remaining > 0 ? remaining : 0,
      // A target of zero is a hand-edited file, not a goal already done.
      progress: g.targetMinor <= 0
          ? 0.0
          : (saved / g.targetMinor).clamp(0.0, 1.0),
      reached: g.targetMinor > 0 && saved >= g.targetMinor,
    );
  }

  /// Everything sitting in the goals account. The overview subtracts it from
  /// the balance to say what is actually free to spend.
  int get totalSetAside {
    final vault = goalsAccountOrNull;
    return vault == null ? 0 : balanceOf(vault.id);
  }

  /// What the goals claim beyond what the goals account actually holds.
  ///
  /// The two are summed from the same rows and normally agree. They can come
  /// apart in one direction: money leaves the goals account without the goal
  /// that was counting it knowing — an expense entered against it directly,
  /// which nothing in the app offers any more, or an imported backup edited by
  /// hand, which is read as it is given because dropping a row loses money.
  /// [statusOf] floors each goal at zero, so the page keeps drawing; this is
  /// the figure that says the drawing is wrong.
  ///
  /// The other direction is not a fault and is not reported: deleting a goal
  /// leaves its money in the account on purpose, so a balance larger than the
  /// goals claim is the designed state, not a discrepancy.
  int get goalsShortfall {
    var claimed = 0;
    for (final g in goals) {
      claimed += statusOf(g).saved;
    }
    final held = totalSetAside;
    return claimed > held ? claimed - held : 0;
  }

  /// The milestone worth celebrating for [g] right now, or null.
  ///
  /// Every milestone at or below where the goal stands is claimed, and only
  /// the highest newly claimed one is returned — so a goal that goes from
  /// nothing to full in one contribution celebrates once rather than four
  /// times, and taking money back out and putting it in again does not replay
  /// a moment that has already been seen.
  int? claimMilestone(Goal g) {
    final progress = statusOf(g).progress;
    int? top;
    for (final m in const [25, 50, 75, 100]) {
      if (progress * 100 >= m && claimMoment('goal-${g.id}-$m')) top = m;
    }
    return top;
  }

  /// Save after a caller has mutated a model object in place — the edit sheet
  /// writes straight onto the row it was handed. Re-sorts because an edit can
  /// change a transaction's day.
  void touch() {
    _sort();
    _commit();
  }

  /// Archiving rather than deleting: a category with history behind it cannot
  /// be removed without orphaning rows, and "I don't use this any more" is the
  /// thing people actually mean.
  void setCategoryArchived(Category c, bool value) {
    c.archived = value;
    _commit();
  }

  void setAccountArchived(Account a, bool value) {
    a.archived = value;
    _commit();
  }

  /// Pause, archive or bring a goal back. Nothing moves: the money sits in the
  /// goals account either way, and the ledger is untouched.
  void setGoalState(Goal g, GoalState state) {
    g.state = state;
    _commit();
  }

  // ── Backup ────────────────────────────────────────────────────────────────

  String exportJson() => jsonEncode({
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'accounts': [for (final a in accounts) a.toJson()],
    'categories': [for (final c in categories) c.toJson()],
    'txns': [for (final t in txns) t.toJson()],
    'rules': [for (final r in rules) r.toJson()],
    'shortcuts': [for (final s in shortcuts) s.toJson()],
    'goals': [for (final g in goals) g.toJson()],
  });

  /// Replace everything with [raw]. Returns false and changes nothing if the
  /// file cannot be read — decoding happens before any list is cleared.
  bool importJson(String raw) {
    try {
      final doc = _decode(raw);
      _adopt(doc);
      _commit();
      return true;
    } catch (e) {
      debugPrint('import: rejected ($e)');
      return false;
    }
  }
}

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

  static TxKind parse(String? s) =>
      TxKind.values.firstWhere((k) => k.name == s, orElse: () => TxKind.expense);
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
    String? createdAt,
  })  : id = id ?? newId(),
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
  }) : id = id ?? newId();

  final String id;
  String name;
  String icon;
  int color;

  /// What was in the account the day tracking started. Signed: an account can
  /// legitimately open in the red (a credit card).
  int openingBalanceMinor;
  bool archived;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'opening': openingBalanceMinor,
        if (archived) 'archived': true,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Account',
        icon: j['icon'] as String? ?? 'wallet',
        color: (j['color'] as num?)?.toInt() ?? defaultCatColor,
        openingBalanceMinor: (j['opening'] as num?)?.toInt() ?? 0,
        archived: j['archived'] as bool? ?? false,
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

  ThemeMode themeMode = ThemeMode.light;
  bool onboarded = false;
  bool loaded = false;

  /// Celebrations already shown today, by key. Reopening the app must not
  /// replay a moment the person already saw.
  final Map<String, String> _moments = {};

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[
        (prefs.getInt(_themeKey) ?? ThemeMode.light.index).clamp(0, 2)];
    onboarded = prefs.getBool(_onboardedKey) ?? false;

    final rawMoments = prefs.getString(_momentsKey);
    if (rawMoments != null) {
      try {
        (jsonDecode(rawMoments) as Map).forEach(
            (k, v) => _moments[k as String] = v as String);
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
  }) _decode(String raw) {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    List<T> read<T>(String key, T Function(Map<String, dynamic>) from) =>
        [
          for (final e in (doc[key] as List? ?? const []))
            from(e as Map<String, dynamic>)
        ];

    return (
      accounts: read('accounts', Account.fromJson),
      categories: read('categories', Category.fromJson),
      txns: read('txns', Txn.fromJson),
      rules: read('rules', Rule.fromJson),
    );
  }

  void _adopt(
      ({
        List<Account> accounts,
        List<Category> categories,
        List<Txn> txns,
        List<Rule> rules,
      }) doc) {
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
    _repair();
    _sort();
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
            name: 'Uncategorised', kind: TxKind.expense, icon: 'circle');
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

    rules.removeWhere((r) =>
        !accountIds.contains(r.accountId) || !categoryIds.contains(r.categoryId));
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
    SharedPreferences.getInstance()
        .then((p) => p.setString(_ledgerKey, exportJson()));
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
      Account(name: 'Card', icon: 'credit-card', color: 12),
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
      categories
          .add(Category(name: name, kind: TxKind.expense, icon: icon, color: color));
    }
    for (final (name, icon, color) in incomes) {
      categories
          .add(Category(name: name, kind: TxKind.income, icon: icon, color: color));
    }
    _commit();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  /// True the first time [key] is claimed today. Persisted, so a relaunch does
  /// not replay a celebration.
  bool claimMoment(String key) {
    final now = dayKey(today());
    if (_moments[key] == now) return false;
    _moments[key] = now;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_momentsKey, jsonEncode(_moments)));
    return true;
  }

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
          if (c.kind == kind && !c.archived) c
      ];

  List<Account> get liveAccounts => [
        for (final a in accounts)
          if (!a.archived) a
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

  void removeRule(Rule r) {
    rules.removeWhere((x) => x.id == r.id);
    _commit();
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

  // ── Backup ────────────────────────────────────────────────────────────────

  String exportJson() => jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'accounts': [for (final a in accounts) a.toJson()],
        'categories': [for (final c in categories) c.toJson()],
        'txns': [for (final t in txns) t.toJson()],
        'rules': [for (final r in rules) r.toJson()],
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

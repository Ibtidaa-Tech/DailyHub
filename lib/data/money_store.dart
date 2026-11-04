import '../core/currencies.dart';
import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

String monthKeyOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime monthStart(String key) {
  final p = key.split('-');
  return DateTime(int.tryParse(p[0]) ?? 2000, int.tryParse(p.length > 1 ? p[1] : '1') ?? 1);
}

String shiftMonth(String key, int delta) {
  final d = monthStart(key);
  return monthKeyOf(DateTime(d.year, d.month + delta));
}

class MonthTotals {
  final double income;
  final double expense;
  final int count;
  const MonthTotals(this.income, this.expense, this.count);
  double get saved => income - expense;
  double get rate => income <= 0 ? 0 : (saved / income).clamp(-9.99, 1).toDouble();
}

class CatAmount {
  final Category category;
  final double amount;
  final int count;
  const CatAmount(this.category, this.amount, this.count);
}

class PersonBalance {
  final String person;
  final double net; // + they owe you, − you owe them
  final List<Debt> items;
  const PersonBalance(this.person, this.net, this.items);
}

/// Everything money: transactions, accounts, categories, budgets, recurring
/// bills, lend/borrow ledger and savings goals. All personal (never shared).
class MoneyStore extends LiveStore {
  MoneyStore() {
    bind();
  }

  final DbService _db = DbService.instance;

  List<Txn> txns = [];
  List<Account> accounts = [];
  List<Category> categories = [];
  List<Budget> budgets = [];
  List<Bill> bills = [];
  List<Debt> debts = [];
  List<SavingsGoal> goals = [];
  Map<String, dynamic>? _prefs;
  bool _prefsLoaded = false;
  bool _catsLoaded = false;
  bool _seeding = false;

  void bind() {
    cancelAll();
    watch('txns', _db.stream('txns'), (List<Map<String, dynamic>> v) {
      txns = v.map(Txn.fromMap).toList()..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    });
    watch('accounts', _db.stream('accounts'), (List<Map<String, dynamic>> v) {
      accounts = v.map(Account.fromMap).toList()..sort((a, b) => a.order.compareTo(b.order));
    });
    watch('categories', _db.stream('categories'), (List<Map<String, dynamic>> v) {
      categories = v.map(Category.fromMap).toList()..sort((a, b) => a.order.compareTo(b.order));
      _catsLoaded = true;
      _maybeSeed();
    });
    watch('budgets', _db.stream('budgets'), (List<Map<String, dynamic>> v) {
      budgets = v.map(Budget.fromMap).toList();
    });
    watch('bills', _db.stream('bills'), (List<Map<String, dynamic>> v) {
      bills = v.map(Bill.fromMap).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
    });
    watch('debts', _db.stream('debts'), (List<Map<String, dynamic>> v) {
      debts = v.map(Debt.fromMap).toList()..sort((a, b) => b.date.compareTo(a.date));
    });
    watch('goals', _db.stream('goals'), (List<Map<String, dynamic>> v) {
      goals = v.map(SavingsGoal.fromMap).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    watch('prefs', _db.watch('prefs'), (Map<String, dynamic>? v) {
      _prefs = v;
      _prefsLoaded = true;
      _maybeSeed();
    });
  }

  // ------------------------------------------------------------ seeding

  static const List<(String, String, int)> defaultExpense = [
    ('food', '🍔', 6),
    ('groceries', '🛒', 1),
    ('transport', '🚕', 0),
    ('fuel', '⛽', 7),
    ('shopping', '🛍️', 8),
    ('bills', '💡', 2),
    ('rent', '🏠', 4),
    ('health', '💊', 3),
    ('education', '📚', 5),
    ('entertainment', '🎬', 4),
    ('travel', '✈️', 5),
    ('personal', '💇', 8),
    ('gifts', '🎁', 3),
    ('emi', '🏦', 7),
    ('subscriptions', '📺', 0),
    ('family', '👨‍👩‍👧', 9),
    ('other', '📦', 7),
  ];

  static const List<(String, String, int)> defaultIncome = [
    ('salary', '💼', 1),
    ('business', '🏪', 0),
    ('freelance', '💻', 4),
    ('interest', '📈', 5),
    ('gift_in', '🎁', 3),
    ('refund', '↩️', 7),
    ('rental', '🏘️', 9),
    ('other_in', '💰', 2),
  ];

  void _maybeSeed() {
    if (_seeding || !_catsLoaded || !_prefsLoaded) return;
    if (categories.isNotEmpty || _prefs?['moneySeeded'] == true) return;
    _seeding = true;
    final paths = <String, dynamic>{};
    var i = 0;
    for (final c in defaultExpense) {
      paths['categories/${c.$1}'] =
          Category(key: c.$1, kind: 'expense', emoji: c.$2, color: c.$3, order: i++).toMap();
    }
    i = 0;
    for (final c in defaultIncome) {
      paths['categories/${c.$1}'] =
          Category(key: c.$1, kind: 'income', emoji: c.$2, color: c.$3, order: i++).toMap();
    }
    if (accounts.isEmpty) {
      paths['accounts/cash'] = Account(name: '', kind: 'cash', emoji: '💵', color: 1, order: 0).toMap();
      paths['accounts/bank'] = Account(name: '', kind: 'bank', emoji: '🏦', color: 0, order: 1).toMap();
      if (Money.current.code == 'INR') {
        paths['accounts/upi'] = Account(name: '', kind: 'upi', emoji: '📱', color: 4, order: 2).toMap();
      } else {
        paths['accounts/card'] = Account(name: '', kind: 'card', emoji: '💳', color: 4, order: 2).toMap();
      }
    }
    paths['prefs/moneySeeded'] = true;
    _db.updateRoot(paths);
  }

  // ------------------------------------------------------------ lookups

  Category? catById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Account? accountById(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<Category> categoriesOf(String kind) =>
      categories.where((c) => c.kind == kind && !c.archived).toList();

  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();

  String get defaultAccountId {
    final a = activeAccounts;
    if (a.isEmpty) return '';
    for (final x in a) {
      if (x.kind == 'upi') return x.id;
    }
    return a.first.id;
  }

  /// Guesses a category from free text ("uber" → transport).
  String guessCategory(String text, String kind) {
    final t = text.toLowerCase();
    const map = {
      'food': ['lunch', 'dinner', 'breakfast', 'food', 'restaurant', 'cafe', 'coffee', 'tea', 'chai', 'pizza', 'burger', 'swiggy', 'zomato', 'snack', 'biryani', 'meal', 'khana', 'nashta'],
      'groceries': ['grocery', 'groceries', 'vegetable', 'sabzi', 'milk', 'doodh', 'fruit', 'bigbasket', 'blinkit', 'zepto', 'kirana', 'supermarket', 'dmart'],
      'transport': ['uber', 'ola', 'rapido', 'auto', 'cab', 'taxi', 'metro', 'bus', 'train', 'ticket', 'parking', 'toll'],
      'fuel': ['petrol', 'diesel', 'fuel', 'cng', 'gas station'],
      'shopping': ['amazon', 'flipkart', 'myntra', 'clothes', 'shoes', 'shopping', 'meesho', 'ajio'],
      'bills': ['electricity', 'bill', 'recharge', 'wifi', 'internet', 'broadband', 'water', 'gas', 'mobile', 'dth', 'bijli'],
      'rent': ['rent', 'kiraya', 'maintenance'],
      'health': ['medicine', 'doctor', 'hospital', 'pharmacy', 'medical', 'dawai', 'gym', 'clinic'],
      'education': ['fees', 'fee', 'book', 'course', 'tuition', 'college', 'school', 'exam'],
      'entertainment': ['movie', 'netflix', 'game', 'concert', 'party', 'outing'],
      'travel': ['hotel', 'flight', 'trip', 'holiday', 'airbnb', 'booking'],
      'subscriptions': ['subscription', 'spotify', 'prime', 'hotstar', 'youtube premium', 'icloud'],
      'emi': ['emi', 'loan', 'installment'],
      'gifts': ['gift', 'birthday', 'wedding', 'shagun'],
      'salary': ['salary', 'payroll', 'stipend', 'tankhwah'],
      'freelance': ['freelance', 'client', 'project', 'invoice'],
      'interest': ['interest', 'dividend', 'fd', 'returns'],
      'refund': ['refund', 'cashback', 'reversal'],
      'business': ['sale', 'sales', 'business', 'shop'],
    };
    for (final e in map.entries) {
      final cat = catById(e.key);
      if (cat == null || cat.kind != kind || cat.archived) continue;
      if (e.value.any((w) => t.contains(w))) return e.key;
    }
    // Custom categories: match their name.
    for (final c in categoriesOf(kind)) {
      if (c.name.isNotEmpty && t.contains(c.name.toLowerCase())) return c.id;
    }
    final fallback = kind == 'income' ? 'other_in' : 'other';
    if (catById(fallback) != null) return fallback;
    final list = categoriesOf(kind);
    return list.isEmpty ? '' : list.last.id;
  }

  // ------------------------------------------------------------ totals

  List<Txn> monthTxns(String month) =>
      memo('m:$month', () => txns.where((t) => t.monthKey == month).toList());

  MonthTotals totals(String month) => memo('tot:$month', () {
        double inc = 0, exp = 0;
        var n = 0;
        for (final t in monthTxns(month)) {
          if (t.isIncome) inc += t.amount;
          if (t.isExpense) exp += t.amount;
          n++;
        }
        return MonthTotals(inc, exp, n);
      });

  MonthTotals rangeTotals(DateTime from, DateTime to) {
    double inc = 0, exp = 0;
    var n = 0;
    for (final t in txns) {
      final d = t.day;
      if (d.isBefore(dateOnly(from)) || d.isAfter(dateOnly(to))) continue;
      if (t.isIncome) inc += t.amount;
      if (t.isExpense) exp += t.amount;
      n++;
    }
    return MonthTotals(inc, exp, n);
  }

  double spentOn(DateTime day) => txns
      .where((t) => t.isExpense && sameDay(t.day, day))
      .fold(0.0, (s, t) => s + t.amount);

  List<CatAmount> byCategory(String month, String kind) => memo('bycat:$month:$kind', () {
        final sums = <String, double>{};
        final counts = <String, int>{};
        for (final t in monthTxns(month)) {
          if (t.type != kind) continue;
          sums[t.category] = (sums[t.category] ?? 0.0) + t.amount;
          counts[t.category] = (counts[t.category] ?? 0) + 1;
        }
        final out = sums.entries
            .map((e) => CatAmount(
                catById(e.key) ?? Category(id: e.key, key: kind == 'income' ? 'other_in' : 'other', kind: kind),
                e.value,
                counts[e.key] ?? 0))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
        return out;
      });

  /// Expense per day of [month] (index 0 = 1st).
  List<double> dailyExpense(String month) => memo('daily:$month', () {
        final start = monthStart(month);
        final n = daysInMonth(start.year, start.month);
        final out = List<double>.filled(n, 0);
        for (final t in monthTxns(month)) {
          if (!t.isExpense) continue;
          final i = t.day.day - 1;
          if (i >= 0 && i < n) out[i] += t.amount;
        }
        return out;
      });

  /// Income/expense for the last [n] months ending at [endMonth].
  List<(String, MonthTotals)> trend(String endMonth, int n) {
    final out = <(String, MonthTotals)>[];
    for (var i = n - 1; i >= 0; i--) {
      final m = shiftMonth(endMonth, -i);
      out.add((m, totals(m)));
    }
    return out;
  }

  double accountBalance(String id) => memo('bal:$id', () {
        final acc = accountById(id);
        var bal = acc?.opening ?? 0.0;
        for (final t in txns) {
          if (t.isIncome && t.account == id) bal += t.amount;
          if (t.isExpense && t.account == id) bal -= t.amount;
          if (t.isTransfer) {
            if (t.account == id) bal -= t.amount;
            if (t.toAccount == id) bal += t.amount;
          }
        }
        return bal;
      });

  double get netWorth => memo('net', () =>
      activeAccounts.fold(0.0, (s, a) => s + accountBalance(a.id)));

  // ------------------------------------------------------------ budgets

  Budget? budgetFor(String category) {
    for (final b in budgets) {
      if (b.category == category) return b;
    }
    return null;
  }

  /// Overall monthly budget: explicit total, else the sum of category caps.
  double get monthlyBudget {
    final t = budgetFor('_total');
    if (t != null && t.limit > 0) return t.limit;
    return budgets.where((b) => b.category != '_total').fold(0.0, (s, b) => s + b.limit);
  }

  double spentInCategory(String month, String cat) => monthTxns(month)
      .where((t) => t.isExpense && t.category == cat)
      .fold(0.0, (s, t) => s + t.amount);

  // -------------------------------------------------------------- bills

  List<Bill> get activeBills => bills.where((b) => b.active).toList()
    ..sort((a, b) => a.due.compareTo(b.due));

  List<Bill> billsDueWithin(int days) =>
      activeBills.where((b) => b.daysLeft() <= days).toList();

  // -------------------------------------------------------------- debts

  double get toReceive => debts.where((d) => d.isLent).fold(0.0, (s, d) => s + d.remaining);
  double get toPay => debts.where((d) => !d.isLent).fold(0.0, (s, d) => s + d.remaining);

  List<PersonBalance> get people => memo('people', () {
        final map = <String, List<Debt>>{};
        for (final d in debts) {
          final key = d.person.trim().toLowerCase();
          map.putIfAbsent(key, () => []).add(d);
        }
        final out = map.values.map((items) {
          final net = items.fold(0.0, (s, d) => s + (d.isLent ? d.remaining : -d.remaining));
          return PersonBalance(items.first.person.trim(), net, items);
        }).toList()
          ..sort((a, b) => b.net.abs().compareTo(a.net.abs()));
        return out;
      });

  // ------------------------------------------------------------ writes

  String saveTxn(Txn t) {
    if (t.date.isEmpty) t.date = dayKey(DateTime.now());
    if (t.id.isEmpty) return _db.addNow('txns', t.toMap());
    _db.set('txns', t.id, t.toMap());
    return t.id;
  }

  Map<String, dynamic> deleteTxn(Txn t) {
    final data = t.toMap();
    // Optimistic: drop it locally first so swipe-to-delete never flickers.
    txns = txns.where((x) => x.id != t.id).toList();
    invalidate();
    _db.remove('txns', t.id);
    return data;
  }

  void restore(String collection, String id, Map<String, dynamic> data) =>
      _db.set(collection, id, data);

  String saveAccount(Account a) {
    if (a.id.isEmpty) {
      a.order = accounts.length;
      return _db.addNow('accounts', a.toMap());
    }
    _db.set('accounts', a.id, a.toMap());
    return a.id;
  }

  /// Accounts with history are archived rather than deleted.
  void deleteAccount(Account a) {
    final used = txns.any((t) => t.account == a.id || t.toAccount == a.id);
    if (used) {
      _db.update('accounts', a.id, {'archived': true});
    } else {
      _db.remove('accounts', a.id);
    }
  }

  String saveCategory(Category c) {
    if (c.id.isEmpty) {
      c.order = categoriesOf(c.kind).length;
      return _db.addNow('categories', c.toMap());
    }
    _db.set('categories', c.id, c.toMap());
    return c.id;
  }

  void deleteCategory(Category c) {
    final used = txns.any((t) => t.category == c.id);
    if (used) {
      _db.update('categories', c.id, {'archived': true});
    } else {
      _db.remove('categories', c.id);
    }
  }

  void setBudget(String category, double limit) {
    final b = budgetFor(category);
    if (limit <= 0) {
      if (b != null) _db.remove('budgets', b.id);
      return;
    }
    final data = Budget(category: category, limit: limit).toMap();
    if (b == null) {
      _db.addNow('budgets', data);
    } else {
      _db.set('budgets', b.id, data);
    }
  }

  String saveBill(Bill b) {
    if (b.freq == 'monthly' || b.freq == 'quarterly' || b.freq == 'yearly') {
      b.anchor = b.dueDate?.day ?? b.anchor;
    }
    if (b.id.isEmpty) return _db.addNow('bills', b.toMap());
    _db.set('bills', b.id, b.toMap());
    return b.id;
  }

  void deleteBill(Bill b) => _db.remove('bills', b.id);

  /// Logs the payment as a transaction and moves the bill to its next date.
  String markBillPaid(Bill b, {double? amount, String? account, DateTime? on}) {
    final day = on ?? DateTime.now();
    final id = saveTxn(Txn(
      type: b.type,
      amount: amount ?? b.amount,
      category: b.category,
      note: b.name,
      date: dayKey(day),
      time: hmOf(DateTime.now()),
      account: account ?? (b.account.isEmpty ? defaultAccountId : b.account),
      billId: b.id,
    ));
    final due = b.dueDate ?? todayDate();
    final next = nextOccurrence(due, b.freq, anchorDay: b.anchor > 0 ? b.anchor : null);
    _db.update('bills', b.id, {'due': dayKey(next), 'lastPaid': dayKey(day)});
    return id;
  }

  void skipBill(Bill b) {
    final due = b.dueDate ?? todayDate();
    final next = nextOccurrence(due, b.freq, anchorDay: b.anchor > 0 ? b.anchor : null);
    _db.update('bills', b.id, {'due': dayKey(next)});
  }

  String saveDebt(Debt d) {
    if (d.date.isEmpty) d.date = dayKey(DateTime.now());
    if (d.id.isEmpty) return _db.addNow('debts', d.toMap());
    _db.set('debts', d.id, d.toMap());
    return d.id;
  }

  Map<String, dynamic> deleteDebt(Debt d) {
    final data = d.toMap();
    _db.remove('debts', d.id);
    return data;
  }

  void addDebtPayment(Debt d, double amount, {String note = ''}) {
    final payments = [
      ...d.payments,
      {'amount': amount, 'date': dayKey(DateTime.now()), 'note': note},
    ];
    final paid = payments.fold(0.0, (s, p) => s + toD(p['amount']));
    _db.update('debts', d.id, {
      'payments': payments,
      'settled': paid >= d.amount - 0.001,
    });
  }

  void settleDebt(Debt d, bool settled) => _db.update('debts', d.id, {'settled': settled});

  String saveGoal(SavingsGoal g) {
    if (g.id.isEmpty) return _db.addNow('goals', g.toMap());
    _db.set('goals', g.id, g.toMap());
    return g.id;
  }

  void deleteGoal(SavingsGoal g) => _db.remove('goals', g.id);

  void addGoalEntry(SavingsGoal g, double amount, {String note = ''}) {
    _db.update('goals', g.id, {
      'entries': [
        ...g.entries,
        {'amount': amount, 'date': dayKey(DateTime.now()), 'note': note},
      ],
    });
  }
}

import '../services/db_service.dart';
import 'models.dart';
import 'store_base.dart';

/// Aisles, so a long list sorts itself into the order you actually shop in.
/// Keys are stable; the UI translates them.
const List<(String, String)> kAisles = [
  ('produce', '🥬'),
  ('dairy', '🥛'),
  ('bakery', '🍞'),
  ('staples', '🌾'),
  ('snacks', '🍪'),
  ('drinks', '🧃'),
  ('frozen', '🧊'),
  ('meat', '🍗'),
  ('household', '🧹'),
  ('personal', '🧴'),
  ('baby', '🍼'),
  ('other', '🛒'),
];

String aisleEmoji(String key) {
  for (final a in kAisles) {
    if (a.$1 == key) return a.$2;
  }
  return '🛒';
}

/// Guesses an aisle from the item name, so nobody has to file things by hand.
String guessAisle(String name) {
  final n = name.toLowerCase();
  const map = {
    'produce': ['tomato', 'onion', 'potato', 'apple', 'banana', 'spinach', 'palak', 'aloo', 'pyaz',
      'fruit', 'veg', 'sabzi', 'lemon', 'nimbu', 'carrot', 'gajar', 'mirchi', 'dhania', 'adrak', 'ginger', 'garlic', 'lehsun'],
    'dairy': ['milk', 'doodh', 'curd', 'dahi', 'paneer', 'cheese', 'butter', 'makhan', 'ghee', 'yogurt', 'cream'],
    'bakery': ['bread', 'pav', 'bun', 'cake', 'rusk', 'biscuit', 'cookie', 'croissant'],
    'staples': ['rice', 'chawal', 'atta', 'flour', 'dal', 'pulse', 'sugar', 'cheeni', 'salt', 'namak',
      'oil', 'tel', 'masala', 'spice', 'besan', 'poha', 'suji', 'maida'],
    'snacks': ['chips', 'namkeen', 'chocolate', 'candy', 'kurkure', 'popcorn', 'nuts', 'dry fruit'],
    'drinks': ['juice', 'cola', 'soda', 'water', 'tea', 'chai', 'coffee', 'beer', 'drink'],
    'frozen': ['frozen', 'ice cream', 'peas', 'matar'],
    'meat': ['chicken', 'mutton', 'fish', 'egg', 'anda', 'prawn', 'meat'],
    'household': ['detergent', 'soap bar', 'surf', 'harpic', 'phenyl', 'broom', 'mop', 'tissue',
      'garbage', 'bag', 'bulb', 'battery', 'dishwash', 'vim'],
    'personal': ['shampoo', 'toothpaste', 'brush', 'razor', 'cream', 'lotion', 'sanitary',
      'pad', 'deodorant', 'perfume', 'soap'],
    'baby': ['diaper', 'baby', 'formula', 'wipes'],
  };
  for (final e in map.entries) {
    for (final w in e.value) {
      if (n.contains(w)) return e.key;
    }
  }
  return 'other';
}

/// One thing to buy.
class ShopItem {
  final String id;
  final Map<String, dynamic> raw;
  String name;
  String qty; // free text: "2 kg", "1 packet"
  double price;
  String aisle;
  String list;
  bool bought;

  ShopItem({
    this.id = '',
    Map<String, dynamic>? raw,
    this.name = '',
    this.qty = '',
    this.price = 0,
    this.aisle = 'other',
    this.list = '',
    this.bought = false,
  }) : raw = raw ?? {};

  factory ShopItem.from(Map<String, dynamic> m) {
    final name = str(m['name']);
    final aisle = str(m['aisle']);
    return ShopItem(
      id: str(m['id']),
      raw: m,
      name: name,
      qty: str(m['qty']),
      price: toD(m['price']),
      aisle: aisle.isEmpty ? guessAisle(name) : aisle,
      list: str(m['list']),
      bought: toB(m['bought']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'qty': qty,
        'price': price,
        'aisle': aisle,
        'list': list,
        'bought': bought,
      };
}

/// Shopping lists, shared with whoever you share your workspace with.
class ShoppingStore extends LiveStore {
  ShoppingStore() {
    bind();
  }

  final DbService _db = DbService.instance;
  List<ShopItem> items = [];

  void bind() {
    cancelAll();
    watch('shopping', _db.stream('shopping', workspace: true), (List<Map<String, dynamic>> v) {
      items = v.map(ShopItem.from).toList();
    });
    invalidate();
  }

  /// Every list name in use, most-used first, with the default one included.
  List<String> get lists {
    final counts = <String, int>{};
    for (final i in items) {
      final l = i.list.trim();
      counts[l] = (counts[l] ?? 0) + 1;
    }
    final names = counts.keys.where((e) => e.isNotEmpty).toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    if (items.any((i) => i.list.trim().isEmpty)) names.insert(0, '');
    return names;
  }

  List<ShopItem> inList(String list) =>
      items.where((i) => i.list.trim() == list.trim()).toList();

  List<ShopItem> pendingIn(String list) => inList(list).where((i) => !i.bought).toList();

  /// Items grouped by aisle, in shopping order, pending before bought.
  List<(String aisle, List<ShopItem> items)> grouped(String list) {
    final byAisle = <String, List<ShopItem>>{};
    for (final i in inList(list)) {
      byAisle.putIfAbsent(i.aisle, () => []).add(i);
    }
    final out = <(String, List<ShopItem>)>[];
    for (final a in kAisles) {
      final group = byAisle[a.$1];
      if (group == null || group.isEmpty) continue;
      group.sort((x, y) {
        if (x.bought != y.bought) return x.bought ? 1 : -1;
        return x.name.toLowerCase().compareTo(y.name.toLowerCase());
      });
      out.add((a.$1, group));
    }
    return out;
  }

  /// Total of what's still to buy, and of what's in the basket.
  (double pending, double basket) totals(String list) {
    var p = 0.0, b = 0.0;
    for (final i in inList(list)) {
      if (i.bought) {
        b += i.price;
      } else {
        p += i.price;
      }
    }
    return (p, b);
  }

  /// Names bought before, for one-tap re-adding.
  List<String> frequent(String list, {int limit = 12}) {
    final counts = <String, int>{};
    for (final i in items) {
      final n = i.name.trim();
      if (n.isEmpty) continue;
      counts[n] = (counts[n] ?? 0) + 1;
    }
    final present = pendingIn(list).map((e) => e.name.toLowerCase()).toSet();
    final names = counts.keys.where((n) => !present.contains(n.toLowerCase())).toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return names.take(limit).toList();
  }

  // -------------------------------------------------------------- writes

  String save(ShopItem i) {
    if (i.id.isEmpty) {
      final id = _db.newId('shopping', workspace: true);
      _db.set('shopping', id, i.toMap(), workspace: true);
      return id;
    }
    _db.set('shopping', i.id, i.toMap(), workspace: true);
    return i.id;
  }

  void toggle(ShopItem i) {
    i.bought = !i.bought;
    invalidate();
    _db.update('shopping', i.id, {'bought': i.bought}, workspace: true);
  }

  Map<String, dynamic> delete(ShopItem i) {
    final data = Map<String, dynamic>.from(i.raw)..remove('id');
    items = items.where((x) => x.id != i.id).toList();
    invalidate();
    _db.remove('shopping', i.id, workspace: true);
    return data;
  }

  void restore(String id, Map<String, dynamic> data) =>
      _db.set('shopping', id, data, workspace: true);

  /// Removes everything already in the basket. Returns them so it can be undone.
  List<ShopItem> clearBought(String list) {
    final gone = inList(list).where((i) => i.bought).toList();
    items = items.where((i) => !(i.list.trim() == list.trim() && i.bought)).toList();
    invalidate();
    for (final i in gone) {
      _db.remove('shopping', i.id, workspace: true);
    }
    return gone;
  }

  void restoreAll(List<ShopItem> gone) {
    for (final i in gone) {
      final data = Map<String, dynamic>.from(i.raw)..remove('id');
      _db.set('shopping', i.id, data.isEmpty ? i.toMap() : data, workspace: true);
    }
  }

  void renameList(String from, String to) {
    for (final i in inList(from)) {
      _db.update('shopping', i.id, {'list': to.trim()}, workspace: true);
    }
  }
}

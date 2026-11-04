import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/shopping_store.dart';
import '../../ui/kit.dart';
import '../money/txn_editor.dart';

String aisleName(BuildContext context, String key) => context.t('aisle_$key');

/// Shared shopping lists, grouped by aisle with a running total.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  String _list = '';
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _quickAdd(ShoppingStore s, {String? name}) {
    final text = (name ?? _add.text).trim();
    if (text.isEmpty) return;
    // "2 kg tomato" / "tomato 2 kg" — pull a leading quantity out of the name.
    final m = RegExp(r'^(\d+(?:\.\d+)?\s*(?:kg|g|gm|l|ml|pc|pcs|packet|pkt|dozen|box)?)\s+(.+)$',
            caseSensitive: false)
        .firstMatch(text);
    final qty = m == null ? '' : m.group(1)!.trim();
    final itemName = m == null ? text : m.group(2)!.trim();
    s.save(ShopItem(
      name: itemName,
      qty: qty,
      aisle: guessAisle(itemName),
      list: _list,
    ));
    _add.clear();
    if (name == null) _addFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ShoppingStore>();
    final ws = context.watch<WorkspaceProvider>();
    final lists = [...s.lists];
    // A list the user just created has no items yet, so keep it selectable.
    if (_list.isNotEmpty && !lists.contains(_list)) lists.add(_list);
    if (lists.isNotEmpty && !lists.contains(_list)) _list = lists.first;
    final groups = s.grouped(_list);
    final pending = s.pendingIn(_list).length;
    final (pendingTotal, basketTotal) = s.totals(_list);
    final frequent = s.frequent(_list);

    return AppPage(
      title: context.t('m_shopping'),
      subtitle: context.t('shop_sub'),
      actions: [
        if (ws.canEdit)
          IconButton(
            tooltip: context.t('shop_lists'),
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => _manageLists(context, s, lists),
          ),
      ],
      header: lists.length > 1
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ChipRow<String>(
                items: [for (final l in lists) (l, l.isEmpty ? context.t('shop_default_list') : l)],
                value: _list,
                onSelected: (v) => setState(() => _list = v),
              ),
            )
          : null,
      bottomBar: ws.canAdd ? _addBar(context, s) : null,
      slivers: [
        if (groups.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.shopping_cart_outlined,
              color: AppColors.mShopping,
              title: context.t('shop_empty'),
              message: context.t('shop_empty_msg'),
            ),
          )
        else ...[
          if (pendingTotal > 0 || basketTotal > 0)
            SliverToBoxAdapter(child: _Totals(pending: pendingTotal, basket: basketTotal, left: pending)),
          for (final g in groups) ...[
            SliverToBoxAdapter(
              child: SectionTitle('${aisleEmoji(g.$1)}  ${aisleName(context, g.$1)}'),
            ),
            SliverList.list(
              children: [
                for (final i in g.$2)
                  ShopRow(
                    item: i,
                    canEdit: ws.canAdd,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      s.toggle(i);
                    },
                    onEdit: () => editShopItem(context, item: i, list: _list),
                    onDelete: () {
                      final data = s.delete(i);
                      showUndo(context, context.t('shop_removed'), () => s.restore(i.id, data));
                    },
                  ),
              ],
            ),
          ],
        ],
        if (frequent.isNotEmpty && ws.canAdd) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('shop_add_again'))),
          SliverToBoxAdapter(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in frequent)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: Text(n),
                  onPressed: () => _quickAdd(s, name: n),
                ),
            ]),
          ),
        ],
        if (s.inList(_list).any((i) => i.bought) && ws.canEdit)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                if (basketTotal > 0 && context.read<AppSettings>().isOn('money'))
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    label: Text(context.tr('shop_log_expense', {'a': Money.format(basketTotal)})),
                    onPressed: () => _logExpense(context, s, basketTotal),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18),
                  label: Text(context.t('shop_clear_bought')),
                  onPressed: () {
                    final gone = s.clearBought(_list);
                    showUndo(context, context.tr('shop_cleared', {'n': gone.length}),
                        () => s.restoreAll(gone));
                  },
                ),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _addBar(BuildContext context, ShoppingStore s) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _add,
              focusNode: _addFocus,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _quickAdd(s),
              decoration: InputDecoration(
                hintText: context.t('shop_add_hint'),
                prefixIcon: const Icon(Icons.add_shopping_cart_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.arrow_upward_rounded),
            onPressed: () => _quickAdd(s),
          ),
        ]),
      ),
    );
  }

  void _logExpense(BuildContext context, ShoppingStore s, double amount) {
    final money = context.read<MoneyStore>();
    final names = s.inList(_list).where((i) => i.bought).map((e) => e.name).take(4).join(', ');
    openTxnEditor(
      context,
      type: TxnType.expense,
      amount: amount,
      note: names.isEmpty ? context.t('m_shopping') : names,
      category: money.guessCategory(names, 'expense'),
    );
  }

  Future<void> _manageLists(BuildContext context, ShoppingStore s, List<String> lists) async {
    await showAppSheet<void>(context, builder: (ctx) {
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.t('shop_lists'), subtitle: ctx.t('shop_lists_sub')),
          for (final l in lists)
            OptionTile(
              icon: Icons.list_alt_rounded,
              color: AppColors.mShopping,
              title: l.isEmpty ? ctx.t('shop_default_list') : l,
              subtitle: ctx.tn('shop_n_items', s.pendingIn(l).length),
              trailing: l.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.drive_file_rename_outline_rounded),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final name = await promptText(context,
                            title: context.t('shop_rename_list'), initial: l);
                        if (name != null && name.trim().isNotEmpty) {
                          s.renameList(l, name.trim());
                          if (context.mounted) setState(() => _list = name.trim());
                        }
                      },
                    ),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _list = l);
              },
            ),
          OptionTile(
            icon: Icons.add_rounded,
            color: AppColors.mShopping,
            title: ctx.t('shop_new_list'),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await promptText(context, title: context.t('shop_new_list'));
              if (name != null && name.trim().isNotEmpty && context.mounted) {
                setState(() => _list = name.trim());
              }
            },
          ),
          const SizedBox(height: 8),
        ]),
      );
    });
  }
}

class _Totals extends StatelessWidget {
  final double pending;
  final double basket;
  final int left;
  const _Totals({required this.pending, required this.basket, required this.left});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return DhCard(
      child: Row(children: [
        Expanded(
          child: StatBlock(
            label: context.tn('shop_n_left', left),
            value: Money.format(pending),
            color: tk.textMuted,
          ),
        ),
        Container(width: 1, height: 34, color: tk.border),
        Expanded(
          child: StatBlock(
            label: context.t('shop_in_basket'),
            value: Money.format(basket),
            color: tk.success,
            align: CrossAxisAlignment.end,
          ),
        ),
      ]),
    );
  }
}

/// One line on the list.
class ShopRow extends StatelessWidget {
  final ShopItem item;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const ShopRow({
    super.key,
    required this.item,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final i = item;
    return SwipeTile(
      swipeKey: ValueKey('shop_${i.id}'),
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: canEdit
          ? () async {
              onDelete();
              return true;
            }
          : null,
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(6, 2, 12, 2),
        onTap: canEdit ? onToggle : null,
        onLongPress: canEdit ? onEdit : null,
        child: Row(children: [
          IconButton(
            icon: Icon(
              i.bought ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: i.bought ? tk.success : tk.textFaint,
            ),
            onPressed: canEdit ? onToggle : null,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                i.name,
                style: context.tt.titleSmall?.copyWith(
                  decoration: i.bought ? TextDecoration.lineThrough : null,
                  color: i.bought ? tk.textFaint : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (i.qty.isNotEmpty)
                Text(i.qty, style: context.tt.bodySmall),
            ]),
          ),
          if (i.price > 0)
            Text(Money.format(i.price),
                style: context.tt.labelLarge?.copyWith(color: i.bought ? tk.textFaint : null)),
        ]),
      ),
    );
  }
}

/// Full editor for quantity, price and aisle.
Future<void> editShopItem(BuildContext context, {ShopItem? item, String list = ''}) async {
  final s = context.read<ShoppingStore>();
  final name = TextEditingController(text: item?.name ?? '');
  final qty = TextEditingController(text: item?.qty ?? '');
  final price = TextEditingController(
      text: (item?.price ?? 0) > 0 ? item!.price.toStringAsFixed(0) : '');
  var aisle = item?.aisle ?? 'other';

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(item == null ? 'shop_add_item' : 'shop_edit_item'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              autofocus: item == null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => set(() => aisle = guessAisle(v)),
              decoration: InputDecoration(
                hintText: ctx.t('shop_item_hint'),
                prefixIcon: const Icon(Icons.shopping_basket_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: qty,
                  decoration: InputDecoration(
                    hintText: ctx.t('shop_qty_hint'),
                    prefixIcon: const Icon(Icons.numbers_rounded, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: ctx.t('shop_price_hint'),
                    prefixText: '${Money.symbol} ',
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text(ctx.t('shop_aisle'), style: ctx.tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in kAisles)
                ChoiceChip(
                  avatar: Text(a.$2),
                  label: Text(aisleName(ctx, a.$1)),
                  selected: aisle == a.$1,
                  onSelected: (_) => set(() => aisle = a.$1),
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              if (item != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(ctx.t('delete')),
                  onPressed: () {
                    final data = s.delete(item);
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      showUndo(context, context.t('shop_removed'), () => s.restore(item.id, data));
                    }
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    showToast(ctx, ctx.t('shop_enter_item'));
                    return;
                  }
                  s.save(ShopItem(
                    id: item?.id ?? '',
                    name: name.text.trim(),
                    qty: qty.text.trim(),
                    price: double.tryParse(price.text.trim()) ?? 0,
                    aisle: aisle,
                    list: item?.list ?? list,
                    bought: item?.bought ?? false,
                  ));
                  Navigator.pop(ctx);
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ]),
        ),
      );
    });
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in [name, qty, price]) {
        c.dispose();
      }
    });
  });
}

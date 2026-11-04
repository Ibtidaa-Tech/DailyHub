import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'money_ui.dart';

const List<String> kCategoryEmojis = [
  '🍔', '🛒', '🚕', '⛽', '🛍️', '💡', '🏠', '💊', '📚', '🎬', '✈️', '💇',
  '🎁', '🏦', '📺', '👨‍👩‍👧', '📦', '☕', '🍺', '🐶', '👶', '🏋️', '🎮', '📱',
  '💻', '🧾', '🚗', '🏍️', '🚌', '🧺', '🧴', '🪴', '🎓', '💍', '🙏', '🎉',
  '💼', '🏪', '📈', '↩️', '🏘️', '💰', '🪙', '🤝', '🎨', '🛠️', '⚕️', '🍕',
];

/// Opens the category editor; returns the saved category id.
Future<String?> editCategory(BuildContext context, {Category? category, String kind = 'expense'}) async {
  final m = context.read<MoneyStore>();
  final name = TextEditingController(text: category == null ? '' : categoryName(context, category));
  var emoji = category?.emoji ?? '📦';
  var color = category?.color ?? m.categories.length;
  final k = category?.kind ?? kind;
  return showAppSheet<String>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(category == null ? 'new_category' : 'edit_category'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              autofocus: category == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t('category_name'),
                prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(emoji, style: const TextStyle(fontSize: 18))),
              ),
            ),
            const SizedBox(height: 14),
            ColorDots(value: color % AppColors.swatches.length, onChanged: (v) => set(() => color = v)),
            const SizedBox(height: 14),
            EmojiGrid(value: emoji, emojis: kCategoryEmojis, onChanged: (v) => set(() => emoji = v)),
            const SizedBox(height: 18),
            Row(children: [
              if (category != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(ctx.t('delete')),
                  onPressed: () {
                    m.deleteCategory(category);
                    Navigator.pop(ctx);
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final text = name.text.trim();
                  if (text.isEmpty) return;
                  final prev = category;
                  // A built-in category keeps its translation key as long as the
                  // user hasn't actually typed a different name.
                  final unchangedDefault =
                      prev != null && prev.key.isNotEmpty && text == categoryName(ctx, prev);
                  final c = Category(
                    id: category?.id ?? '',
                    name: unchangedDefault ? '' : text,
                    key: prev != null && unchangedDefault ? prev.key : '',
                    kind: k,
                    emoji: emoji,
                    color: color,
                    order: category?.order ?? 0,
                  );
                  final id = m.saveCategory(c);
                  Navigator.pop(ctx, id);
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ]),
        ),
      );
    });
  });
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _kind = 'expense';

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final cats = m.categoriesOf(_kind);
    final month = monthKeyOf(DateTime.now());
    final sums = {for (final c in m.byCategory(month, _kind)) c.category.id: c.amount};
    return AppPage(
      title: context.t('m_categories'),
      fab: FloatingActionButton.extended(
        onPressed: () => editCategory(context, kind: _kind),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('new_category')),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: PillTabs<String>(
            items: [('expense', context.t('spent')), ('income', context.t('earned'))],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('this_month'))),
        SliverList.list(children: [
          for (final c in cats)
            DhCard(
              onTap: () => editCategory(context, category: c),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(children: [
                IconBadge(emoji: c.emoji, color: categoryColor(c), size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text(categoryName(context, c), style: context.tt.titleMedium)),
                Text(Money.format(sums[c.id] ?? 0), style: context.tt.labelLarge?.copyWith(color: context.tokens.textMuted)),
              ]),
            ),
        ]),
      ],
    );
  }
}

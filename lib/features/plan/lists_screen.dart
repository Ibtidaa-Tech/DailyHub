import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import 'plan_tiles.dart';
import 'task_editor.dart';

/// Lists (projects) and tags.
class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final ws = context.watch<WorkspaceProvider>();
    return AppPage(
      title: context.t('m_lists'),
      fab: ws.canAdd
          ? FloatingActionButton.extended(
              onPressed: () => editList(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(context.t('new_list')),
            )
          : null,
      slivers: [
        SliverList.list(children: [
          _ListRow(
            emoji: '📥',
            name: context.t('inbox'),
            count: plan.countOpenIn('inbox'),
            color: AppColors.mTasks,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ListDetailScreen(listId: '', title: context.t('inbox')))),
          ),
          for (final l in plan.lists)
            _ListRow(
              emoji: l.emoji,
              name: l.name,
              count: plan.countOpenIn(l.id),
              color: AppColors.swatch(l.color),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ListDetailScreen(listId: l.id, title: '${l.emoji} ${l.name}'))),
              onEdit: ws.canEdit ? () => editList(context, list: l) : null,
            ),
          if (plan.lists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.t('lists_hint'), style: context.tt.bodySmall),
            ),
          if (plan.tags.isNotEmpty) ...[
            SectionTitle(context.t('tags')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final tag in plan.tags)
                ActionChip(
                  avatar: const Icon(Icons.tag_rounded, size: 16),
                  label: Text('$tag · ${plan.withTag(tag).length}'),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ListDetailScreen(tag: tag, title: '#$tag'))),
                ),
            ]),
          ],
        ]),
      ],
    );
  }

  static Future<void> editList(BuildContext context, {TaskList? list}) async {
    final store = context.read<PlanStore>();
    final name = TextEditingController(text: list?.name ?? '');
    var emoji = list?.emoji ?? '📁';
    var color = list?.color ?? store.lists.length % AppColors.swatches.length;
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t(list == null ? 'new_list' : 'edit_list'), style: ctx.tt.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                autofocus: list == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: ctx.t('list_name_hint'),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ColorDots(value: color, onChanged: (v) => set(() => color = v)),
              const SizedBox(height: 14),
              EmojiGrid(value: emoji, onChanged: (v) => set(() => emoji = v)),
              const SizedBox(height: 18),
              Row(children: [
                if (list != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(ctx.t('delete')),
                    onPressed: () async {
                      final ok = await confirmDialog(ctx,
                          title: ctx.t('delete_list_q'), message: ctx.t('delete_list_msg'), danger: true, confirm: ctx.t('delete'));
                      if (!ok) return;
                      store.deleteList(list);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    if (name.text.trim().isEmpty) return;
                    store.saveList(TaskList(
                      id: list?.id ?? '',
                      name: name.text.trim(),
                      emoji: emoji,
                      color: color,
                      order: list?.order ?? store.lists.length,
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
  }
}

class _ListRow extends StatelessWidget {
  final String emoji;
  final String name;
  final int count;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  const _ListRow({required this.emoji, required this.name, required this.count, required this.color, required this.onTap, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return DhCard(
      onTap: onTap,
      onLongPress: onEdit,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(children: [
        IconBadge(emoji: emoji, color: color, size: 40),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: context.tt.titleMedium)),
        Text('$count', style: context.tt.titleMedium?.copyWith(color: context.tokens.textMuted)),
        if (onEdit != null)
          IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: onEdit)
        else
          const SizedBox(width: 12),
      ]),
    );
  }
}

/// Tasks in one list or with one tag.
class ListDetailScreen extends StatelessWidget {
  final String? listId;
  final String? tag;
  final String title;
  const ListDetailScreen({super.key, this.listId, this.tag, required this.title});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final ws = context.watch<WorkspaceProvider>();
    final tasks = tag != null ? plan.withTag(tag!) : plan.inList(listId == '' ? 'inbox' : listId!);
    final done = plan.tasks
        .where((t) => t.isDone && (tag != null ? t.tags.contains(tag) : t.list == (listId ?? '')))
        .toList();
    return AppPage(
      title: title,
      subtitle: context.tn('n_tasks', tasks.length),
      fab: ws.canAdd
          ? FloatingActionButton(
              onPressed: () => openTaskEditor(context, list: listId),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      slivers: [
        if (tasks.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.task_alt_rounded,
              title: context.t('list_empty'),
              actionLabel: ws.canAdd ? context.t('add_task') : null,
              onAction: () => openTaskEditor(context, list: listId),
            ),
          )
        else
          SliverList.list(children: [for (final t in tasks) TaskTile(task: t)]),
        if (done.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle('${context.t('completed')} · ${done.length}')),
          SliverList.list(children: [for (final t in done.take(30)) TaskTile(task: t)]),
        ],
      ],
    );
  }
}

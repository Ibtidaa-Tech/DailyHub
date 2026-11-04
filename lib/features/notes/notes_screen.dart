import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/life_store.dart';
import '../../data/models.dart';
import '../../ui/kit.dart';
import 'note_editor.dart';

/// Note background colours (index stored on the note), per theme.
class NoteColors {
  static const light = [
    Color(0xFFFFFFFF), Color(0xFFFFF4C2), Color(0xFFFFDDD2), Color(0xFFD6F5DF),
    Color(0xFFD8ECFF), Color(0xFFE9E0FF), Color(0xFFFFDCEA), Color(0xFFEDE8DE),
  ];
  static const dark = [
    Color(0xFF16191F), Color(0xFF3D3717), Color(0xFF45291F), Color(0xFF1C3F28),
    Color(0xFF1B344D), Color(0xFF342A52), Color(0xFF472033), Color(0xFF38342B),
  ];
  static Color of(BuildContext context, int i) {
    final l = context.isDark ? dark : light;
    return l[i.abs() % l.length];
  }
}

class NotesScreen extends StatefulWidget {
  final bool isTab;
  const NotesScreen({super.key, this.isTab = false});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _q = '';
  String? _label;
  bool _archived = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<AppSettings>();
    final grid = settings.notesLayout == 'grid';
    var notes = _archived ? store.archived : store.active;
    if (_label != null) notes = notes.where((n) => n.labels.contains(_label)).toList();
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      notes = notes
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.body.toLowerCase().contains(q) ||
              n.checklist.any((c) => c.title.toLowerCase().contains(q)) ||
              n.labels.any((l) => l.toLowerCase().contains(q)))
          .toList();
    }
    final pinned = notes.where((n) => n.pinned).toList();
    final others = notes.where((n) => !n.pinned).toList();

    return AppPage(
      title: context.t(_archived ? 'archived_notes' : 'm_notes'),
      showBack: !widget.isTab,
      actions: [
        IconButton(
          tooltip: context.t(grid ? 'list_view' : 'grid_view'),
          icon: Icon(grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
          onPressed: () => settings.setNotesLayout(grid ? 'list' : 'grid'),
        ),
        IconButton(
          tooltip: context.t(_archived ? 'm_notes' : 'archive'),
          icon: Icon(_archived ? Icons.sticky_note_2_outlined : Icons.archive_outlined),
          onPressed: () => setState(() => _archived = !_archived),
        ),
      ],
      fab: _archived
          ? null
          : FloatingActionButton.extended(
              heroTag: 'noteFab',
              onPressed: () => openNoteEditor(context),
              icon: const Icon(Icons.edit_rounded),
              label: Text(context.t('new_note')),
            ),
      slivers: [
        SliverToBoxAdapter(
          child: TextField(
            decoration: InputDecoration(
              hintText: context.t('search_notes'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        if (store.labels.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ChipRow<String?>(
                items: [(null, context.t('all')), for (final l in store.labels) (l, l)],
                value: _label,
                onSelected: (v) => setState(() => _label = v),
              ),
            ),
          ),
        if (notes.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: _archived ? Icons.archive_outlined : Icons.sticky_note_2_rounded,
              color: AppColors.mNotes,
              title: context.t(_archived ? 'no_archived' : (_q.isEmpty ? 'no_notes' : 'no_results')),
              message: _archived || _q.isNotEmpty ? null : context.t('no_notes_msg'),
              actionLabel: _archived || _q.isNotEmpty ? null : context.t('new_note'),
              onAction: () => openNoteEditor(context),
            ),
          ),
        if (pinned.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('pinned'))),
          SliverToBoxAdapter(child: _NotesLayout(notes: pinned, grid: grid)),
        ],
        if (others.isNotEmpty) ...[
          if (pinned.isNotEmpty) SliverToBoxAdapter(child: SectionTitle(context.t('others'))),
          if (pinned.isEmpty) const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(child: _NotesLayout(notes: others, grid: grid)),
        ],
      ],
    );
  }
}

/// Masonry grid (balanced columns) or single-column list.
class _NotesLayout extends StatelessWidget {
  final List<Note> notes;
  final bool grid;
  const _NotesLayout({required this.notes, required this.grid});

  static double _estimate(Note n) {
    var h = 40.0;
    if (n.title.isNotEmpty) h += 22;
    final text = n.preview;
    h += (text.length / 26).clamp(1, 8) * 18;
    if (n.photos.isNotEmpty) h += 110;
    if (n.labels.isNotEmpty) h += 24;
    return h;
  }

  @override
  Widget build(BuildContext context) {
    if (!grid) return Column(children: [for (final n in notes) NoteCard(note: n, maxLines: 4)]);
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 600 ? 3 : 2);
      final columns = List.generate(cols, (_) => <Note>[]);
      final heights = List.filled(cols, 0.0);
      for (final n in notes) {
        var i = 0;
        for (var j = 1; j < cols; j++) {
          if (heights[j] < heights[i]) i = j;
        }
        columns[i].add(n);
        heights[i] += _estimate(n);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: Column(children: [for (final n in columns[i]) NoteCard(note: n)])),
        ],
      ]);
    });
  }
}

class NoteCard extends StatelessWidget {
  final Note note;
  final int maxLines;
  const NoteCard({super.key, required this.note, this.maxLines = 9});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final n = note;
    final bg = NoteColors.of(context, n.color);
    final hasColor = n.color != 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: hasColor ? Colors.transparent : tk.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openNoteEditor(context, note: n),
          onLongPress: () => noteQuickActions(context, n),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (n.photos.isNotEmpty)
              SizedBox(
                height: 110,
                child: Image.network(n.photos.first, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: tk.subtle, child: const Icon(Icons.broken_image_outlined))),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (n.title.isNotEmpty)
                  Row(children: [
                    Expanded(
                      child: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                    ),
                    if (n.pinned) Icon(Icons.push_pin_rounded, size: 14, color: tk.textMuted),
                  ]),
                if (n.title.isNotEmpty && n.preview.isNotEmpty) const SizedBox(height: 4),
                if (n.preview.isNotEmpty)
                  Text(n.preview,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodyMedium?.copyWith(height: 1.35)),
                if (n.labels.isNotEmpty || n.voice.isNotEmpty || n.photos.length > 1) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final l in n.labels.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(l, style: context.tt.labelSmall?.copyWith(letterSpacing: 0)),
                      ),
                    if (n.voice.isNotEmpty) Icon(Icons.mic_rounded, size: 15, color: tk.textMuted),
                    if (n.photos.length > 1) Icon(Icons.photo_library_outlined, size: 15, color: tk.textMuted),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

Future<void> noteQuickActions(BuildContext context, Note n) async {
  final store = context.read<NotesStore>();
  final a = await showAppSheet<String>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(n.title.isEmpty ? ctx.t('note') : n.title, subtitle: n.updatedAt.isEmpty ? null : ctx.tr('edited_x', {'x': ctx.relative(DateTime.tryParse(n.updatedAt) ?? DateTime.now())})),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var i = 0; i < NoteColors.light.length; i++)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, 'color$i'),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: NoteColors.of(ctx, i),
                      shape: BoxShape.circle,
                      border: Border.all(color: i == n.color ? ctx.cs.primary : ctx.tokens.border, width: i == n.color ? 2.5 : 1),
                    ),
                  ),
                ),
            ]),
          ),
          OptionTile(icon: n.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, title: ctx.t(n.pinned ? 'unpin' : 'pin'), onTap: () => Navigator.pop(ctx, 'pin')),
          OptionTile(icon: n.archived ? Icons.unarchive_outlined : Icons.archive_outlined, title: ctx.t(n.archived ? 'unarchive' : 'archive'), onTap: () => Navigator.pop(ctx, 'archive')),
          OptionTile(icon: Icons.delete_outline_rounded, title: ctx.t('delete'), destructive: true, onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
  });
  if (a == null || !context.mounted) return;
  if (a.startsWith('color')) {
    store.update(n, {'color': int.parse(a.substring(5))});
  } else if (a == 'pin') {
    store.update(n, {'pinned': !n.pinned});
  } else if (a == 'archive') {
    store.update(n, {'archived': !n.archived});
    showUndo(context, context.t(n.archived ? 'unarchived' : 'archived_toast'), () => store.update(n, {'archived': n.archived}));
  } else if (a == 'delete') {
    final data = store.delete(n);
    showUndo(context, context.t('note_deleted'), () => store.restore(n.id, data));
  }
}

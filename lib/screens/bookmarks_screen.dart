import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// Links saved to read later.
///
/// The whole card is the link — one tap opens it. Copy and share sit on the
/// right, swiping right marks it read (the pile you've worked through drops
/// to the bottom) and swiping left deletes with an undo.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  String? _tag;

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('bookmarks'),
      builder: (context, snap) {
        final all = [...?snap.data]
          ..sort((a, b) => str(b['createdAt']).compareTo(str(a['createdAt'])));

        final tags = <String>{for (final b in all) ...tagsOf(b)}.toList()..sort();
        if (_tag != null && !tags.contains(_tag)) _tag = null;
        final items = _tag == null
            ? all
            : all.where((b) => tagsOf(b).contains(_tag)).toList();
        final unread = items.where((b) => b['read'] != true).toList();
        final read = items.where((b) => b['read'] == true).toList();
        final split = unread.isNotEmpty && read.isNotEmpty;

        return AppPage(
          title: context.t('m_bookmarks'),
          subtitle: context.t('bm_sub'),
          fab: FloatingActionButton.extended(
            heroTag: 'bmFab',
            onPressed: () => openBookmarkEditor(context),
            icon: const Icon(Icons.add_link_rounded),
            label: Text(context.t('bm_add')),
          ),
          header: tags.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ChipRow<String?>(
                    items: [(null, context.t('all')), for (final t in tags) (t, t)],
                    value: _tag,
                    onSelected: (v) => setState(() => _tag = v),
                  ),
                ),
          slivers: [
            if (items.isEmpty && snap.hasData)
              SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.bookmark_border_rounded,
                  color: AppColors.mBookmarks,
                  title: context.t(_tag == null ? 'bm_none' : 'no_results'),
                  message: _tag == null ? context.t('bm_none_msg') : null,
                  actionLabel: _tag == null ? context.t('bm_add') : null,
                  onAction: _tag == null ? () => openBookmarkEditor(context) : null,
                ),
              )
            else ...[
              if (split) SliverToBoxAdapter(child: SectionTitle(context.t('bm_unread'))),
              SliverList.list(
                children: [for (final b in unread) _BookmarkCard(db: db, bookmark: b)],
              ),
              if (split) SliverToBoxAdapter(child: SectionTitle(context.t('bm_read'))),
              SliverList.list(
                children: [for (final b in read) _BookmarkCard(db: db, bookmark: b)],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Tags are stored as one comma-separated string, the same shape meetings use
/// for attendees — nothing to migrate, and an older record simply has none.
List<String> tagsOf(Map<String, dynamic> bookmark) => str(bookmark['tags'])
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

/// Bare domain, used as the card's chip: "www.bbc.co.uk/news" → "bbc.co.uk".
String domainOf(String raw) {
  final uri = Uri.tryParse(_normalize(raw));
  final host = uri?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _normalize(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return u;
  return u.startsWith('http://') || u.startsWith('https://') ? u : 'https://$u';
}

class _BookmarkCard extends StatelessWidget {
  final DbService db;
  final Map<String, dynamic> bookmark;
  const _BookmarkCard({required this.db, required this.bookmark});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final url = str(bookmark['url']);
    final title = str(bookmark['title']);
    final isRead = bookmark['read'] == true;
    final domain = domainOf(url);
    final tags = tagsOf(bookmark);
    final saved = DateTime.tryParse(str(bookmark['createdAt']));

    return SwipeTile(
      swipeKey: ValueKey('bm_${bookmark['id']}'),
      rightIcon: isRead ? Icons.mark_email_unread_outlined : Icons.check_rounded,
      rightColor: isRead ? tk.textMuted : tk.success,
      rightLabel: context.t(isRead ? 'bm_mark_unread' : 'bm_mark_read'),
      onSwipeRight: () async {
        _setRead(context, db, bookmark, !isRead);
        return false; // it just moves between the two sections
      },
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        _removeBookmark(context, db, bookmark);
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        onTap: () => _openLink(context, url),
        onLongPress: () => openBookmarkEditor(context, existing: bookmark),
        child: Row(children: [
          IconBadge(
            icon: isRead ? Icons.check_circle_rounded : Icons.link_rounded,
            color: isRead ? tk.success : AppColors.mBookmarks,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title.isEmpty ? url : title,
                style: context.tt.titleSmall?.copyWith(color: isRead ? tk.textMuted : null),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (domain.isNotEmpty)
                  Pill(domain, color: AppColors.mBookmarks, icon: Icons.public_rounded)
                else
                  Pill(context.t('url'), color: tk.textMuted),
                for (final t in tags) Pill(t, color: tk.textMuted, icon: Icons.sell_outlined),
                if (saved != null) MetaChip(Icons.schedule_rounded, context.dayLabel(saved, short: true)),
              ]),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('copy'),
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _normalize(url)));
              showToast(context, context.t('bm_copied'), icon: Icons.copy_rounded);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('share'),
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            onPressed: () => Share.share(
              title.isEmpty ? _normalize(url) : '$title\n${_normalize(url)}',
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- actions

Future<void> _openLink(BuildContext context, String raw) async {
  final url = _normalize(raw);
  final uri = url.isEmpty ? null : Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  showToast(context, context.t('bm_open_failed'), icon: Icons.error_outline_rounded);
}

void _setRead(BuildContext context, DbService db, Map<String, dynamic> bookmark, bool value) {
  final id = str(bookmark['id']);
  db.update('bookmarks', id, {'read': value});
  showUndo(
    context,
    context.t(value ? 'bm_marked_read' : 'bm_marked_unread'),
    () => db.update('bookmarks', id, {'read': !value}),
  );
}

void _removeBookmark(BuildContext context, DbService db, Map<String, dynamic> bookmark) {
  final id = str(bookmark['id']);
  final data = Map<String, dynamic>.from(bookmark)..remove('id');
  db.remove('bookmarks', id);
  showUndo(context, context.t('bm_removed'), () => db.set('bookmarks', id, data));
}

// ----------------------------------------------------------------- editor

/// Add or edit a link. Pass [existing] to edit in place.
Future<void> openBookmarkEditor(BuildContext context, {Map<String, dynamic>? existing}) async {
  final db = DbService.instance;
  final url = TextEditingController(text: str(existing?['url']));
  final title = TextEditingController(text: str(existing?['title']));
  final tags =
      TextEditingController(text: tagsOf(existing ?? const <String, dynamic>{}).join(', '));

  await showAppSheet<void>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ctx.t(existing == null ? 'bm_add' : 'bm_edit'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: url,
              autofocus: existing == null,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: ctx.t('bm_url_hint'),
                prefixIcon: const Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ctx.t('bm_title_hint'),
                prefixIcon: const Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tags,
              decoration: InputDecoration(
                hintText: ctx.t('bm_tags_hint'),
                prefixIcon: const Icon(Icons.sell_outlined),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              if (existing != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(ctx.t('delete')),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (context.mounted) _removeBookmark(context, db, existing);
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  if (url.text.trim().isEmpty) {
                    showToast(ctx, ctx.t('bm_enter_url'));
                    return;
                  }
                  final data = <String, dynamic>{
                    'url': url.text.trim(),
                    'title': title.text.trim(),
                    'tags': tags.text
                        .split(',')
                        .map((t) => t.trim())
                        .where((t) => t.isNotEmpty)
                        .join(', '),
                    'createdAt': str(existing?['createdAt']).isEmpty
                        ? DateTime.now().toIso8601String()
                        : str(existing?['createdAt']),
                  };
                  Navigator.pop(ctx);
                  if (existing == null) {
                    await db.add('bookmarks', data);
                    return;
                  }
                  final id = str(existing['id']);
                  // Merge, so links added from other screens survive the edit.
                  final previous = {for (final k in data.keys) k: existing[k]};
                  await db.update('bookmarks', id, data);
                  if (!context.mounted) return;
                  showUndo(context, context.t('bm_updated'),
                      () => db.update('bookmarks', id, previous));
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ],
        ),
      ),
    );
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in [url, title, tags]) {
        c.dispose();
      }
    });
  });
}

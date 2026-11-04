import 'package:flutter/material.dart';

import '../services/db_service.dart';
import '../services/link_service.dart';

/// Shows everything linked to a record, with a picker to add more.
/// Drop this into any detail view to turn a flat record into a hub.
class LinkedItemsPanel extends StatefulWidget {
  final String collection;
  final Map<String, dynamic> item;
  const LinkedItemsPanel({
    super.key,
    required this.collection,
    required this.item,
  });

  @override
  State<LinkedItemsPanel> createState() => _LinkedItemsPanelState();
}

class _LinkedItemsPanelState extends State<LinkedItemsPanel> {
  late Future<List<({String collection, Map<String, dynamic> data})>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = LinkService.instance.resolve(widget.item);
  }

  static IconData _icon(String c) => switch (c) {
        'trips' => Icons.flight,
        'todos' => Icons.check_circle_outline,
        'notes' => Icons.sticky_note_2_outlined,
        'txns' => Icons.account_balance_wallet_outlined,
        'reminders' => Icons.alarm,
        'bookmarks' => Icons.bookmark,
        'meetings' => Icons.groups,
        _ => Icons.link,
      };

  static Color _color(String c) => switch (c) {
        'trips' => const Color(0xFF27AE60),
        'todos' => const Color(0xFF667EEA),
        'notes' => const Color(0xFFF39C12),
        'txns' => const Color(0xFF16A085),
        'reminders' => const Color(0xFFE74C3C),
        'bookmarks' => const Color(0xFF9B59B6),
        'meetings' => const Color(0xFF34495E),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_outlined, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            const Text('Linked items',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add_link, size: 18),
              label: const Text('Link'),
              onPressed: _openPicker,
            ),
          ],
        ),
        FutureBuilder<List<({String collection, Map<String, dynamic> data})>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text('Nothing linked yet',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              );
            }
            return Column(
              children: items.map((e) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_icon(e.collection),
                      color: _color(e.collection), size: 20),
                  title: Text(
                      LinkService.titleOf(e.collection, e.data),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                      LinkService.linkable[e.collection] ?? e.collection,
                      style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off, size: 18),
                    onPressed: () async {
                      await LinkService.instance.unlink(
                        fromCollection: widget.collection,
                        fromId: widget.item['id'],
                        fromData: widget.item,
                        toCollection: e.collection,
                        toId: e.data['id'],
                      );
                      if (mounted) setState(_refresh);
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _LinkPicker(
        excludeCollection: widget.collection,
        excludeId: widget.item['id'],
        onPick: (collection, data) async {
          await LinkService.instance.link(
            fromCollection: widget.collection,
            fromId: widget.item['id'],
            fromData: widget.item,
            toCollection: collection,
            toId: data['id'],
            toData: data,
          );
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted) setState(_refresh);
        },
      ),
    );
  }
}

class _LinkPicker extends StatefulWidget {
  final String excludeCollection;
  final String excludeId;
  final Future<void> Function(String collection, Map<String, dynamic> data)
      onPick;
  const _LinkPicker({
    required this.excludeCollection,
    required this.excludeId,
    required this.onPick,
  });

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  String _collection = 'notes';

  @override
  void initState() {
    super.initState();
    // Default to something other than the record's own collection.
    if (widget.excludeCollection == 'notes') _collection = 'todos';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Link to...',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: LinkService.linkable.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _collection == e.key,
                          onSelected: (_) =>
                              setState(() => _collection = e.key),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DbService.instance.stream(_collection,
                  workspace: LinkService.isWorkspace(_collection)),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!
                    .where((e) => !(_collection == widget.excludeCollection &&
                        e['id'] == widget.excludeId))
                    .toList();
                if (items.isEmpty) {
                  return Center(
                    child: Text('Nothing to link here yet',
                        style: TextStyle(color: Colors.grey.shade500)),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final d = items[i];
                    return ListTile(
                      dense: true,
                      title: Text(LinkService.titleOf(_collection, d),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.add_link, size: 18),
                      onTap: () => widget.onPick(_collection, d),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

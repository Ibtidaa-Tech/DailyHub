import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/trip_store.dart';
import '../../ui/kit.dart';
import 'trip_editor.dart';
import 'trips_screen.dart';

/// Everything about one journey: the facts, what to pack, and your notes.
class TripDetailScreen extends StatelessWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TripStore>();
    final ws = context.watch<WorkspaceProvider>();
    final t = s.byId(tripId);
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(context.t('not_found'))));
    }
    final away = t.daysAway;

    return AppPage(
      title: t.route.isEmpty ? context.t('trip_untitled') : t.route,
      subtitle: tripModeLabel(context, t.mode),
      actions: [
        IconButton(
          tooltip: context.t('share'),
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => _share(context, t),
        ),
        if (ws.canEdit)
          IconButton(
            tooltip: context.t('edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openTripEditor(context, trip: t),
          ),
      ],
      slivers: [
        if (t.isUpcoming && away != null)
          SliverToBoxAdapter(
            child: DhCard(
              color: context.tokens.tint(AppColors.mTrips),
              borderColor: Colors.transparent,
              child: Row(children: [
                Text(
                  away <= 0 ? '🎒' : '✈️',
                  style: const TextStyle(fontSize: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    away < 0
                        ? context.t('trip_in_progress')
                        : (away == 0
                            ? context.t('trip_today')
                            : context.tn('trip_days_left', away)),
                    style: context.tt.titleMedium?.copyWith(color: AppColors.mTrips),
                  ),
                ),
              ]),
            ),
          ),
        SliverToBoxAdapter(child: TripFacts(trip: t)),
        if (t.notes.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('notes_optional'))),
          SliverToBoxAdapter(child: DhCard(child: Text(t.notes, style: context.tt.bodyMedium))),
        ],
        SliverToBoxAdapter(child: SectionTitle(context.t('trip_packing'))),
        SliverToBoxAdapter(child: _Packing(trip: t, canEdit: ws.canAdd)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              if (ws.canEdit && !t.isDone)
                OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(context.t('trip_mark_done')),
                  onPressed: () => s.setStatus(t, 'done'),
                ),
              if (ws.canEdit && t.isDone)
                OutlinedButton.icon(
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text(context.t('reopen')),
                  onPressed: () => s.setStatus(t, 'upcoming'),
                ),
              if (ws.canEdit && !t.isCancelled)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: context.tokens.warning),
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: Text(context.t('trip_cancel')),
                  onPressed: () => s.setStatus(t, 'cancelled'),
                ),
              if (ws.canEdit)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: context.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(context.t('delete')),
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: context.t('trip_delete_q'), danger: true, confirm: context.t('delete'));
                    if (!ok || !context.mounted) return;
                    final data = s.delete(t);
                    Navigator.pop(context);
                    if (context.mounted) {
                      showUndo(context, context.t('trip_deleted'), () => s.restore(t.id, data));
                    }
                  },
                ),
            ]),
          ),
        ),
      ],
    );
  }

  void _share(BuildContext context, Trip t) {
    final dep = t.departure;
    final lines = <String>[
      t.route,
      '${tripModeLabel(context, t.mode)}${t.operator.isEmpty ? '' : ' · ${t.operator}'}',
      if (dep != null) '${context.t('trip_departs')}: ${context.dayTimeLabel(dep, hasTime: t.depTime.isNotEmpty)}',
      if (t.pnr.isNotEmpty) '${context.t('trip_pnr')}: ${t.pnr}',
      if (t.seat.isNotEmpty) '${context.t('trip_seat')}: ${t.seat}',
    ];
    Share.share(lines.where((e) => e.trim().isNotEmpty).join('\n'));
  }
}

class _Packing extends StatefulWidget {
  final Trip trip;
  final bool canEdit;
  const _Packing({required this.trip, required this.canEdit});
  @override
  State<_Packing> createState() => _PackingState();
}

class _PackingState extends State<_Packing> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _addItem(TripStore s) {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    s.setPacking(widget.trip, [...widget.trip.packing, PackItem(title: text)]);
    _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<TripStore>();
    final t = widget.trip;
    final tk = context.tokens;

    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (t.packing.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(context.t('trip_packing_empty'), style: context.tt.bodySmall),
          )
        else ...[
          Row(children: [
            Expanded(child: ProgressBar(value: t.packProgress, color: tk.success, height: 7)),
            const SizedBox(width: 10),
            Text('${t.packed}/${t.packing.length}', style: context.tt.labelMedium),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < t.packing.length; i++)
            _PackRow(
              item: t.packing[i],
              canEdit: widget.canEdit,
              onToggle: () => s.togglePackItem(t, i),
              onRemove: () {
                final items = List<PackItem>.from(t.packing)..removeAt(i);
                s.setPacking(t, items);
              },
            ),
        ],
        if (widget.canEdit) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _add,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addItem(s),
                decoration: InputDecoration(
                  hintText: context.t('trip_add_item'),
                  isDense: true,
                  prefixIcon: const Icon(Icons.add_rounded),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final group in kPackingTemplates.keys)
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(context.t('pkg_$group')),
                onPressed: () {
                  final have = t.packing.map((e) => e.title.toLowerCase()).toSet();
                  final add = <PackItem>[];
                  for (final key in kPackingTemplates[group]!) {
                    final title = context.t(key);
                    if (!have.contains(title.toLowerCase())) add.add(PackItem(title: title));
                  }
                  if (add.isEmpty) {
                    showToast(context, context.t('trip_already_added'));
                    return;
                  }
                  s.setPacking(t, [...t.packing, ...add]);
                },
              ),
            if (t.packing.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.clear_all_rounded, size: 16),
                label: Text(context.t('trip_clear_packing')),
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: context.t('trip_clear_packing_q'), danger: true, confirm: context.t('remove'));
                  if (ok) s.setPacking(t, []);
                },
              ),
          ]),
        ],
      ]),
    );
  }
}

class _PackRow extends StatelessWidget {
  final PackItem item;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  const _PackRow({
    required this.item,
    required this.canEdit,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: canEdit
          ? () {
              HapticFeedback.selectionClick();
              onToggle();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(
            item.done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 20,
            color: item.done ? tk.success : tk.textFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.title,
              style: context.tt.bodyMedium?.copyWith(
                decoration: item.done ? TextDecoration.lineThrough : null,
                color: item.done ? tk.textFaint : null,
              ),
            ),
          ),
          if (canEdit)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 16, color: tk.textFaint),
              onPressed: onRemove,
            ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/whereabouts_store.dart';
import '../../services/location_service.dart';
import '../../ui/kit.dart';

/// A day-by-day record of where you were.
///
/// One entry per day, captured when you open the app, with a label you write
/// yourself. There is no reverse geocoding — nothing is sent to a mapping
/// service — so a place is whatever you choose to call it, which is more
/// useful than "Unnamed Road" anyway.
class WhereaboutsScreen extends StatefulWidget {
  const WhereaboutsScreen({super.key});
  @override
  State<WhereaboutsScreen> createState() => _WhereaboutsScreenState();
}

class _WhereaboutsScreenState extends State<WhereaboutsScreen> {
  bool _busy = false;

  Future<void> _logNow(WhereaboutsStore store, {DateTime? day}) async {
    setState(() => _busy = true);
    final err = await store.logNow(day: day);
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(
      context,
      err ?? context.t('wa_logged'),
      icon: err == null ? Icons.my_location_rounded : Icons.error_outline_rounded,
    );
  }

  Future<void> _edit(WhereaboutsStore store, DateTime day, Map<String, dynamic>? row) async {
    final label = TextEditingController(text: str(row?['label']));
    final note = TextEditingController(text: str(row?['note']));
    final saved = await showAppSheet<bool>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(ctx.dayLabel(day)),
          const SizedBox(height: 10),
          TextField(
            controller: label,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: ctx.t('wa_label'),
              hintText: ctx.t('wa_label_hint'),
              prefixIcon: const Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: ctx.t('wa_note'),
              hintText: ctx.t('wa_note_hint'),
              prefixIcon: const Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            if (row != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(ctx.t('delete')),
                onPressed: () {
                  store.remove(day);
                  Navigator.pop(ctx, false);
                },
              ),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t('save'))),
          ]),
        ]),
      ),
    );
    if (saved == true) {
      store.save(day, label: label.text.trim(), note: note.text.trim());
    }
    label.dispose();
    note.dispose();
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse(LocationService.mapsUrl(lat, lng));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WhereaboutsStore>();
    final today = todayDate();
    final todayRow = store.forDay(today);

    return AppPage(
      title: context.t('m_whereabouts'),
      subtitle: context.t('wa_sub'),
      fab: FloatingActionButton.extended(
        heroTag: 'waFab',
        onPressed: _busy ? null : () => _logNow(store),
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location_rounded),
        label: Text(context.t('wa_log_now')),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: DhCard(
            color: context.tokens.tint(AppColors.mPlaces),
            onTap: () => _edit(store, today, todayRow),
            child: Row(children: [
              IconBadge(
                icon: todayRow == null ? Icons.location_searching_rounded : Icons.place_rounded,
                color: AppColors.mPlaces,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('today'), style: context.tt.titleSmall),
                  Text(
                    todayRow == null
                        ? context.t('wa_nothing_today')
                        : (WhereaboutsStore.labelFor(todayRow).isEmpty
                            ? context.t('wa_unnamed')
                            : WhereaboutsStore.labelFor(todayRow)),
                    style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: DhCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, size: 18, color: context.tokens.textFaint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.t('wa_privacy'),
                    style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted)),
              ),
            ]),
          ),
        ),
        if (store.days.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.map_outlined,
              color: AppColors.mPlaces,
              title: context.t('wa_empty'),
              message: context.t('wa_empty_msg'),
              actionLabel: context.t('wa_log_now'),
              onAction: () => _logNow(store),
            ),
          )
        else ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('wa_history'))),
          SliverList.builder(
            itemCount: store.days.length,
            itemBuilder: (context, n) => _DayRow(
              row: store.days[n],
              onTap: (day, row) => _edit(store, day, row),
              onMaps: _openMaps,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final void Function(DateTime day, Map<String, dynamic> row) onTap;
  final Future<void> Function(double lat, double lng) onMaps;
  const _DayRow({required this.row, required this.onTap, required this.onMaps});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final day = parseDay(str(row['id'])) ?? todayDate();
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    // The typed label if there is one, otherwise the looked-up place name,
    // and only coordinates as a last resort.
    final label = WhereaboutsStore.labelFor(row);
    final area = str(row['area']);
    final note = str(row['note']);
    final at = DateTime.tryParse(str(row['at']));

    return DhCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      onTap: () => onTap(day, row),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Text(context.fmtDate(day, 'd'),
              style: context.tt.titleMedium?.copyWith(color: AppColors.mPlaces)),
          Text(context.fmtDate(day, 'MMM'), style: context.tt.bodySmall),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.isEmpty ? context.t('wa_unnamed') : label,
                style: context.tt.titleSmall?.copyWith(
                  color: label.isEmpty ? tk.textMuted : null,
                )),
            if (area.isNotEmpty && area != label)
              Text(area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall?.copyWith(color: tk.textFaint)),
            if (note.isNotEmpty)
              Text(note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Text(context.fmtDate(day, 'EEEE'),
                  style: context.tt.bodySmall?.copyWith(fontSize: 11, color: tk.textFaint)),
              if (at != null)
                Text('· ${context.timeOf(at)}',
                    style: context.tt.bodySmall?.copyWith(fontSize: 11, color: tk.textFaint)),
            ]),
          ]),
        ),
        if (lat != null && lng != null) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('wa_copy'),
            icon: Icon(Icons.copy_rounded, size: 17, color: tk.textFaint),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$lat, $lng'));
              showToast(context, context.t('wa_copied'), icon: Icons.copy_rounded);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('wa_maps'),
            icon: const Icon(Icons.map_rounded, size: 18, color: AppColors.mPlaces),
            onPressed: () => onMaps(lat, lng),
          ),
        ],
      ]),
    );
  }
}

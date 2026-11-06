import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';
import 'tracker_ui.dart';

/// The list behind a number.
///
/// Tapping "14 missed" should answer *which* fourteen, otherwise the figure
/// is a scoreboard rather than something you can act on. Rows are newest
/// first and tappable, so a missed day leads straight to filling it in.
Future<TrackerEntry?> showTickList(
  BuildContext context, {
  required Challenge challenge,
  required TrackerStore store,
  TickStatus? status,
  bool lateEntryOnly = false,
  String? title,
}) {
  final entries = store.entries(
    challenge,
    status: status,
    lateEntryOnly: lateEntryOnly,
  );
  return showAppSheet<TrackerEntry>(
    context,
    expand: entries.length > 6,
    builder: (_) => _TickListSheet(
      entries: entries,
      challenge: challenge,
      title: title ??
          (lateEntryOnly
              ? context.t('tr_late_entries')
              : context.t(tickStatusKey(status ?? TickStatus.onTime))),
    ),
  );
}

class _TickListSheet extends StatelessWidget {
  final List<TrackerEntry> entries;
  final Challenge challenge;
  final String title;
  const _TickListSheet({required this.entries, required this.challenge, required this.title});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetHeader(title),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.check_circle_outline_rounded, size: 20, color: tk.success),
            const SizedBox(width: 10),
            Expanded(child: Text(context.t('tr_none_in_list'), style: context.tt.bodyMedium)),
          ]),
        ]),
      );
    }

    final body = ListView.builder(
      shrinkWrap: true,
      physics: entries.length > 6 ? null : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, n) {
        final e = entries[n];
        final color = AppColors.swatch(e.item.color);
        final done = e.log?.completedAt;
        return DhCard(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          onTap: () => Navigator.pop(context, e),
          child: Row(children: [
            IconBadge(emoji: e.item.emoji, color: color, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.item.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
                Text(
                  done == null
                      ? context.dayLabel(e.day)
                      : '${context.dayLabel(e.day, short: true)} · ${context.timeOf(done)}',
                  style: context.tt.bodySmall?.copyWith(color: tk.textMuted),
                ),
              ]),
            ),
            TickPill(e.status, itemColor: color, lateBy: e.log?.lateBy ?? 0),
          ]),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(title, subtitle: context.tr('tr_n_entries', {'n': entries.length})),
        const SizedBox(height: 8),
        entries.length > 6 ? Expanded(child: body) : Flexible(child: body),
      ]),
    );
  }
}

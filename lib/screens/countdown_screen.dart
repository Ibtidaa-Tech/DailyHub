import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// Countdowns to the things you're actually waiting for — exams, trips,
/// birthdays, deadlines. Past events flip to counting up instead.
class CountdownScreen extends StatelessWidget {
  const CountdownScreen({super.key});

  static const emojis = [
    '🎯', '🎓', '✈️', '🎂', '💍', '🏆', '📅', '🎉',
    '🎁', '🏠', '💼', '🚗', '📝', '🪔', '❤️', '⭐',
  ];

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('countdowns'),
      builder: (context, snap) {
        final raw = snap.data;
        final today = todayDate();
        final dated = <(int, Map<String, dynamic>)>[];
        for (final c in raw ?? const <Map<String, dynamic>>[]) {
          final d = parseDay(str(c['date']));
          if (d == null) continue;
          dated.add((daysBetween(today, d), c));
        }
        final upcoming = dated.where((e) => e.$1 >= 0).toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
        final past = dated.where((e) => e.$1 < 0).toList()
          ..sort((a, b) => b.$1.compareTo(a.$1));

        return AppPage(
          title: context.t('m_countdowns'),
          subtitle: context.t('cd_sub'),
          fab: FloatingActionButton.extended(
            heroTag: 'cdFab',
            onPressed: () => _openCountdownEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.t('cd_new')),
          ),
          slivers: [
            if (raw == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 70),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (dated.isEmpty)
              SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.hourglass_empty_rounded,
                  color: AppColors.mCountdown,
                  title: context.t('cd_none'),
                  message: context.t('cd_none_msg'),
                  actionLabel: context.t('cd_new'),
                  onAction: () => _openCountdownEditor(context),
                ),
              )
            else ...[
              if (upcoming.isNotEmpty) ...[
                SliverToBoxAdapter(child: SectionTitle(context.t('upcoming'))),
                SliverList.list(
                  children: [
                    for (final e in upcoming) _CountdownCard(days: e.$1, item: e.$2),
                  ],
                ),
              ],
              if (past.isNotEmpty) ...[
                SliverToBoxAdapter(child: SectionTitle(context.t('cd_past'))),
                SliverList.list(
                  children: [
                    for (final e in past) _CountdownCard(days: e.$1, item: e.$2),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// One countdown. The day count is the hero; the title and date support it.
class _CountdownCard extends StatelessWidget {
  final int days;
  final Map<String, dynamic> item;
  const _CountdownCard({required this.days, required this.item});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final c = item;
    final d = parseDay(str(c['date']));
    final isToday = days == 0;
    final past = days < 0;
    final Color color = past
        ? tk.textMuted
        : isToday
            ? tk.success
            : days <= 7
                ? tk.warning
                : AppColors.mCountdown;
    final n = days.abs();
    final caption = past
        ? context.t(n == 1 ? 'cd_day_ago' : 'cd_days_ago')
        : context.t(n == 1 ? 'cd_day_to_go' : 'cd_days_to_go');

    return SwipeTile(
      swipeKey: ValueKey('cd_${str(c['id'])}'),
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        await _removeCountdown(context, c);
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        borderColor: isToday ? tk.success : null,
        onTap: () => _openCountdownEditor(context, existing: c),
        child: Row(children: [
          Container(
            width: 66,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: tk.tint(color),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isToday ? context.t('cd_today') : '$n',
                  maxLines: 1,
                  style: context.tt.headlineSmall?.copyWith(
                      color: color, fontSize: isToday ? 15 : 26, height: 1.1),
                ),
              ),
              if (!isToday)
                Text(
                  caption,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelSmall
                      ?.copyWith(color: color, fontSize: 10, letterSpacing: 0.2),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(str(c['emoji']).isEmpty ? '🎯' : str(c['emoji']),
                    style: const TextStyle(fontSize: 18, height: 1.1)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    str(c['title']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.titleSmall
                        ?.copyWith(color: past ? tk.textMuted : null),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              if (d != null)
                MetaChip(Icons.event_outlined, context.fmtDate(d, 'EEE, d MMM yyyy')),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Removes a countdown, recoverable for a few seconds.
Future<void> _removeCountdown(BuildContext context, Map<String, dynamic> item) async {
  final db = DbService.instance;
  final id = str(item['id']);
  final data = Map<String, dynamic>.from(item)..remove('id');
  await db.remove('countdowns', id);
  if (!context.mounted) return;
  showUndo(context, context.t('cd_deleted'), () => db.set('countdowns', id, data));
}

/// Add or edit a countdown: what it is, an emoji for it, and the day.
Future<void> _openCountdownEditor(BuildContext context, {Map<String, dynamic>? existing}) async {
  final ex = existing;
  final db = DbService.instance;
  final title = TextEditingController(text: str(ex?['title']));
  var date = parseDay(str(ex?['date'])) ?? addDays(todayDate(), 30);
  var emoji = str(ex?['emoji']).isEmpty ? '🎯' : str(ex?['emoji']);

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      final away = daysBetween(todayDate(), date);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ctx.t(ex == null ? 'cd_new' : 'cd_edit'), style: ctx.tt.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                autofocus: ex == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ctx.t('cd_title_hint'),
                  prefixIcon: const Icon(Icons.hourglass_bottom_rounded),
                ),
              ),
              const SizedBox(height: 12),
              FormFieldButton(
                icon: Icons.event_rounded,
                label: ctx.t('date'),
                value: ctx.fmtDate(date, 'EEE, d MMM yyyy'),
                leading: Text(emoji, style: const TextStyle(fontSize: 20, height: 1.1)),
                onTap: () async {
                  final now = DateTime.now();
                  final first = DateTime(now.year - 50);
                  final last = DateTime(now.year + 100);
                  var start = date;
                  if (start.isBefore(first)) start = first;
                  if (start.isAfter(last)) start = last;
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: start,
                    firstDate: first,
                    lastDate: last,
                  );
                  if (picked != null) set(() => date = dateOnly(picked));
                },
              ),
              const SizedBox(height: 6),
              Text(
                away == 0
                    ? ctx.t('cd_today')
                    : away > 0
                        ? '$away ${ctx.t(away == 1 ? 'cd_day_to_go' : 'cd_days_to_go')}'
                        : '${-away} ${ctx.t(away == -1 ? 'cd_day_ago' : 'cd_days_ago')}',
                style: ctx.tt.bodySmall?.copyWith(color: AppColors.mCountdown),
              ),
              const SizedBox(height: 14),
              Text(ctx.t('cd_icon'), style: ctx.tt.labelMedium),
              const SizedBox(height: 8),
              EmojiGrid(
                value: emoji,
                emojis: CountdownScreen.emojis,
                onChanged: (e) => set(() => emoji = e),
              ),
              const SizedBox(height: 18),
              Row(children: [
                if (ex != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(ctx.t('delete')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _removeCountdown(context, ex);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final text = title.text.trim();
                    if (text.isEmpty) {
                      showToast(ctx, ctx.t('cd_enter_title'));
                      return;
                    }
                    final data = <String, dynamic>{
                      ...?ex,
                      'title': text,
                      'emoji': emoji,
                      'date': dayKey(date),
                    }..remove('id');
                    if (ex == null) {
                      db.add('countdowns', data);
                    } else {
                      db.set('countdowns', str(ex['id']), data);
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text(ctx.t('save')),
                ),
              ]),
            ],
          ),
        ),
      );
    });
  });
  // Dispose after the sheet's exit animation, not while it still uses it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), title.dispose);
  });
}

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// A daily diary: one entry a day, a mood, and a few lines about it.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  /// Happiest first — the order the picker shows them in.
  static const moods = ['😄', '🙂', '😐', '😔', '😣'];

  static List<String> moodLabels(BuildContext context) => [
        context.t('mood_great'),
        context.t('mood_good'),
        context.t('mood_okay'),
        context.t('mood_low'),
        context.t('mood_rough'),
      ];

  static String moodLabel(BuildContext context, String mood) {
    final i = moods.indexOf(mood);
    return i < 0 ? '' : moodLabels(context)[i];
  }

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('journal'),
      builder: (context, snap) {
        final raw = snap.data;
        final entries = (raw ?? const <Map<String, dynamic>>[]).toList()
          ..sort((a, b) => str(b['date']).compareTo(str(a['date'])));
        final today = todayDate();
        final todayEntry = _entryOn(entries, today);
        // Today is featured in the header, so it doesn't repeat in the months.
        final months = _groupByMonth(
            entries.where((e) => !identical(e, todayEntry)).toList());

        return AppPage(
          title: context.t('m_journal'),
          subtitle: context.t('jr_sub'),
          fab: FloatingActionButton.extended(
            heroTag: 'journalFab',
            onPressed: () => _openEntryEditor(context, existing: todayEntry, day: today),
            icon: Icon(todayEntry == null ? Icons.edit_rounded : Icons.auto_stories_rounded),
            label: Text(context.t(todayEntry == null ? 'jr_write' : 'jr_today')),
          ),
          header: raw == null || entries.isEmpty
              ? null
              : _JournalTodayCard(entry: todayEntry, entries: entries),
          slivers: [
            if (raw == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 70),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (entries.isEmpty)
              SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.auto_stories_outlined,
                  color: AppColors.mJournal,
                  title: context.t('jr_none'),
                  message: context.t('jr_none_msg'),
                  actionLabel: context.t('jr_write'),
                  onAction: () => _openEntryEditor(context, day: today),
                ),
              )
            else
              for (final m in months) ...[
                SliverToBoxAdapter(
                  child: SectionTitle(
                    context.monthLabel(m.$1),
                    trailing: Text(context.tn('jr_entries', m.$2.length),
                        style: context.tt.bodySmall),
                  ),
                ),
                SliverList.list(
                  children: [
                    for (final e in m.$2) _JournalEntryCard(entry: e),
                  ],
                ),
              ],
          ],
        );
      },
    );
  }
}

/// The entry written on [day], if there is one.
Map<String, dynamic>? _entryOn(List<Map<String, dynamic>> entries, DateTime day) {
  for (final e in entries) {
    final d = parseDay(str(e['date']));
    if (d != null && sameDay(d, day)) return e;
  }
  return null;
}

/// Entries bucketed by calendar month, newest month first.
List<(DateTime, List<Map<String, dynamic>>)> _groupByMonth(List<Map<String, dynamic>> entries) {
  final out = <(DateTime, List<Map<String, dynamic>>)>[];
  for (final e in entries) {
    final d = parseDay(str(e['date']));
    if (d == null) continue;
    if (out.isNotEmpty && out.last.$1.year == d.year && out.last.$1.month == d.month) {
      out.last.$2.add(e);
    } else {
      out.add((DateTime(d.year, d.month), <Map<String, dynamic>>[e]));
    }
  }
  return out;
}

/// Days written in an unbroken run ending today (or yesterday).
int _journalStreak(List<Map<String, dynamic>> entries) {
  final days = <String>{};
  for (final e in entries) {
    final d = parseDay(str(e['date']));
    if (d != null) days.add(dayKey(d));
  }
  var day = todayDate();
  if (!days.contains(dayKey(day))) day = addDays(day, -1);
  var n = 0;
  while (days.contains(dayKey(day)) && n < 3650) {
    n++;
    day = addDays(day, -1);
  }
  return n;
}

/// Today's entry, or a gentle nudge to write one.
class _JournalTodayCard extends StatelessWidget {
  final Map<String, dynamic>? entry;
  final List<Map<String, dynamic>> entries;
  const _JournalTodayCard({required this.entry, required this.entries});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final streak = _journalStreak(entries);
    final e = entry;

    if (e != null) {
      final mood = str(e['mood']).isEmpty ? '🙂' : str(e['mood']);
      return DhCard(
        onTap: () => _openEntryEditor(context, existing: e),
        child: Row(children: [
          IconBadge(emoji: mood, color: AppColors.mJournal, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(context.t('today'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                ),
                if (streak > 1) ...[
                  const SizedBox(width: 8),
                  Pill(context.tn('jr_streak', streak),
                      color: AppColors.mJournal, icon: Icons.local_fire_department_rounded),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                str(e['text']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodySmall,
              ),
            ]),
          ),
          Icon(Icons.edit_outlined, size: 18, color: tk.textFaint),
        ]),
      );
    }

    final labels = JournalScreen.moodLabels(context);
    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(context.t('how_was_day'), style: context.tt.titleSmall)),
          if (streak > 1)
            Pill(context.tn('jr_streak', streak),
                color: AppColors.mJournal, icon: Icons.local_fire_department_rounded),
        ]),
        const SizedBox(height: 2),
        Text(context.t('jr_prompt_msg'), style: context.tt.bodySmall),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < JournalScreen.moods.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openEntryEditor(context,
                      day: todayDate(), mood: JournalScreen.moods[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      Text(JournalScreen.moods[i], style: const TextStyle(fontSize: 26, height: 1.1)),
                      const SizedBox(height: 4),
                      Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.tt.labelSmall?.copyWith(color: tk.textMuted),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

/// One past entry: date on the left, mood and the first lines beside it.
class _JournalEntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _JournalEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final e = entry;
    final d = parseDay(str(e['date']));
    final mood = str(e['mood']).isEmpty ? '🙂' : str(e['mood']);
    final isToday = d != null && sameDay(d, todayDate());

    return SwipeTile(
      swipeKey: ValueKey('journal_${str(e['id'])}'),
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        await _removeEntry(context, e);
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        onTap: () => _openEntryEditor(context, existing: e),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 46,
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  d == null ? '—' : '${d.day}',
                  style: context.tt.headlineSmall?.copyWith(
                      color: isToday ? AppColors.mJournal : context.cs.onSurface, fontSize: 24),
                ),
              ),
              Text(
                d == null ? '' : context.fmtDate(d, 'EEE'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelSmall?.copyWith(color: tk.textMuted),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(mood, style: const TextStyle(fontSize: 17, height: 1.1)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    JournalScreen.moodLabel(context, mood),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.labelMedium?.copyWith(color: tk.textMuted),
                  ),
                ),
                if (isToday) Pill(context.t('today'), color: AppColors.mJournal),
              ]),
              const SizedBox(height: 4),
              Text(
                str(e['text']),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodyMedium,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Removes an entry, recoverable for a few seconds.
Future<void> _removeEntry(BuildContext context, Map<String, dynamic> entry) async {
  final db = DbService.instance;
  final id = str(entry['id']);
  final data = Map<String, dynamic>.from(entry)..remove('id');
  await db.remove('journal', id);
  if (!context.mounted) return;
  showUndo(context, context.t('jr_deleted'), () => db.set('journal', id, data));
}

/// Write or edit one day's entry. Pass [existing] to edit, [day] to start a
/// new one on a particular date, [mood] to preselect how the day felt.
Future<void> _openEntryEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
  DateTime? day,
  String? mood,
}) async {
  final ex = existing;
  final db = DbService.instance;
  final text = TextEditingController(text: str(ex?['text']));
  final originalDay = parseDay(str(ex?['date']));
  var date = originalDay ?? day ?? todayDate();
  var pick = mood ?? (str(ex?['mood']).isEmpty ? '🙂' : str(ex?['mood']));

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      final labels = JournalScreen.moodLabels(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              ctx.t(ex == null ? 'jr_write' : 'jr_edit'),
              subtitle: ctx.dayLabel(date),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ctx.t('mood'), style: ctx.tt.labelMedium),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < JournalScreen.moods.length; i++)
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => set(() => pick = JournalScreen.moods[i]),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: pick == JournalScreen.moods[i]
                                    ? ctx.tokens.tint(AppColors.mJournal)
                                    : ctx.tokens.subtle,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: pick == JournalScreen.moods[i]
                                      ? AppColors.mJournal
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(children: [
                                Text(JournalScreen.moods[i],
                                    style: const TextStyle(fontSize: 26, height: 1.1)),
                                const SizedBox(height: 4),
                                Text(
                                  labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: ctx.tt.labelSmall?.copyWith(
                                      color: pick == JournalScreen.moods[i]
                                          ? AppColors.mJournal
                                          : ctx.tokens.textMuted),
                                ),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FormFieldButton(
                    icon: Icons.event_rounded,
                    label: ctx.t('date'),
                    value: ctx.dayLabel(date),
                    onTap: () async {
                      final now = DateTime.now();
                      final first = DateTime(now.year - 30);
                      final last = todayDate();
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: text,
                    minLines: 5,
                    maxLines: 12,
                    autofocus: ex == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: ctx.t('jr_hint')),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    if (ex != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: Text(ctx.t('delete')),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _removeEntry(context, ex);
                        },
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final body = text.text.trim();
                        if (body.isEmpty) {
                          showToast(ctx, ctx.t('jr_empty_entry'));
                          return;
                        }
                        final keepDate = originalDay != null && sameDay(originalDay, date);
                        final data = <String, dynamic>{
                          ...?ex,
                          'text': body,
                          'mood': pick,
                          'date': keepDate
                              ? str(ex?['date'])
                              : DateTime(date.year, date.month, date.day, 12).toIso8601String(),
                        }..remove('id');
                        if (ex == null) {
                          db.add('journal', data);
                        } else {
                          db.set('journal', str(ex['id']), data);
                        }
                        Navigator.pop(ctx);
                      },
                      child: Text(ctx.t('save')),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      );
    });
  });
  // Dispose after the sheet's exit animation, not while it still uses it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), text.dispose);
  });
}

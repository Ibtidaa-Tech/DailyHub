import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../data/work_store.dart';
import '../../ui/kit.dart';
import '../plan/pickers.dart';

/// Meetings, their notes, and the actions that came out of them.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key});
  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  int _tab = 0; // 0 upcoming, 1 actions, 2 past

  @override
  Widget build(BuildContext context) {
    final s = context.watch<WorkStore>();
    final actions = s.openActions;

    return AppPage(
      title: context.t('m_work'),
      subtitle: context.t('work_sub'),
      fab: FloatingActionButton.extended(
        onPressed: () => openMeetingEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('work_add')),
      ),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: PillTabs<int>(
          items: [
            (0, context.t('upcoming')),
            (1, actions.isEmpty ? context.t('work_actions') : '${context.t('work_actions')} · ${actions.length}'),
            (2, context.t('trip_past')),
          ],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      slivers: switch (_tab) {
        1 => _actionSlivers(context, s, actions),
        2 => _listSlivers(context, s.past, context.t('work_no_past'), null),
        _ => _listSlivers(context, s.upcoming, context.t('work_none'), context.t('work_none_msg')),
      },
    );
  }

  List<Widget> _listSlivers(BuildContext context, List<Meeting> list, String empty, String? msg) {
    if (list.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.groups_outlined,
            color: AppColors.mWork,
            title: empty,
            message: msg,
            actionLabel: msg == null ? null : context.t('work_add'),
            onAction: msg == null ? null : () => openMeetingEditor(context),
          ),
        ),
      ];
    }
    return [SliverList.list(children: [for (final m in list) MeetingCard(meeting: m)])];
  }

  List<Widget> _actionSlivers(BuildContext context, WorkStore s, List<(Meeting, ActionItem)> actions) {
    if (actions.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.task_alt_rounded,
            color: AppColors.mWork,
            title: context.t('work_no_actions'),
            message: context.t('work_no_actions_msg'),
          ),
        ),
      ];
    }
    return [
      SliverList.list(
        children: [
          for (final (m, a) in actions)
            DhCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => MeetingDetailScreen(meetingId: m.id))),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.circle_outlined, color: context.tokens.textFaint),
                  onPressed: () => s.toggleAction(m, m.actions.indexOf(a)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, style: context.tt.titleSmall),
                    Text(
                      [
                        if (a.owner.isNotEmpty) a.owner,
                        m.title.isEmpty ? context.t('work_untitled') : m.title,
                      ].join(' · '),
                      style: context.tt.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                ),
              ]),
            ),
        ],
      ),
    ];
  }
}

/// One meeting in the list.
class MeetingCard extends StatelessWidget {
  final Meeting meeting;
  const MeetingCard({super.key, required this.meeting});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final m = meeting;
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      borderColor: m.isNow ? context.cs.primary : null,
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => MeetingDetailScreen(meetingId: m.id))),
      child: Row(children: [
        const IconBadge(icon: Icons.groups_rounded, color: AppColors.mWork, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  m.title.isEmpty ? context.t('work_untitled') : m.title,
                  style: context.tt.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (m.isNow) Pill(context.t('st_now'), color: context.cs.primary, filled: true),
            ]),
            const SizedBox(height: 3),
            Wrap(spacing: 10, runSpacing: 2, children: [
              if (m.at != null)
                MetaChip(Icons.event_outlined, context.dayTimeLabel(m.at!, hasTime: true)),
              if (m.place.isNotEmpty) MetaChip(Icons.place_outlined, m.place),
              if (m.openActions > 0)
                MetaChip(Icons.task_alt_rounded, '${m.openActions}', color: tk.warning),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Agenda, notes and action items for one meeting.
class MeetingDetailScreen extends StatefulWidget {
  final String meetingId;
  const MeetingDetailScreen({super.key, required this.meetingId});
  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  final _notes = TextEditingController();
  final _action = TextEditingController();
  bool _notesLoaded = false;
  Timer? _saveNotes;
  WorkStore? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Held so dispose() can flush without looking the provider up again.
    _store = context.read<WorkStore>();
  }

  @override
  void dispose() {
    // Write whatever the debounce hasn't flushed yet, so leaving the screen
    // mid-sentence doesn't lose the last few words.
    if (_saveNotes?.isActive ?? false) {
      final m = _store?.byId(widget.meetingId);
      if (m != null) _store?.setNotes(m, _notes.text);
    }
    _saveNotes?.cancel();
    _notes.dispose();
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<WorkStore>();
    final m = s.byId(widget.meetingId);
    if (m == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(context.t('not_found'))));
    }
    if (!_notesLoaded) {
      _notes.text = m.notes;
      _notesLoaded = true;
    }

    return AppPage(
      title: m.title.isEmpty ? context.t('work_untitled') : m.title,
      subtitle: m.at == null ? null : context.dayTimeLabel(m.at!, hasTime: true),
      actions: [
        IconButton(
          tooltip: context.t('share'),
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => _share(context, m),
        ),
        IconButton(
          tooltip: context.t('edit'),
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => openMeetingEditor(context, meeting: m),
        ),
      ],
      slivers: [
        if (m.place.isNotEmpty || m.attendeeList.isNotEmpty)
          SliverToBoxAdapter(
            child: DhCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (m.place.isNotEmpty)
                  Row(children: [
                    Icon(Icons.place_outlined, size: 18, color: context.tokens.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m.place, style: context.tt.bodyMedium)),
                  ]),
                if (m.attendeeList.isNotEmpty) ...[
                  if (m.place.isNotEmpty) const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final n in m.attendeeList)
                      Chip(
                        avatar: InitialsAvatar(n, size: 22, color: AppColors.mWork),
                        label: Text(n),
                        visualDensity: VisualDensity.compact,
                      ),
                  ]),
                ],
              ]),
            ),
          ),
        if (m.agenda.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('work_agenda'))),
          SliverToBoxAdapter(child: DhCard(child: Text(m.agenda, style: context.tt.bodyMedium))),
        ],
        SliverToBoxAdapter(child: SectionTitle(context.t('work_notes'))),
        SliverToBoxAdapter(
          child: DhCard(
            child: TextField(
              controller: _notes,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t('work_notes_hint'),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              // One write per keystroke would hammer the database; settle first.
              onChanged: (v) {
                _saveNotes?.cancel();
                _saveNotes = Timer(const Duration(milliseconds: 700), () => s.setNotes(m, v));
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('work_actions'))),
        SliverToBoxAdapter(child: _Actions(meeting: m, controller: _action)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                icon: Icon(m.done ? Icons.undo_rounded : Icons.check_circle_outline_rounded, size: 18),
                label: Text(context.t(m.done ? 'reopen' : 'work_mark_done')),
                onPressed: () => s.setDone(m, !m.done),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: context.tokens.danger),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(context.t('delete')),
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: context.t('work_delete_q'), danger: true, confirm: context.t('delete'));
                  if (!ok || !context.mounted) return;
                  final data = s.delete(m);
                  Navigator.pop(context);
                  if (context.mounted) {
                    showUndo(context, context.t('work_deleted'), () => s.restore(m.id, data));
                  }
                },
              ),
            ]),
          ),
        ),
      ],
    );
  }

  void _share(BuildContext context, Meeting m) {
    final lines = <String>[
      m.title,
      if (m.at != null) context.dayTimeLabel(m.at!, hasTime: true),
      if (m.attendees.isNotEmpty) '${context.t('work_attendees')}: ${m.attendees}',
      if (m.notes.isNotEmpty) '\n${m.notes}',
      if (m.actions.isNotEmpty) '\n${context.t('work_actions')}:',
      for (final a in m.actions)
        '${a.done ? '[x]' : '[ ]'} ${a.title}${a.owner.isEmpty ? '' : ' — ${a.owner}'}',
    ];
    Share.share(lines.where((e) => e.trim().isNotEmpty).join('\n'));
  }
}

class _Actions extends StatelessWidget {
  final Meeting meeting;
  final TextEditingController controller;
  const _Actions({required this.meeting, required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = context.read<WorkStore>();
    final plan = context.read<PlanStore>();
    final tk = context.tokens;
    final m = meeting;

    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.actions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(context.t('work_no_actions_yet'), style: context.tt.bodySmall),
          )
        else
          for (var i = 0; i < m.actions.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    m.actions[i].done ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 20,
                    color: m.actions[i].done ? tk.success : tk.textFaint,
                  ),
                  onPressed: () => s.toggleAction(m, i),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      m.actions[i].title,
                      style: context.tt.bodyMedium?.copyWith(
                        decoration: m.actions[i].done ? TextDecoration.lineThrough : null,
                        color: m.actions[i].done ? tk.textFaint : null,
                      ),
                    ),
                    if (m.actions[i].owner.isNotEmpty)
                      Text(m.actions[i].owner, style: context.tt.bodySmall),
                  ]),
                ),
                if (m.actions[i].taskId.isEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.t('work_to_task'),
                    icon: Icon(Icons.playlist_add_rounded, size: 20, color: context.cs.primary),
                    onPressed: () {
                      final a = m.actions[i];
                      final id = plan.saveTask(Task(
                        // An empty list is the Inbox; 'inbox' is only a query id,
                        // so storing it would hide the task from every list.
                        title: a.title,
                        desc: m.title.isEmpty ? '' : context.tr('work_from_meeting', {'m': m.title}),
                      ));
                      final items = List<ActionItem>.from(m.actions);
                      items[i] = ActionItem(
                          title: a.title, done: a.done, taskId: id, owner: a.owner);
                      s.setActions(m, items);
                      showToast(context, context.t('work_added_to_plan'),
                          icon: Icons.check_circle_rounded);
                    },
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.playlist_add_check_rounded, size: 18, color: tk.success),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 16, color: tk.textFaint),
                  onPressed: () {
                    final items = List<ActionItem>.from(m.actions)..removeAt(i);
                    s.setActions(m, items);
                  },
                ),
              ]),
            ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('work_add_action'),
            prefixIcon: const Icon(Icons.add_rounded),
            isDense: true,
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isEmpty) return;
            s.setActions(m, [...m.actions, ActionItem(title: t)]);
            controller.clear();
          },
        ),
      ]),
    );
  }
}

/// Add or edit a meeting.
Future<void> openMeetingEditor(BuildContext context, {Meeting? meeting}) async {
  final s = context.read<WorkStore>();
  final title = TextEditingController(text: meeting?.title ?? '');
  final place = TextEditingController(text: meeting?.place ?? '');
  final attendees = TextEditingController(text: meeting?.attendees ?? '');
  final agenda = TextEditingController(text: meeting?.agenda ?? '');
  var at = meeting?.at ?? DateTime.now().add(const Duration(hours: 1));
  var minutes = meeting?.minutes ?? 30;

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(meeting == null ? 'work_add' : 'work_edit'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              autofocus: meeting == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ctx.t('work_title_hint'),
                prefixIcon: const Icon(Icons.groups_outlined),
              ),
            ),
            const SizedBox(height: 12),
            FormFieldButton(
              icon: Icons.event_rounded,
              label: ctx.t('when'),
              value: ctx.dayTimeLabel(at, hasTime: true),
              onTap: () async {
                final picked = await pickDateTime(ctx, initial: at);
                if (picked != null) set(() => at = picked);
              },
            ),
            const SizedBox(height: 12),
            Text(ctx.t('work_length'), style: ctx.tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final mn in [15, 30, 45, 60, 90, 120])
                ChoiceChip(
                  label: Text(ctx.tr('work_n_min', {'n': mn})),
                  selected: minutes == mn,
                  onSelected: (_) => set(() => minutes = mn),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: place,
              decoration: InputDecoration(
                hintText: ctx.t('work_place_hint'),
                prefixIcon: const Icon(Icons.place_outlined),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: attendees,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t('work_attendees_hint'),
                prefixIcon: const Icon(Icons.people_outline_rounded),
                isDense: true,
              ),
            ),
            if (s.knownAttendees.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final n in s.knownAttendees.take(8))
                    ActionChip(
                      label: Text(n),
                      onPressed: () {
                        final have = attendees.text
                            .split(RegExp(r'[,;]'))
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        if (have.map((e) => e.toLowerCase()).contains(n.toLowerCase())) return;
                        attendees.text = [...have, n].join(', ');
                        set(() {});
                      },
                    ),
                ]),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: agenda,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ctx.t('work_agenda_hint'),
                prefixIcon: const Icon(Icons.list_alt_rounded),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) {
                  showToast(ctx, ctx.t('work_enter_title'));
                  return;
                }
                s.save(Meeting(
                  id: meeting?.id ?? '',
                  title: title.text.trim(),
                  at: at,
                  minutes: minutes,
                  place: place.text.trim(),
                  attendees: attendees.text.trim(),
                  agenda: agenda.text.trim(),
                  notes: meeting?.notes ?? '',
                  done: meeting?.done ?? false,
                  actions: meeting?.actions ?? [],
                ));
                Navigator.pop(ctx);
              },
              child: Text(ctx.t('save')),
            ),
          ]),
        ),
      );
    });
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in [title, place, attendees, agenda]) {
        c.dispose();
      }
    });
  });
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/life_store.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/plan_store.dart';
import '../../screens/bookmarks_screen.dart';
import '../../screens/journal_screen.dart';
import '../shopping/shopping_screen.dart';
import '../student/student_screen.dart';
import '../../data/shopping_store.dart';
import '../../data/trip_store.dart';
import '../trips/trip_detail.dart';
import '../trips/trips_screen.dart';
import '../../data/work_store.dart';
import '../work/work_screen.dart';
import '../../services/db_service.dart';
import '../../ui/kit.dart';
import '../habits/habits_screen.dart';
import '../money/bills_screen.dart';
import '../money/ledger_screen.dart';
import '../money/money_ui.dart';
import '../money/txn_editor.dart';
import '../notes/note_editor.dart';
import '../plan/reminder_editor.dart';
import '../plan/task_editor.dart';

class _Hit {
  final String group;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final void Function(BuildContext) open;
  _Hit(this.group, this.icon, this.color, this.title, this.subtitle, this.open);
}

/// One box, results from every module grouped by type.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  String _q = '';
  final Map<String, List<Map<String, dynamic>>> _legacy = {};
  final List<dynamic> _subs = [];

  static const _legacyCollections = {
    'assignments': false,
    'bookmarks': false,
    'journal': false,
  };

  @override
  void initState() {
    super.initState();
    final db = DbService.instance;
    _legacyCollections.forEach((c, ws) {
      _subs.add(db.stream(c, workspace: ws).listen((v) {
        if (mounted) setState(() => _legacy[c] = v);
      }));
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _c.dispose();
    super.dispose();
  }

  bool _m(String q, List<Object?> fields) => fields.any((f) => (f ?? '').toString().toLowerCase().contains(q));

  void _push(BuildContext context, Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  List<_Hit> _results(BuildContext context) {
    final q = _q.toLowerCase();
    if (q.length < 2) return [];
    final plan = context.read<PlanStore>();
    final money = context.read<MoneyStore>();
    final notes = context.read<NotesStore>();
    final habits = context.read<HabitsStore>();
    final settings = context.read<AppSettings>();
    final out = <_Hit>[];

    for (final t in plan.tasks) {
      if (_m(q, [t.title, t.desc, ...t.tags, ...t.subtasks.map((s) => s.title)])) {
        out.add(_Hit(context.t('m_tasks'), t.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            AppColors.mTasks, t.title, t.dueDate == null ? '' : context.dayLabel(t.dueDate!), (c) => openTaskEditor(c, task: t)));
      }
    }
    for (final r in plan.reminders) {
      if (_m(q, [r.title, r.notes])) {
        out.add(_Hit(context.t('m_reminders'), Icons.notifications_active_outlined, AppColors.mReminders, r.title,
            r.when == null ? '' : context.dayTimeLabel(r.when!), (c) => openReminderEditor(c, reminder: r)));
      }
    }
    for (final n in notes.notes) {
      if (_m(q, [n.title, n.body, ...n.labels, ...n.checklist.map((c) => c.title)])) {
        out.add(_Hit(context.t('m_notes'), Icons.sticky_note_2_outlined, AppColors.mNotes,
            n.title.isNotEmpty ? n.title : n.preview.split('\n').first, n.labels.join(', '), (c) => openNoteEditor(c, note: n)));
      }
    }
    if (settings.isOn('money')) {
      for (final t in money.txns) {
        final cat = categoryName(context, money.catById(t.category));
        if (_m(q, [t.note, cat, t.amount.toStringAsFixed(0)])) {
          out.add(_Hit(context.t('m_money'), Icons.receipt_long_outlined, typeColor(context, t.type),
              t.note.isNotEmpty ? t.note : cat, '${Money.format(t.amount)} · ${context.dayLabel(t.day, short: true)}',
              (c) => openTxnEditor(c, txn: t)));
        }
        if (out.length > 300) break;
      }
      for (final b in money.bills) {
        if (_m(q, [b.name])) {
          out.add(_Hit(context.t('m_bills'), Icons.receipt_long_rounded, AppColors.mReminders, '${b.emoji} ${b.name}',
              Money.format(b.amount), (c) => BillsScreen.editBill(c, bill: b)));
        }
      }
      for (final d in money.debts) {
        if (_m(q, [d.person, d.note])) {
          out.add(_Hit(context.t('m_ledger'), Icons.handshake_outlined, AppColors.mJournal, d.person,
              '${context.t(d.isLent ? 'i_lent' : 'i_borrowed')} · ${Money.format(d.amount)}', (c) => LedgerScreen.editDebt(c, debt: d)));
        }
      }
    }
    for (final h in habits.habits) {
      if (_m(q, [h.name])) {
        out.add(_Hit(context.t('m_habits'), Icons.local_fire_department_outlined, AppColors.mHabits, '${h.emoji} ${h.name}',
            '🔥 ${h.streak()}', (c) => _push(c, HabitDetailScreen(habitId: h.id))));
      }
    }
    if (settings.isOn('trips')) {
      for (final t in context.read<TripStore>().trips) {
        if (_m(q, [t.from, t.to, t.pnr, t.operator, t.notes])) {
          out.add(_Hit(context.t('m_trips'), tripIcon(t.mode), AppColors.mTrips,
              t.route.isEmpty ? context.t('trip_untitled') : t.route,
              t.departure == null ? '' : context.dayLabel(t.departure!, short: true),
              (c) => _push(c, TripDetailScreen(tripId: t.id))));
        }
      }
    }
    if (settings.isOn('work')) {
      for (final m in context.read<WorkStore>().meetings) {
        if (_m(q, [m.title, m.notes, m.agenda, m.attendees])) {
          out.add(_Hit(context.t('m_work'), Icons.groups_rounded, AppColors.mWork,
              m.title.isEmpty ? context.t('work_untitled') : m.title,
              m.at == null ? '' : context.dayLabel(m.at!, short: true),
              (c) => _push(c, MeetingDetailScreen(meetingId: m.id))));
        }
      }
    }
    for (final a in _legacy['assignments'] ?? const <Map<String, dynamic>>[]) {
      if (_m(q, [a['title'], a['subject']])) {
        out.add(_Hit(context.t('m_student'), Icons.assignment_rounded, AppColors.mStudy, str(a['title']), str(a['subject']),
            (c) => _push(c, const StudentScreen())));
      }
    }
    if (settings.isOn('shopping')) {
      for (final i in context.read<ShoppingStore>().items) {
        if (_m(q, [i.name, i.list, i.qty])) {
          out.add(_Hit(context.t('m_shopping'), Icons.shopping_cart_outlined, AppColors.mShopping,
              i.name, i.list, (c) => _push(c, const ShoppingScreen())));
        }
      }
    }
    for (final b in _legacy['bookmarks'] ?? const <Map<String, dynamic>>[]) {
      if (_m(q, [b['title'], b['url']])) {
        out.add(_Hit(context.t('m_bookmarks'), Icons.bookmark_outline_rounded, AppColors.mBookmarks,
            str(b['title']).isEmpty ? str(b['url']) : str(b['title']), str(b['url']), (c) => _push(c, const BookmarksScreen())));
      }
    }
    for (final j in _legacy['journal'] ?? const <Map<String, dynamic>>[]) {
      if (_m(q, [j['text']])) {
        out.add(_Hit(context.t('m_journal'), Icons.auto_stories_outlined, AppColors.mJournal, str(j['text']), '',
            (c) => _push(c, const JournalScreen())));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<PlanStore>();
    context.watch<MoneyStore>();
    context.watch<NotesStore>();
    final results = _results(context);
    final grouped = <String, List<_Hit>>{};
    for (final r in results) {
      grouped.putIfAbsent(r.group, () => []).add(r);
    }
    final pad = sidePad(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _c,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.t('search_everything'),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _c.clear();
                setState(() => _q = '');
              },
            ),
        ],
      ),
      body: _q.length < 2
          ? EmptyView(icon: Icons.search_rounded, title: context.t('search_title'), message: context.t('search_msg'))
          : results.isEmpty
              ? EmptyView(icon: Icons.search_off_rounded, title: context.t('no_results'), message: context.tr('no_results_for', {'q': _q}))
              : ListView(
                  padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
                  children: [
                    for (final e in grouped.entries) ...[
                      SectionTitle('${e.key} · ${e.value.length}'),
                      GroupCard(children: [
                        for (final r in e.value.take(25))
                          ListTile(
                            leading: Icon(r.icon, color: r.color),
                            title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: r.subtitle.isEmpty ? null : Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => r.open(context),
                          ),
                      ]),
                    ],
                  ],
                ),
    );
  }
}

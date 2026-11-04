import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import 'pickers.dart';

/// Opens the reminder editor. Reminders are pure time-based alerts that fire
/// even when the app is closed; they can repeat.
Future<void> openReminderEditor(BuildContext context, {Reminder? reminder, DateTime? when, String? title}) {
  final store = context.read<PlanStore>();
  return showAppSheet(
    context,
    builder: (ctx) => ChangeNotifierProvider.value(
      value: store,
      child: _ReminderSheet(reminder: reminder, when: when, title: title),
    ),
  );
}

class _ReminderSheet extends StatefulWidget {
  final Reminder? reminder;
  final DateTime? when;
  final String? title;
  const _ReminderSheet({this.reminder, this.when, this.title});
  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _when;
  late String _repeat;

  bool get _isNew => widget.reminder == null;

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    _title = TextEditingController(text: r?.title ?? widget.title ?? '');
    _notes = TextEditingController(text: r?.notes ?? '');
    final base = DateTime.now().add(const Duration(hours: 1));
    _when = r?.when ?? widget.when ?? DateTime(base.year, base.month, base.day, base.hour, 0);
    _repeat = r?.repeat ?? 'once';
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final store = context.read<PlanStore>();
    final r = widget.reminder ?? Reminder();
    r
      ..title = _title.text.trim()
      ..notes = _notes.text.trim()
      ..when = _when
      ..repeat = _repeat
      ..done = false;
    store.saveReminder(r);
    Navigator.pop(context);
    showToast(context, context.tr('reminder_set_for', {'when': context.dayTimeLabel(_when)}),
        icon: Icons.notifications_active_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final past = _when.isBefore(DateTime.now()) && _repeat == 'once';
    return SafeArea(
      // Scrollable so the form doesn't overflow on small screens with the keyboard open.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const IconBadge(icon: Icons.notifications_active_rounded, color: AppColors.mReminders, size: 36),
            const SizedBox(width: 12),
            Text(context.t(_isNew ? 'new_reminder' : 'edit_reminder'), style: context.tt.titleLarge),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            autofocus: _isNew && _title.text.isEmpty,
            textCapitalization: TextCapitalization.sentences,
            style: context.tt.titleMedium,
            decoration: InputDecoration(hintText: context.t('reminder_title_hint')),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _Field(
                icon: Icons.event_rounded,
                label: context.dayLabel(_when),
                danger: past,
                onTap: () async {
                  final d = await pickDay(context, initial: _when, allowNone: false);
                  final v = d?.value;
                  if (v != null) setState(() => _when = DateTime(v.year, v.month, v.day, _when.hour, _when.minute));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Field(
                icon: Icons.schedule_rounded,
                label: context.timeOf(_when),
                danger: past,
                onTap: () async {
                  final t = await pickTime(context, initial: TimeOfDay.fromDateTime(_when), allowNone: false);
                  final v = t?.value;
                  if (v != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, v.hour, v.minute));
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _Field(
            icon: Icons.repeat_rounded,
            label: repeatLabel(context, _repeat),
            onTap: () async {
              final r = await pickRepeat(context, _repeat, once: true);
              if (r != null) setState(() => _repeat = r == 'none' ? 'once' : r);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: context.t('notes_optional'), prefixIcon: const Icon(Icons.notes_rounded)),
          ),
          if (past)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.t('time_in_past'), style: context.tt.bodySmall?.copyWith(color: tk.danger)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            if (!_isNew)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: tk.danger),
                onPressed: () {
                  final store = context.read<PlanStore>();
                  final r = widget.reminder!;
                  final data = store.deleteReminder(r);
                  Navigator.pop(context);
                  showUndo(context, context.t('reminder_deleted'), () => store.restoreReminder(r.id, data));
                },
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: Text(context.t(_isNew ? 'set_reminder' : 'save')),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _Field({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Material(
      color: tk.subtle,
      borderRadius: BorderRadius.circular(Radii.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 20, color: danger ? tk.danger : tk.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelLarge?.copyWith(color: danger ? tk.danger : null)),
            ),
            Icon(Icons.expand_more_rounded, color: tk.textFaint),
          ]),
        ),
      ),
    );
  }
}

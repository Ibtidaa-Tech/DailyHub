import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/student_store.dart';
import '../../ui/kit.dart';
import '../plan/pickers.dart';
import 'timetable_view.dart';

/// Disposes a sheet's controllers after its exit animation, never during it.
void _disposeLater(List<TextEditingController> cs) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in cs) {
        c.dispose();
      }
    });
  });
}

/// Suggests subjects the user already has, so names stay consistent.
Widget _subjectSuggestions(BuildContext ctx, StudentStore s, TextEditingController c, VoidCallback onPick) {
  final names = s.subjectNames;
  if (names.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(spacing: 8, runSpacing: 8, children: [
      for (final n in names.take(12))
        ActionChip(
          label: Text(n),
          onPressed: () {
            c.text = n;
            onPick();
          },
        ),
    ]),
  );
}

// ------------------------------------------------------------- timetable

Future<void> editClass(BuildContext context, {Klass? klass, String? day}) async {
  final s = context.read<StudentStore>();
  final subject = TextEditingController(text: klass?.subject ?? '');
  final room = TextEditingController(text: klass?.room ?? '');
  final teacher = TextEditingController(text: klass?.teacher ?? '');
  var d = klass?.day ?? day ?? dayKeyOfWeekday(DateTime.now().weekday);
  var start = klass?.start ?? '09:00';
  var end = klass?.end ?? '10:00';

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(klass == null ? 'st_add_class' : 'st_edit_class'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: subject,
              autofocus: klass == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t('st_subject_hint'),
                prefixIcon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            _subjectSuggestions(ctx, s, subject, () => set(() {})),
            const SizedBox(height: 12),
            Text(ctx.t('st_which_day'), style: ctx.tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in kDayKeys)
                ChoiceChip(
                  label: Text(dayLabelOf(ctx, k)),
                  selected: d == k,
                  onSelected: (_) => set(() => d = k),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FormFieldButton(
                  icon: Icons.schedule_rounded,
                  label: ctx.t('st_starts'),
                  value: ctx.timeOfHm(start),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: ctx, initialTime: parseHm(start) ?? const TimeOfDay(hour: 9, minute: 0));
                    if (t == null) return;
                    set(() {
                      start = hmKey(t.hour, t.minute);
                      // Keep the end after the start.
                      final e = parseHm(end);
                      if (e == null || e.hour * 60 + e.minute <= t.hour * 60 + t.minute) {
                        final mins = t.hour * 60 + t.minute + 60;
                        end = hmKey((mins ~/ 60) % 24, mins % 60);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldButton(
                  icon: Icons.schedule_outlined,
                  label: ctx.t('st_ends'),
                  value: ctx.timeOfHm(end),
                  onTap: () async {
                    final t = await showTimePicker(
                        context: ctx, initialTime: parseHm(end) ?? const TimeOfDay(hour: 10, minute: 0));
                    if (t != null) set(() => end = hmKey(t.hour, t.minute));
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: room,
                  decoration: InputDecoration(
                    hintText: ctx.t('st_room_hint'),
                    prefixIcon: const Icon(Icons.meeting_room_outlined),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: teacher,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: ctx.t('st_teacher_hint'),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              if (klass != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(ctx.t('delete')),
                  onPressed: () async {
                    final ok = await confirmDialog(ctx,
                        title: ctx.t('st_delete_class_q'), danger: true, confirm: ctx.t('delete'));
                    if (!ok || !ctx.mounted) return;
                    final data = s.deleteClass(klass);
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      showUndo(context, context.t('st_class_deleted'),
                          () => s.restore('timetable', klass.id, data));
                    }
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (subject.text.trim().isEmpty) {
                    showToast(ctx, ctx.t('st_enter_subject'));
                    return;
                  }
                  s.saveClass(Klass(
                    id: klass?.id ?? '',
                    subject: subject.text.trim(),
                    room: room.text.trim(),
                    teacher: teacher.text.trim(),
                    day: d,
                    start: start,
                    end: end,
                  ));
                  Navigator.pop(ctx);
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ]),
        ),
      );
    });
  });
  _disposeLater([subject, room, teacher]);
}

// ------------------------------------------------------------ assignment

Future<void> editAssignment(BuildContext context, {Assignment? assignment}) async {
  final s = context.read<StudentStore>();
  final title = TextEditingController(text: assignment?.title ?? '');
  final subject = TextEditingController(text: assignment?.subject ?? '');
  final notes = TextEditingController(text: assignment?.notes ?? '');
  DateTime? due = assignment?.dueDate;

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(assignment == null ? 'st_add_assignment' : 'st_edit_assignment'),
                style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              autofocus: assignment == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ctx.t('st_work_hint'),
                prefixIcon: const Icon(Icons.assignment_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subject,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t('st_subject_hint'),
                prefixIcon: const Icon(Icons.menu_book_outlined),
                isDense: true,
              ),
            ),
            _subjectSuggestions(ctx, s, subject, () => set(() {})),
            const SizedBox(height: 12),
            FormFieldButton(
              icon: Icons.event_outlined,
              label: ctx.t('st_due'),
              value: due == null ? ctx.t('no_date') : ctx.dayLabel(due!),
              onTap: () async {
                final picked = await pickDay(ctx, initial: due, allowNone: true);
                if (picked != null) set(() => due = picked.value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ctx.t('notes_optional'),
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              if (assignment != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(ctx.t('delete')),
                  onPressed: () {
                    final data = s.deleteAssignment(assignment);
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      showUndo(context, context.t('st_assignment_deleted'),
                          () => s.restore('assignments', assignment.id, data));
                    }
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (title.text.trim().isEmpty) {
                    showToast(ctx, ctx.t('st_enter_work'));
                    return;
                  }
                  s.saveAssignment(Assignment(
                    id: assignment?.id ?? '',
                    title: title.text.trim(),
                    subject: subject.text.trim(),
                    due: due == null ? '' : dayKey(due!),
                    notes: notes.text.trim(),
                    done: assignment?.done ?? false,
                  ));
                  Navigator.pop(ctx);
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ]),
        ),
      );
    });
  });
  _disposeLater([title, subject, notes]);
}

// --------------------------------------------------------------- subject

Future<void> editSubject(BuildContext context, {SubjectInfo? subject}) async {
  final s = context.read<StudentStore>();
  final name = TextEditingController(text: subject?.name ?? '');
  final code = TextEditingController(text: subject?.code ?? '');
  double credits = subject?.credits ?? 3;
  var grade = subject?.grade ?? '';
  var color = subject?.color ?? s.subjects.length;

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(subject == null ? 'st_add_subject' : 'st_edit_subject'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              autofocus: subject == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t('st_subject_hint'),
                prefixIcon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: ctx.t('st_code_hint'),
                prefixIcon: const Icon(Icons.tag_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Text(ctx.t('st_credits'), style: ctx.tt.bodyLarge),
              const Spacer(),
              IconButton.filledTonal(
                icon: const Icon(Icons.remove_rounded, size: 18),
                onPressed: () => set(() => credits = (credits - 1).clamp(1, 20).toDouble()),
              ),
              SizedBox(
                width: 42,
                child: Text('${credits.round()}', textAlign: TextAlign.center, style: ctx.tt.titleMedium),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: () => set(() => credits = (credits + 1).clamp(1, 20).toDouble()),
              ),
            ]),
            const SizedBox(height: 14),
            Text(ctx.t('st_grade'), style: ctx.tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text(ctx.t('st_no_grade')),
                selected: grade.isEmpty,
                onSelected: (_) => set(() => grade = ''),
              ),
              for (final g in kGradePoints.keys)
                ChoiceChip(
                  label: Text(g),
                  selected: grade == g,
                  onSelected: (_) => set(() => grade = g),
                ),
            ]),
            const SizedBox(height: 14),
            ColorDots(value: color, onChanged: (v) => set(() => color = v)),
            const SizedBox(height: 18),
            Row(children: [
              if (subject != null)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(ctx.t('delete')),
                  onPressed: () {
                    final data = s.deleteSubject(subject);
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      showUndo(context, context.t('st_subject_deleted'),
                          () => s.restore('subjects', subject.id, data));
                    }
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) {
                    showToast(ctx, ctx.t('st_enter_subject'));
                    return;
                  }
                  s.saveSubject(SubjectInfo(
                    id: subject?.id ?? '',
                    name: name.text.trim(),
                    code: code.text.trim(),
                    credits: credits,
                    grade: grade,
                    color: color,
                  ));
                  Navigator.pop(ctx);
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ]),
        ),
      );
    });
  });
  _disposeLater([name, code]);
}

// ------------------------------------------------------------ attendance

/// Starts tracking attendance for a subject.
Future<void> addSubjectForAttendance(BuildContext context) async {
  final s = context.read<StudentStore>();
  final name = TextEditingController();
  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t('st_track_subject'), style: ctx.tt.titleLarge),
            const SizedBox(height: 6),
            Text(ctx.t('st_track_subject_sub'), style: ctx.tt.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t('st_subject_hint'),
                prefixIcon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            _subjectSuggestions(ctx, s, name, () => set(() {})),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                final n = name.text.trim();
                if (n.isEmpty) {
                  showToast(ctx, ctx.t('st_enter_subject'));
                  return;
                }
                s.setAttendanceBase(n, s.attendanceFor(n)?.baseAttended ?? 0, s.attendanceFor(n)?.baseTotal ?? 0);
                Navigator.pop(ctx);
              },
              child: Text(ctx.t('save')),
            ),
          ]),
        ),
      );
    });
  });
  _disposeLater([name]);
}

/// Lets the user set where they already stood before using the app.
Future<void> editAttendanceBase(BuildContext context, Attendance record) async {
  final s = context.read<StudentStore>();
  var attended = record.baseAttended;
  var total = record.baseTotal;

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(record.subject, subtitle: ctx.t('st_starting_counts')),
            _Counter(
              label: ctx.t('st_classes_attended'),
              value: attended,
              onChanged: (v) => set(() {
                attended = v;
                if (total < attended) total = attended;
              }),
            ),
            _Counter(
              label: ctx.t('st_classes_held'),
              value: total,
              onChanged: (v) => set(() {
                total = v;
                if (attended > total) attended = total;
              }),
            ),
            if (record.log.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  ctx.tr('st_plus_marked', {'a': record.loggedPresent, 'b': record.loggedPresent + record.loggedAbsent}),
                  style: ctx.tt.bodySmall,
                ),
              ),
            const SizedBox(height: 18),
            Row(children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(ctx.t('st_stop_tracking')),
                onPressed: () async {
                  final ok = await confirmDialog(ctx,
                      title: ctx.t('st_stop_tracking_q'), danger: true, confirm: ctx.t('delete'));
                  if (!ok || !ctx.mounted) return;
                  final data = s.deleteAttendance(record);
                  Navigator.pop(ctx);
                  if (context.mounted) {
                    showUndo(context, context.t('st_tracking_stopped'),
                        () => s.restore('attendance', record.id, data));
                  }
                },
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  s.setAttendanceBase(record.subject, attended, total);
                  Navigator.pop(ctx);
                },
                child: Text(ctx.t('save')),
              ),
            ]),
          ]),
        ),
      );
    });
  });
}

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _Counter({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: context.tt.bodyLarge)),
        IconButton.filledTonal(
          icon: const Icon(Icons.remove_rounded, size: 18),
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 48,
          child: Text('$value', textAlign: TextAlign.center, style: context.tt.titleMedium),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.add_rounded, size: 18),
          onPressed: () => onChanged(value + 1),
        ),
      ]),
    );
  }
}

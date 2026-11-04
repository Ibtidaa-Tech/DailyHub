import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/quick_parse.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/life_store.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import '../plan/pickers.dart';

IconData captureIcon(CaptureKind k) => switch (k) {
      CaptureKind.task => Icons.check_circle_outline_rounded,
      CaptureKind.reminder => Icons.notifications_active_outlined,
      CaptureKind.expense => Icons.north_east_rounded,
      CaptureKind.income => Icons.south_west_rounded,
      CaptureKind.note => Icons.sticky_note_2_outlined,
      CaptureKind.lent => Icons.call_made_rounded,
      CaptureKind.borrowed => Icons.call_received_rounded,
    };

Color captureColor(BuildContext context, CaptureKind k) => switch (k) {
      CaptureKind.task => AppColors.mTasks,
      CaptureKind.reminder => AppColors.mReminders,
      CaptureKind.expense => context.tokens.expense,
      CaptureKind.income => context.tokens.income,
      CaptureKind.note => AppColors.mNotes,
      CaptureKind.lent || CaptureKind.borrowed => AppColors.mJournal,
    };

String captureLabel(BuildContext context, CaptureKind k) => switch (k) {
      CaptureKind.task => context.t('task'),
      CaptureKind.reminder => context.t('reminder'),
      CaptureKind.expense => context.t('spent'),
      CaptureKind.income => context.t('earned'),
      CaptureKind.note => context.t('note'),
      CaptureKind.lent => context.t('i_lent'),
      CaptureKind.borrowed => context.t('i_borrowed'),
    };

/// One-line summary of what will be created.
String captureSummary(BuildContext context, Parsed p) {
  final bits = <String>[];
  if (p.isMoney && p.amount != null) bits.add(Money.format(p.amount!));
  if (p.person.isNotEmpty) bits.add(p.person);
  if (p.kind == CaptureKind.reminder) {
    bits.add(context.dayTimeLabel(p.reminderTime()));
  } else if (p.date != null && !p.isMoney) {
    bits.add(context.dayTimeLabel(p.date!, hasTime: p.hasTime));
  }
  if (p.repeat != 'none') bits.add(repeatLabel(context, p.repeat));
  if (p.priority != 'none') bits.add(prioLabel(context, p.priority));
  bits.addAll(p.tags.map((t) => '#$t'));
  return bits.join(' · ');
}

/// Creates records for parsed items. Returns an undo callback.
VoidCallback saveParsed(BuildContext context, List<Parsed> items) {
  final plan = context.read<PlanStore>();
  final money = context.read<MoneyStore>();
  final notes = context.read<NotesStore>();
  final settings = context.read<AppSettings>();
  final created = <(String, String)>[]; // (collection, id)
  for (final p in items) {
    final title = p.title.isEmpty ? p.source : p.title;
    switch (p.kind) {
      case CaptureKind.task:
        final id = plan.saveTask(Task(
          title: title,
          date: p.date == null ? '' : dayKey(p.date!),
          time: p.hasTime && p.date != null ? hmOf(p.date!) : '',
          priority: p.priority,
          repeat: p.repeat,
          tags: p.tags,
        ));
        created.add(('todos', id));
        break;
      case CaptureKind.reminder:
        final id = plan.saveReminder(Reminder(
          title: title,
          when: p.reminderTime(),
          repeat: p.repeat == 'none' ? 'once' : p.repeat,
        ));
        created.add(('reminders', id));
        break;
      case CaptureKind.expense:
      case CaptureKind.income:
        final kind = p.kind == CaptureKind.income ? 'income' : 'expense';
        final acc = money.accountById(settings.defaultAccount) != null ? settings.defaultAccount : money.defaultAccountId;
        final id = money.saveTxn(Txn(
          type: kind,
          amount: p.amount ?? 0,
          category: money.guessCategory(title, kind),
          note: title,
          date: dayKey(p.date ?? DateTime.now()),
          time: hmOf(DateTime.now()),
          account: acc,
        ));
        created.add(('txns', id));
        break;
      case CaptureKind.note:
        final id = notes.save(Note(body: p.source.replaceFirst(RegExp(r'^\s*(note|idea|n)\s*:\s*', caseSensitive: false), '')));
        created.add(('notes', id));
        break;
      case CaptureKind.lent:
      case CaptureKind.borrowed:
        final id = money.saveDebt(Debt(
          person: p.person.isEmpty ? context.t('someone') : p.person,
          kind: p.kind == CaptureKind.lent ? 'lent' : 'borrowed',
          amount: p.amount ?? 0,
          note: title,
        ));
        created.add(('debts', id));
        break;
    }
  }
  return () {
    for (final c in created) {
      switch (c.$1) {
        case 'todos':
          final t = plan.taskById(c.$2);
          if (t != null) plan.deleteTask(t);
          break;
        case 'reminders':
          final r = plan.reminderById(c.$2);
          if (r != null) plan.deleteReminder(r);
          break;
        case 'txns':
          money.deleteTxn(Txn(id: c.$2));
          break;
        case 'notes':
          final n = notes.byId(c.$2);
          if (n != null) notes.delete(n);
          break;
        case 'debts':
          money.deleteDebt(Debt(id: c.$2));
          break;
      }
    }
  };
}

/// The "Add anything…" box with live understanding and one-tap save.
class SmartCaptureField extends StatefulWidget {
  final bool autofocus;
  final VoidCallback? onSaved;
  final bool compact;
  const SmartCaptureField({super.key, this.autofocus = false, this.onSaved, this.compact = false});
  @override
  State<SmartCaptureField> createState() => _SmartCaptureFieldState();
}

class _SmartCaptureFieldState extends State<SmartCaptureField> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  List<Parsed> _items = [];
  final Map<int, CaptureKind> _overrides = {};

  @override
  void initState() {
    super.initState();
    _c.addListener(_parse);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _parse() {
    final text = _c.text.trim();
    setState(() {
      _items = text.isEmpty ? [] : QuickParse.parseAll(text);
      _overrides.removeWhere((k, _) => k >= _items.length);
      for (final e in _overrides.entries) {
        _items[e.key].kind = e.value;
      }
    });
  }

  void _save() {
    if (_items.isEmpty) return;
    final valid = _items.where((p) => !p.isMoney || (p.amount ?? 0) > 0).toList();
    if (valid.isEmpty) {
      showToast(context, context.t('enter_amount'));
      return;
    }
    final undo = saveParsed(context, valid);
    final msg = valid.length == 1
        ? '${captureLabel(context, valid.first.kind)} · ${context.t('saved')}'
        : context.tr('saved_n_items', {'n': valid.length});
    _c.clear();
    _overrides.clear();
    widget.onSaved?.call();
    showUndo(context, msg, undo);
  }

  Future<void> _changeKind(int i) async {
    final k = await showAppSheet<CaptureKind>(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(ctx.t('save_as')),
            for (final k in CaptureKind.values)
              OptionTile(
                icon: captureIcon(k),
                color: captureColor(ctx, k),
                title: captureLabel(ctx, k),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ]),
        ),
      );
    });
    if (k == null || !mounted) return;
    setState(() {
      _overrides[i] = k;
      _items[i].kind = k;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final active = _focus.hasFocus || _c.text.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: tk.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? context.cs.primary : tk.border, width: active ? 1.6 : 1),
          boxShadow: active
              ? [BoxShadow(color: context.cs.primary.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 4, 14),
            child: Icon(Icons.auto_awesome_rounded, color: context.cs.primary, size: 22),
          ),
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _focus,
              autofocus: widget.autofocus,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: context.tt.bodyLarge,
              decoration: InputDecoration(
                hintText: context.t('capture_hint'),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: _items.isEmpty ? 0.85 : 1,
              child: IconButton.filled(
                onPressed: _items.isEmpty ? null : _save,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ),
        ]),
      ),
      if (_items.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _changeKind(i),
                child: Pill(captureLabel(context, _items[i].kind),
                    color: captureColor(context, _items[i].kind), icon: captureIcon(_items[i].kind)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: _items[i].title.isEmpty ? _items[i].source : _items[i].title,
                      style: context.tt.labelLarge,
                    ),
                    if (captureSummary(context, _items[i]).isNotEmpty)
                      TextSpan(text: '  ${captureSummary(context, _items[i])}', style: context.tt.bodySmall),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        if (!widget.compact)
          Text(context.t('capture_tip'), style: context.tt.bodySmall?.copyWith(fontSize: 11)),
      ],
    ]);
  }
}

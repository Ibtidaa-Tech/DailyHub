import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';

/// Add or edit one column of the sheet.
///
/// The window is the whole point: with one set, ticking after it closes is
/// recorded as late rather than quietly passing as done.
Future<bool> showItemEditor(
  BuildContext context, {
  required Challenge challenge,
  TrackerItem? item,
  TrackerStore? store,
}) async {
  final target = store ?? context.read<TrackerStore>();
  final saved = await showAppSheet<bool>(
    context,
    builder: (_) => _ItemSheet(challenge: challenge, item: item, store: target),
  );
  return saved == true;
}

class _ItemSheet extends StatefulWidget {
  final Challenge challenge;
  final TrackerItem? item;
  final TrackerStore store;
  const _ItemSheet({required this.challenge, this.item, required this.store});

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final TextEditingController _name;
  late String _emoji;
  late int _color;
  late String _kind;
  late String _start;
  late String _end;
  late int _grace;
  late DateTime _startDay;
  late List<TargetStep> _targets;
  bool _showMore = false;
  String? _error;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name ?? '');
    _emoji = i?.emoji ?? '✅';
    _color = i?.color ?? widget.store.itemsOf(widget.challenge.id).length;
    _kind = i?.kind ?? ItemKind.doIt;
    _start = i?.windowStart ?? '';
    _end = i?.windowEnd ?? '';
    _grace = i?.grace ?? 0;
    // A new column added mid-run starts counting from today, not from day 1 —
    // it has not been tracked for the days it did not exist.
    final challengeStart = widget.challenge.start ?? todayDate();
    _startDay = parseDay(i?.startDay ?? '') ??
        (challengeStart.isAfter(todayDate()) ? challengeStart : todayDate());
    _showMore = (i?.hasWindow ?? false) || (i?.grace ?? 0) > 0;
    // Edited on a copy, so cancelling the sheet really cancels.
    _targets = [for (final t in i?.sortedTargets ?? const <TargetStep>[]) t.copy()];
  }

  /// First day a target may start: an item's own start day. A target before
  /// the habit existed would describe days that were never tracked.
  DateTime get _floor => _startDay;

  /// Never allowed below the floor: showDatePicker asserts on an inverted
  /// range, and a challenge whose end predates a late-added item would hit it.
  DateTime get _ceiling {
    final end = widget.challenge.end ?? addDays(_startDay, 20);
    return end.isBefore(_floor) ? _floor : end;
  }

  /// Pulls a leading number out of the name: "20 Pushups" -> "Pushups" + 20.
  /// Offered rather than applied, because "5 a day Quran" is not the same
  /// shape and the person knows which is which.
  ({String name, double value})? get _splittable {
    final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*[x×]?\s+(.+)$').firstMatch(_name.text);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    final rest = m.group(2)!.trim();
    if (v == null || v <= 0 || rest.isEmpty) return null;
    return (name: rest, value: v);
  }

  Future<void> _editTarget({TargetStep? existing}) async {
    // A new step defaults to tomorrow: raising a target today would relabel
    // what you already did today. The date is editable either way.
    final initial = existing?.day ??
        (() {
          final t = addDays(todayDate(), 1);
          if (t.isBefore(_floor)) return _floor;
          if (t.isAfter(_ceiling)) return _ceiling;
          return t;
        })();
    final value = TextEditingController(
        text: existing == null ? '' : existing.valueLabel);
    final unit = TextEditingController(text: existing?.unit ?? '');
    var from = initial;

    final saved = await showAppSheet<bool>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ctx.t(existing == null ? 'tr_target_add' : 'tr_target_edit'),
                    style: ctx.tt.titleLarge),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: value,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: ctx.t('tr_target_value'),
                        hintText: '40',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: unit,
                      decoration: InputDecoration(
                        labelText: ctx.t('tr_target_unit'),
                        hintText: ctx.t('tr_target_unit_hint'),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                FormFieldButton(
                  icon: Icons.event_rounded,
                  label: ctx.t('tr_target_from'),
                  value: ctx.dayLabel(from),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: from,
                      firstDate: _floor,
                      lastDate: _ceiling,
                    );
                    if (picked != null) set(() => from = dateOnly(picked));
                  },
                ),
                const SizedBox(height: 4),
                Text(ctx.t('tr_target_from_hint'),
                    style: ctx.tt.bodySmall
                        ?.copyWith(color: ctx.tokens.textMuted)),
                const SizedBox(height: 18),
                Row(children: [
                  if (existing != null)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: ctx.tokens.danger),
                      label: Text(ctx.t('delete'),
                          style: TextStyle(color: ctx.tokens.danger)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ctx.t('save')),
                  ),
                ]),
              ],
            ),
          ),
        );
      });
    });

    final typed = value.text.trim();
    final typedUnit = unit.text.trim();
    value.dispose();
    unit.dispose();

    if (!mounted || saved == null) return;
    if (saved == false && existing != null) {
      setState(() => _targets.removeWhere((t) => t.from == existing.from));
      return;
    }
    final v = double.tryParse(typed);
    if (v == null || v <= 0) return;
    setState(() {
      if (existing != null) _targets.removeWhere((t) => t.from == existing.from);
      _targets.removeWhere((t) => t.from == dayKey(from));
      _targets.add(TargetStep(from: dayKey(from), value: v, unit: typedUnit));
      _targets.sort((a, b) => a.from.compareTo(b.from));
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final current = parseHm(isStart ? _start : _end);
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay(hour: isStart ? 6 : 7, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final hm = hmKey(picked.hour, picked.minute);
      if (isStart) {
        _start = hm;
        // A start with no end has no deadline to be late against, so give it
        // a sensible one rather than silently never flagging anything.
        if (_end.isEmpty) {
          final e = picked.replacing(hour: (picked.hour + 1) % 24);
          _end = hmKey(e.hour, e.minute);
        }
      } else {
        _end = hm;
      }
    });
  }

  Future<void> _pickStartDay() async {
    final cs = widget.challenge.start ?? todayDate();
    final ce = widget.challenge.end ?? addDays(cs, 20);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDay,
      firstDate: cs,
      lastDate: ce,
    );
    if (picked != null && mounted) setState(() => _startDay = dateOnly(picked));
  }

  /// The step in force today, by the same rule the model uses.
  TargetStep? _currentOf(List<TargetStep> list) {
    final today = todayDate();
    TargetStep? found;
    for (final t in [...list]..sort((a, b) => a.from.compareTo(b.from))) {
      final d = t.day;
      if (d == null || d.isAfter(today)) break;
      found = t;
    }
    return found;
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.t('tr_name_required'));
      return;
    }
    final i = widget.item ?? TrackerItem(challengeId: widget.challenge.id);
    i
      ..name = name
      ..emoji = _emoji
      ..color = _color
      ..kind = _kind
      ..windowStart = _start
      ..windowEnd = _end
      ..grace = _grace
      ..startDay = dayKey(_startDay)
      ..targets = _targets;
    widget.store.saveItem(i);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final color = AppColors.swatch(_color);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(context.t(_isNew ? 'tr_add_item' : 'tr_edit_item')),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(emoji: _emoji, color: color, size: 48, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.t('tr_item_name'),
                hintText: context.t('tr_item_name_hint'),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        EmojiGrid(value: _emoji, onChanged: (e) => setState(() => _emoji = e)),
        const SizedBox(height: 10),
        ColorDots(value: _color, onChanged: (c) => setState(() => _color = c)),
        const SizedBox(height: 16),

        Text(context.t('tr_kind'), style: context.tt.labelMedium),
        const SizedBox(height: 6),
        PillTabs<String>(
          items: [
            (ItemKind.doIt, context.t('tr_kind_do')),
            (ItemKind.avoid, context.t('tr_kind_avoid')),
          ],
          value: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 6),
        Text(
          context.t(_kind == ItemKind.avoid ? 'tr_kind_avoid_hint' : 'tr_kind_do_hint'),
          style: context.tt.bodySmall?.copyWith(color: tk.textMuted),
        ),
        const SizedBox(height: 16),

        // ------------------------------------------------------- the window
        Row(children: [
          Expanded(
            child: FormFieldButton(
              icon: Icons.play_arrow_rounded,
              label: context.t('tr_window_start'),
              value: _start.isEmpty ? context.t('tr_no_time') : context.timeOfHm(_start),
              onTap: () => _pickTime(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FormFieldButton(
              icon: Icons.flag_rounded,
              label: context.t('tr_window_end'),
              value: _end.isEmpty ? context.t('tr_no_time') : context.timeOfHm(_end),
              onTap: () => _pickTime(false),
            ),
          ),
        ]),
        if (_start.isNotEmpty || _end.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _start = '';
                _end = '';
              }),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: Text(context.t('tr_clear_window')),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        const SizedBox(height: 4),
        Text(context.t('tr_window_hint'), style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),

        // -------------------------------------------------------- targets
        const SizedBox(height: 16),
        SectionTitle(context.t('tr_target')),
        const SizedBox(height: 6),
        if (_targets.isEmpty)
          Text(context.t('tr_target_none'),
              style: context.tt.bodySmall?.copyWith(color: tk.textMuted))
        else
          for (final t in _targets) ...[
            _TargetRow(
              step: t,
              // The step in force today is the one you are actually aiming at.
              current: _currentOf(_targets) == t,
              onTap: () => _editTarget(existing: t),
            ),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 2),
        Row(children: [
          TextButton.icon(
            onPressed: () => _editTarget(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(context.t(_targets.isEmpty ? 'tr_target_set' : 'tr_target_change')),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          // Only shown when the name actually begins with a number, so it
          // never nags at habits where it makes no sense.
          if (_targets.isEmpty && _splittable != null)
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  final sp = _splittable!;
                  setState(() {
                    _name.text = sp.name;
                    _targets = [
                      TargetStep(from: dayKey(_startDay), value: sp.value)
                    ];
                  });
                },
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: Text(
                  context.tr('tr_target_split', {
                    'n': _splittable!.value.round().toString(),
                    'name': _splittable!.name,
                  }),
                  maxLines: 2,
                  style: context.tt.bodySmall,
                ),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
        ]),
        const SizedBox(height: 2),
        Text(context.t('tr_target_hint'),
            style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),

        // --------------------------------------------------------- extras
        const SizedBox(height: 8),
        if (!_showMore)
          TextButton.icon(
            onPressed: () => setState(() => _showMore = true),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Text(context.t('more_options')),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        else ...[
          if (_end.isNotEmpty) ...[
            Text(context.t('tr_grace'), style: context.tt.labelMedium),
            const SizedBox(height: 4),
            ChipRow<int>(
              items: [for (final m in [0, 5, 10, 15, 30, 60]) (m, context.tr('tr_grace_n', {'n': m}))],
              value: _grace,
              onSelected: (m) => setState(() => _grace = m),
            ),
            const SizedBox(height: 4),
            Text(context.t('tr_grace_hint'), style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
            const SizedBox(height: 12),
          ],
          FormFieldButton(
            icon: Icons.event_rounded,
            label: context.t('tr_item_starts'),
            value: context.dayLabel(_startDay),
            onTap: _pickStartDay,
          ),
          const SizedBox(height: 4),
          Text(context.t('tr_item_starts_hint'), style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
        ],

        const SizedBox(height: 20),
        Row(children: [
          if (!_isNew && widget.store.canDeleteItem(widget.item!))
            TextButton.icon(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: context.t('tr_delete_item'),
                  message: context.tr('tr_delete_item_q', {'name': widget.item!.name}),
                  confirm: context.t('delete'),
                  danger: true,
                );
                if (!ok || !context.mounted) return;
                widget.store.deleteItem(widget.item!);
                Navigator.pop(context, true);
              },
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: tk.danger),
              label: Text(context.t('delete'), style: TextStyle(color: tk.danger)),
            ),
          const Spacer(),
          FilledButton(onPressed: _save, child: Text(context.t('save'))),
        ]),
      ]),
    );
  }
}

/// One dated target in the editor's list.
class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.step, required this.current, required this.onTap});

  final TargetStep step;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final day = step.day;
    final future = day != null && day.isAfter(todayDate());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: current ? context.cs.primary.withValues(alpha: 0.08) : tk.subtle,
          borderRadius: BorderRadius.circular(Radii.m),
          border: Border.all(color: current ? context.cs.primary : tk.border),
        ),
        child: Row(children: [
          Text(step.label,
              style: context.tt.titleSmall?.copyWith(
                  color: current ? context.cs.primary : null)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              day == null
                  ? ''
                  : context.tr('tr_target_from_day', {'day': context.dayLabel(day)}),
              style: context.tt.bodySmall?.copyWith(color: tk.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (current)
            Pill(context.t('tr_target_now'), color: context.cs.primary)
          else if (future)
            Pill(context.t('tr_target_upcoming'), color: tk.textFaint),
          const SizedBox(width: 4),
          Icon(Icons.edit_rounded, size: 15, color: tk.textFaint),
        ]),
      ),
    );
  }
}

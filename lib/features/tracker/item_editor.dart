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
      ..startDay = dayKey(_startDay);
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

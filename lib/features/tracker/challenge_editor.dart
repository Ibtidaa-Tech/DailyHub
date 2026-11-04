import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';

/// A ready-made set of columns, so a new run is one tap rather than eleven
/// trips through the item editor.
class _Template {
  final String id;
  final String labelKey;
  final String descKey;
  final IconData icon;

  /// (name key, emoji, window start, window end, colour index)
  final List<(String, String, String, String, int)> items;
  const _Template(this.id, this.labelKey, this.descKey, this.icon, this.items);
}

/// Matches the paper sheet: wake, the five Salah, then the daily work.
/// Prayer times are a starting point — edit each one to your own timetable.
const _sheet = _Template(
  'sheet',
  'tr_tpl_sheet',
  'tr_tpl_sheet_desc',
  Icons.calendar_view_week_rounded,
  [
    ('tr_tpl_wake', '⏰', '05:45', '06:00', 0),
    ('tr_tpl_fajr', '🌅', '05:22', '06:30', 1),
    ('tr_tpl_zuhr', '☀️', '12:20', '15:00', 2),
    ('tr_tpl_asr', '🌤️', '15:41', '18:00', 3),
    ('tr_tpl_maghrib', '🌇', '18:08', '19:00', 4),
    ('tr_tpl_isha', '🌙', '19:15', '23:30', 5),
    ('tr_tpl_leetcode', '💻', '', '', 6),
    ('tr_tpl_github', '🐙', '', '', 7),
    ('tr_tpl_duolingo', '🦉', '', '', 8),
    ('tr_tpl_pushups', '💪', '', '', 9),
    ('tr_tpl_nojunk', '🚫', '', '', 10),
  ],
);

const _salah = _Template(
  'salah',
  'tr_tpl_salah',
  'tr_tpl_salah_desc',
  Icons.mosque_rounded,
  [
    ('tr_tpl_fajr', '🌅', '05:22', '06:30', 1),
    ('tr_tpl_zuhr', '☀️', '12:20', '15:00', 2),
    ('tr_tpl_asr', '🌤️', '15:41', '18:00', 3),
    ('tr_tpl_maghrib', '🌇', '18:08', '19:00', 4),
    ('tr_tpl_isha', '🌙', '19:15', '23:30', 5),
  ],
);

const _blank = _Template('blank', 'tr_tpl_blank', 'tr_tpl_blank_desc', Icons.add_rounded, []);

const _templates = [_sheet, _salah, _blank];

/// Create a run, or edit the one you have. Returns the challenge id when a
/// new one was created.
/// [store] overrides the signed-in account's store — that is how a mentor
/// sets a tracker inside a student's data.
Future<String?> showChallengeEditor(
  BuildContext context, {
  Challenge? challenge,
  TrackerStore? store,
}) async {
  final target = store ?? context.read<TrackerStore>();
  return showAppSheet<String>(
    context,
    expand: true,
    builder: (_) => _ChallengeSheet(challenge: challenge, store: target),
  );
}

class _ChallengeSheet extends StatefulWidget {
  final Challenge? challenge;
  final TrackerStore store;
  const _ChallengeSheet({this.challenge, required this.store});

  @override
  State<_ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<_ChallengeSheet> {
  late final TextEditingController _title;
  late final TextEditingController _motto;
  late DateTime _start;
  late int _days;
  String _template = 'sheet';

  bool get _isNew => widget.challenge == null;

  @override
  void initState() {
    super.initState();
    final c = widget.challenge;
    _title = TextEditingController(text: c?.title ?? '');
    _motto = TextEditingController(text: c?.subtitle ?? '');
    _start = c?.start ?? todayDate();
    _days = c?.days ?? 21;
  }

  @override
  void dispose() {
    _title.dispose();
    _motto.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = todayDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      // Backdating a run would invent missed days you never agreed to, so the
      // earliest it can begin is today.
      firstDate: now,
      lastDate: addDays(now, 365),
    );
    if (picked != null && mounted) setState(() => _start = dateOnly(picked));
  }

  Future<void> _pickLength() async {
    final v = await promptText(
      context,
      title: context.t('tr_length'),
      initial: '$_days',
      keyboard: TextInputType.number,
    );
    final n = int.tryParse(v?.trim() ?? '');
    if (n != null && n >= 1 && n <= 365 && mounted) setState(() => _days = n);
  }

  void _save() {
    final c = widget.challenge ?? Challenge();
    final title = _title.text.trim();
    c
      ..title = title.isEmpty ? context.t('tr_challenge_title_hint') : title
      ..subtitle = _motto.text.trim()
      ..startDay = dayKey(_start)
      ..days = _days;
    final id = widget.store.saveChallenge(c);

    if (_isNew) {
      final tpl = _templates.firstWhere((t) => t.id == _template, orElse: () => _blank);
      var order = 0;
      for (final it in tpl.items) {
        widget.store.saveItem(TrackerItem(
          challengeId: id,
          name: context.t(it.$1),
          emoji: it.$2,
          windowStart: it.$3,
          windowEnd: it.$4,
          color: it.$5,
          startDay: dayKey(_start),
          order: order++,
        ));
      }
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
        child: SheetHeader(context.t(_isNew ? 'tr_new' : 'tr_edit_challenge')),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.t('tr_challenge_title'),
                hintText: context.t('tr_challenge_title_hint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motto,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.t('tr_motto'),
                hintText: context.t('tr_motto_hint'),
              ),
            ),
            const SizedBox(height: 16),
            FormFieldButton(
              icon: Icons.event_rounded,
              label: context.t('tr_start_day'),
              value: context.dayLabel(_start),
              onTap: _pickStart,
            ),
            const SizedBox(height: 14),
            Text(context.t('tr_length'), style: context.tt.labelMedium),
            const SizedBox(height: 6),
            ChipRow<int>(
              items: [
                for (final n in [7, 14, 21, 30, 40, 90]) (n, context.tr('tr_length_n', {'n': n})),
                if (![7, 14, 21, 30, 40, 90].contains(_days)) (_days, context.tr('tr_length_n', {'n': _days})),
              ],
              value: _days,
              onSelected: (n) => setState(() => _days = n),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickLength,
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: Text(context.t('tr_custom')),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
            Text(
              context.tr('tr_runs_until', {'d': context.dayLabel(addDays(_start, _days - 1))}),
              style: context.tt.bodySmall?.copyWith(color: tk.textMuted),
            ),
            if (_isNew) ...[
              const SizedBox(height: 18),
              Text(context.t('tr_template'), style: context.tt.labelMedium),
              const SizedBox(height: 6),
              GroupCard(children: [
                for (final t in _templates)
                  OptionTile(
                    icon: t.icon,
                    color: AppColors.mTracker,
                    title: context.t(t.labelKey),
                    subtitle: context.t(t.descKey),
                    trailing: Icon(
                      _template == t.id
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: _template == t.id ? context.cs.primary : tk.textFaint,
                    ),
                    onTap: () => setState(() => _template = t.id),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(context.t('tr_template_edit_hint'),
                  style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
            ],
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: Text(context.t(_isNew ? 'tr_create' : 'save')),
            ),
          ),
        ),
      ),
    ]);
  }
}

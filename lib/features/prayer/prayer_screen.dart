import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/prayer_store.dart';
import '../../services/location_service.dart';
import '../../services/prayer_times.dart';
import '../../ui/kit.dart';

/// Prayer times for wherever you are, with every school shown and every time
/// editable for that day alone.
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});
  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  DateTime _day = todayDate();
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Only asks when there is nothing to show, or when you have said the
    // times should follow you. Never on a timer, never in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<AppSettings>();
      if (s.prayerLat == null || s.prayerFollowLocation) _locate(silent: true);
    });
  }

  Future<void> _locate({bool silent = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      if (!silent) _error = null;
    });
    final res = await LocationService.instance.current();
    if (!mounted) return;
    final pos = res.position;
    if (pos != null) {
      context.read<AppSettings>().setPrayerLocation(pos.latitude, pos.longitude);
      setState(() {
        _locating = false;
        _error = null;
      });
    } else {
      setState(() {
        _locating = false;
        _error = silent ? null : res.error;
      });
    }
  }

  Future<void> _editTime(PrayerStore store, String prayer, DateTime? current) async {
    final now = current ?? DateTime(_day.year, _day.month, _day.day, 6);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
      helpText: context.tr('pr_edit_for', {'d': context.dayLabel(_day)}),
    );
    if (picked == null || !mounted) return;
    store.setEdit(_day, prayer, hmKey(picked.hour, picked.minute));
    showToast(context, context.t('pr_edited'), icon: Icons.edit_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PrayerStore>();
    final settings = context.watch<AppSettings>();
    final tk = context.tokens;
    final isToday = sameDay(_day, todayDate());

    return AppPage(
      title: context.t('m_prayer'),
      subtitle: settings.prayerPlace.isEmpty ? null : settings.prayerPlace,
      actions: [
        IconButton(
          tooltip: context.t('pr_refresh_location'),
          icon: _locating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded),
          onPressed: _locating ? null : () => _locate(),
        ),
        IconButton(
          tooltip: context.t('pr_method'),
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => _showMethodSheet(settings),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(child: _dayBar(isToday)),
        if (!store.hasLocation)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.location_off_rounded,
              color: AppColors.mPrayer,
              title: context.t('pr_no_location'),
              message: _error ?? context.t('pr_no_location_msg'),
              actionLabel: context.t('pr_use_location'),
              onAction: () => _locate(),
            ),
          )
        else ...[
          SliverToBoxAdapter(child: _nextCard(store)),
          SliverToBoxAdapter(child: SectionTitle(context.t('pr_times'))),
          SliverToBoxAdapter(child: _timesCard(store)),
          SliverToBoxAdapter(child: SectionTitle(context.t('pr_asr_schools'))),
          SliverToBoxAdapter(child: _asrCard(store)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                context.tr('pr_footnote', {'m': PrayerMethod.byId(settings.prayerMethod).label}),
                style: context.tt.bodySmall?.copyWith(color: tk.textFaint),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 70)),
      ],
    );
  }

  Widget _dayBar(bool isToday) {
    return DhCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => setState(() => _day = addDays(_day, -1)),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: addDays(todayDate(), -365),
                lastDate: addDays(todayDate(), 365),
              );
              if (picked != null && mounted) setState(() => _day = dateOnly(picked));
            },
            child: Column(children: [
              Text(context.dayLabel(_day), style: context.tt.titleSmall, textAlign: TextAlign.center),
              Text(context.fmtDate(_day, 'EEEE'),
                  style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted)),
            ]),
          ),
        ),
        if (!isToday)
          TextButton(
            onPressed: () => setState(() => _day = todayDate()),
            child: Text(context.t('tr_jump_today')),
          ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => setState(() => _day = addDays(_day, 1)),
        ),
      ]),
    );
  }

  /// What is next, which is the question people actually open this for.
  Widget _nextCard(PrayerStore store) {
    final now = DateTime.now();
    if (!sameDay(_day, todayDate())) return const SizedBox.shrink();
    String? next;
    DateTime? at;
    for (final p in PrayerId.five) {
      final t = store.timeOf(_day, p);
      if (t != null && t.isAfter(now)) {
        next = p;
        at = t;
        break;
      }
    }
    if (next == null || at == null) return const SizedBox.shrink();
    final left = at.difference(now);
    return DhCard(
      color: context.tokens.tint(AppColors.mPrayer),
      child: Row(children: [
        const IconBadge(icon: Icons.mosque_rounded, color: AppColors.mPrayer, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('pr_next', {'p': context.t(PrayerId.labelKey(next))}),
                style: context.tt.titleSmall),
            Text(
              left.inMinutes < 60
                  ? context.tr('pr_in_min', {'n': left.inMinutes})
                  : context.tr('pr_in_hm', {'h': left.inHours, 'm': left.inMinutes % 60}),
              style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted),
            ),
          ]),
        ),
        Text(context.timeOf(at), style: context.tt.titleMedium),
      ]),
    );
  }

  Widget _timesCard(PrayerStore store) {
    final rows = [PrayerId.fajr, PrayerId.sunrise, PrayerId.dhuhr, PrayerId.asr,
                  PrayerId.maghrib, PrayerId.isha];
    return DhCard(
      child: Column(children: [
        for (var n = 0; n < rows.length; n++) ...[
          if (n > 0) Divider(height: 14, color: context.tokens.border),
          _timeRow(store, rows[n]),
        ],
      ]),
    );
  }

  Widget _timeRow(PrayerStore store, String prayer) {
    final tk = context.tokens;
    final t = store.timeOf(_day, prayer);
    final edited = store.isEdited(_day, prayer);
    final isSunrise = prayer == PrayerId.sunrise;
    return InkWell(
      onTap: () => _editTime(store, prayer, t),
      borderRadius: BorderRadius.circular(Radii.s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(
            isSunrise ? Icons.wb_twilight_rounded : Icons.mosque_outlined,
            size: 18,
            color: isSunrise ? tk.textFaint : AppColors.mPrayer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.t(PrayerId.labelKey(prayer)),
              style: isSunrise
                  ? context.tt.bodyMedium?.copyWith(color: tk.textMuted)
                  : context.tt.titleSmall,
            ),
          ),
          if (edited) ...[
            Pill(context.t('pr_edited_tag'), color: tk.transfer, icon: Icons.edit_rounded),
            const SizedBox(width: 8),
          ],
          Text(t == null ? '—' : context.timeOf(t),
              style: context.tt.titleSmall?.copyWith(color: edited ? tk.transfer : null)),
          if (edited)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.t('pr_reset'),
              icon: Icon(Icons.undo_rounded, size: 16, color: tk.textFaint),
              onPressed: () => store.clearEdit(_day, prayer),
            )
          else
            Icon(Icons.edit_outlined, size: 15, color: tk.textFaint),
        ]),
      ),
    );
  }

  /// All four schools. Three of them share a time — shown anyway, because
  /// reading your own school off the list beats knowing the rule.
  Widget _asrCard(PrayerStore store) {
    final tk = context.tokens;
    final settings = context.watch<AppSettings>();
    final edited = store.isEdited(_day, PrayerId.asr);
    return DhCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (edited)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.t('pr_asr_edited'),
                style: context.tt.bodySmall?.copyWith(color: tk.transfer)),
          ),
        for (final m in Madhab.all)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: InkWell(
              onTap: () => settings.setAsrMadhab(m.id),
              borderRadius: BorderRadius.circular(Radii.s),
              child: Row(children: [
              Icon(
                m.id == settings.asrMadhab
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: m.id == settings.asrMadhab ? AppColors.mPrayer : tk.textFaint,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(context.t(m.labelKey), style: context.tt.bodyMedium)),
              Text(
                store.computed(_day)?.asr[m.id] == null
                    ? '—'
                    : context.timeOf(store.computed(_day)!.asr[m.id]!),
                style: context.tt.titleSmall?.copyWith(
                  color: m.id == settings.asrMadhab ? AppColors.mPrayer : tk.textMuted,
                ),
              ),
            ]),
            ),
          ),
        const SizedBox(height: 4),
        Text(context.t('pr_asr_note'),
            style: context.tt.bodySmall?.copyWith(color: tk.textFaint)),
      ]),
    );
  }

  Future<void> _showMethodSheet(AppSettings settings) async {
    await showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(ctx.t('pr_method'), subtitle: ctx.t('pr_method_sub')),
            const SizedBox(height: 6),
            for (final m in PrayerMethod.all)
              ListTile(
                onTap: () {
                  settings.setPrayerMethod(m.id);
                  setSheet(() {});
                },
                leading: Icon(
                  settings.prayerMethod == m.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: settings.prayerMethod == m.id ? AppColors.mPrayer : ctx.tokens.textFaint,
                ),
                title: Text(m.label, style: ctx.tt.bodyMedium),
                dense: true,
              ),
            const Divider(),
            SwitchListTile(
              value: settings.prayerFollowLocation,
              onChanged: (v) {
                settings.setPrayerFollowLocation(v);
                setSheet(() {});
              },
              title: Text(ctx.t('pr_follow'), style: ctx.tt.bodyMedium),
              subtitle: Text(ctx.t('pr_follow_sub'), style: ctx.tt.bodySmall),
              dense: true,
            ),
          ]),
        ),
      ),
    );
  }
}

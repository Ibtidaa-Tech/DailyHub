import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/agenda.dart';
import '../../data/extras_store.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../data/plan_store.dart';
import '../../services/db_service.dart';
import '../../ui/kit.dart';
import '../capture/capture.dart';
import '../habits/habits_screen.dart';
import '../money/bills_screen.dart';
import '../money/money_screen.dart';
import '../plan/plan_screen.dart';
import '../plan/plan_tiles.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/shell.dart';
import 'weather_chip.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final pad = sidePad(context);
    final sections = settings.homeOrder.where((s) => !settings.homeHidden.contains(s)).toList();
    final children = <Widget>[];
    for (final s in sections) {
      final w = switch (s) {
        HomeSections.capture => const SmartCaptureField(),
        HomeSections.agenda => const _AgendaCard(),
        HomeSections.habits => settings.isOn('habits') ? const _HabitsSection() : null,
        HomeSections.money => settings.isOn('money') ? const _MoneySection() : null,
        HomeSections.upcoming => const _UpcomingSection(),
        _ => null,
      };
      if (w != null) {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 14), child: w));
      }
    }
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => WeatherChip.refresh(context),
        child: CustomScrollView(slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
              sliver: const SliverToBoxAdapter(child: _Header()),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 110),
            sliver: SliverList.list(children: [
              ...children,
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(context.t('customize_home')),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeLayoutScreen())),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: DbService.instance.profileStream(),
      builder: (context, snap) {
        final name = str(snap.data?['name']).isNotEmpty
            ? str(snap.data?['name'])
            : (user?.displayName ?? user?.email?.split('@').first ?? '');
        final first = name.trim().split(RegExp(r'\s+')).first;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(context.fmtDate(DateTime.now(), 'EEEE, d MMMM'),
                  style: context.tt.labelLarge?.copyWith(color: context.tokens.textMuted)),
            ),
            IconButton(
              tooltip: context.t('search'),
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              child: InitialsAvatar(name.isEmpty ? '?' : name, size: 38, color: context.cs.primary),
            ),
          ]),
          const SizedBox(height: 2),
          Text(
            first.isEmpty ? context.t(greetingKey()) : '${context.t(greetingKey())}, $first',
            style: context.tt.headlineMedium,
          ),
          const SizedBox(height: 10),
          const WeatherChip(),
        ]);
      },
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard();

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanStore>();
    final money = context.watch<MoneyStore>();
    final extras = context.watch<ExtrasStore?>();
    final shell = context.read<ShellController?>();
    final t0 = todayDate();
    final items = Agenda.forDay(t0, plan: plan, money: money, extras: extras, includeDone: false);
    final overdue = plan.overdue;
    final done = plan.completedToday.length;
    final total = done + items.where((i) => i.kind == AgendaKind.task).length;
    final shown = items.take(6).toList();

    return DhCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(context.t('today'), style: context.tt.titleLarge)),
          if (total > 0) Text(context.tr('x_of_y_done', {'x': done, 'y': total}), style: context.tt.bodySmall),
          const SizedBox(width: 8),
          if (total > 0)
            ProgressRing(value: done / total, size: 26, stroke: 3.5, color: context.tokens.success),
        ]),
        if (overdue.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Material(
              color: context.tokens.tint(context.tokens.danger),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => shell?.go('plan', planView: PlanView.today),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: context.tokens.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.tn('overdue_count', overdue.length),
                          style: context.tt.labelLarge?.copyWith(color: context.tokens.danger)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: context.tokens.danger),
                      onPressed: () {
                        plan.rescheduleAll(overdue, t0);
                        showToast(context, context.t('moved_to_today'), icon: Icons.today_rounded);
                      },
                      child: Text(context.t('move_to_today')),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(children: [
              const Text('☀️', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('all_clear'), style: context.tt.titleSmall),
                  Text(context.t('all_clear_msg'), style: context.tt.bodySmall),
                ]),
              ),
            ]),
          )
        else
          for (final i in shown)
            (switch (i.kind) {
              AgendaKind.task => TaskTile(task: i.ref as Task, showDate: false, dense: true),
              AgendaKind.reminder => ReminderTile(reminder: i.ref as Reminder, showDate: false, occurrence: i.time),
              AgendaKind.bill => EventTile(
                  item: i,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BillsScreen()))),
              _ => EventTile(item: i),
            }),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => shell?.go('plan', planView: PlanView.today),
            child: Text(items.length > shown.length
                ? context.tr('see_all_n', {'n': items.length})
                : context.t('open_plan')),
          ),
        ),
      ]),
    );
  }
}

class _HabitsSection extends StatelessWidget {
  const _HabitsSection();
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(
        context.t('m_habits'),
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
        action: context.t('see_all'),
        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HabitsScreen())),
      ),
      const HabitsRow(),
    ]);
  }
}

class _MoneySection extends StatelessWidget {
  const _MoneySection();
  @override
  Widget build(BuildContext context) {
    final shell = context.read<ShellController?>();
    return MoneySnapshot(onOpen: () => shell?.go('money'));
  }
}

class _UpcomingSection extends StatelessWidget {
  const _UpcomingSection();

  @override
  Widget build(BuildContext context) {
    final extras = context.watch<ExtrasStore?>();
    final money = context.watch<MoneyStore>();
    final settings = context.watch<AppSettings>();
    final t0 = todayDate();
    final rows = <(DateTime, IconData, Color, String, String)>[];
    for (final h in extras?.upcomingHighlights(21) ?? const <(DateTime, Map<String, dynamic>, String)>[]) {
      if (sameDay(h.$1, t0)) continue;
      switch (h.$3) {
        case 'trip':
          rows.add((h.$1, Icons.flight_takeoff_rounded, AppColors.mTrips, '${str(h.$2['from'])} → ${str(h.$2['to'])}', context.t('k_trip')));
          break;
        case 'countdown':
          rows.add((h.$1, Icons.celebration_rounded, AppColors.mCountdown, '${str(h.$2['emoji'])} ${str(h.$2['title'])}'.trim(), context.t('k_countdown')));
          break;
        case 'assignment':
          rows.add((h.$1, Icons.assignment_rounded, AppColors.mStudy, str(h.$2['title']), context.t('k_assignment')));
          break;
      }
    }
    if (settings.isOn('money')) {
      for (final b in money.billsDueWithin(10)) {
        final d = b.dueDate;
        if (d == null) continue;
        rows.add((d, Icons.receipt_long_rounded, b.type == 'income' ? AppColors.income : AppColors.mReminders,
            '${b.emoji} ${b.name}', Money.format(b.amount)));
      }
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(context.t('coming_up'), padding: const EdgeInsets.fromLTRB(4, 0, 0, 6)),
      DhCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final r in rows.take(6))
            ListTile(
              dense: true,
              leading: IconBadge(icon: r.$2, color: r.$3, size: 34),
              title: Text(r.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
              subtitle: Text(r.$5, style: context.tt.bodySmall),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(context.dayLabel(r.$1, short: true), style: context.tt.labelMedium),
                Text(r.$1.isBefore(t0) ? context.t('overdue') : context.tn('in_days', daysBetween(t0, r.$1)),
                    style: context.tt.bodySmall?.copyWith(fontSize: 11)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

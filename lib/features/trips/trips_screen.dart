import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/trip_store.dart';
import '../../ui/kit.dart';
import 'trip_detail.dart';
import 'trip_editor.dart';

IconData tripIcon(String mode) => switch (mode) {
      TripMode.flight => Icons.flight_takeoff_rounded,
      TripMode.train => Icons.train_rounded,
      TripMode.bus => Icons.directions_bus_rounded,
      TripMode.car => Icons.directions_car_rounded,
      _ => Icons.luggage_rounded,
    };

String tripModeLabel(BuildContext context, String mode) => context.t('trip_$mode');

/// Every journey, soonest first.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});
  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  bool _past = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TripStore>();
    final ws = context.watch<WorkspaceProvider>();
    final list = _past ? s.past : s.upcoming;

    return AppPage(
      title: context.t('m_trips'),
      subtitle: context.t('trips_sub'),
      fab: ws.canAdd
          ? FloatingActionButton.extended(
              onPressed: () => openTripEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.t('trip_add')),
            )
          : null,
      header: s.past.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PillTabs<bool>(
                items: [
                  (false, context.tn('trip_n_upcoming', s.upcoming.length)),
                  (true, context.t('trip_past')),
                ],
                value: _past,
                onChanged: (v) => setState(() => _past = v),
              ),
            ),
      slivers: [
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.luggage_outlined,
              color: AppColors.mTrips,
              title: context.t(_past ? 'trip_no_past' : 'trip_none'),
              message: _past ? null : context.t('trip_none_msg'),
              actionLabel: _past || !ws.canAdd ? null : context.t('trip_add'),
              onAction: _past ? null : () => openTripEditor(context),
            ),
          )
        else
          SliverList.list(children: [for (final t in list) TripCard(trip: t)]),
      ],
    );
  }
}

/// One journey in the list.
class TripCard extends StatelessWidget {
  final Trip trip;
  const TripCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final t = trip;
    final away = t.daysAway;
    final dep = t.departure;

    return DhCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: t.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(icon: tripIcon(t.mode), color: AppColors.mTrips, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                t.route.isEmpty ? context.t('trip_untitled') : t.route,
                style: context.tt.titleMedium?.copyWith(
                  decoration: t.isCancelled ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  tripModeLabel(context, t.mode),
                  if (t.operator.isNotEmpty) t.operator,
                ].join(' · '),
                style: context.tt.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (t.isCancelled)
            Pill(context.t('cancelled'), color: tk.danger)
          else if (away != null && t.isUpcoming)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                away == 0 ? context.t('today') : (away == 1 ? context.t('tomorrow') : '$away'),
                style: context.tt.titleMedium?.copyWith(color: AppColors.mTrips),
              ),
              if (away > 1)
                Text(context.t('trip_days_to_go'), style: context.tt.bodySmall?.copyWith(fontSize: 10)),
            ]),
        ]),
        if (dep != null || t.packing.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (dep != null)
              MetaChip(Icons.event_outlined, context.dayTimeLabel(dep, hasTime: t.depTime.isNotEmpty)),
            if (t.pnr.isNotEmpty) MetaChip(Icons.confirmation_number_outlined, t.pnr),
            if (t.packing.isNotEmpty)
              MetaChip(
                Icons.checklist_rounded,
                '${t.packed}/${t.packing.length}',
                color: t.packed == t.packing.length ? tk.success : null,
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Compact summary used inside the trip detail screen.
class TripFacts extends StatelessWidget {
  final Trip trip;
  const TripFacts({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final dep = t.departure;
    final arr = t.arrival;
    final rows = <(IconData, String, String)>[
      if (dep != null)
        (Icons.flight_takeoff_rounded, context.t('trip_departs'),
            context.dayTimeLabel(dep, hasTime: t.depTime.isNotEmpty)),
      if (arr != null)
        (Icons.flight_land_rounded, context.t('trip_arrives'),
            context.dayTimeLabel(arr, hasTime: t.arrTime.isNotEmpty)),
      if (t.operator.isNotEmpty) (tripIcon(t.mode), context.t('trip_operator'), t.operator),
      if (t.pnr.isNotEmpty) (Icons.confirmation_number_outlined, context.t('trip_pnr'), t.pnr),
      if (t.seat.isNotEmpty) (Icons.event_seat_outlined, context.t('trip_seat'), t.seat),
      if (t.cost > 0) (Icons.payments_outlined, context.t('trip_cost'), Money.format(t.cost)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return DhCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        for (final r in rows)
          ListTile(
            dense: true,
            leading: Icon(r.$1, color: context.tokens.textMuted, size: 20),
            title: Text(r.$2, style: context.tt.bodySmall),
            subtitle: Text(r.$3, style: context.tt.titleSmall),
          ),
      ]),
    );
  }
}

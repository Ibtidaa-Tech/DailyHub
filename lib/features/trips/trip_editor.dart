import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/trip_store.dart';
import '../../ui/kit.dart';
import '../plan/pickers.dart';
import 'trips_screen.dart';

/// Add or edit a journey.
Future<void> openTripEditor(BuildContext context, {Trip? trip}) async {
  final s = context.read<TripStore>();
  final from = TextEditingController(text: trip?.from ?? '');
  final to = TextEditingController(text: trip?.to ?? '');
  final pnr = TextEditingController(text: trip?.pnr ?? '');
  final operator = TextEditingController(text: trip?.operator ?? '');
  final seat = TextEditingController(text: trip?.seat ?? '');
  final notes = TextEditingController(text: trip?.notes ?? '');
  final cost = TextEditingController(
      text: (trip?.cost ?? 0) > 0 ? trip!.cost.toStringAsFixed(0) : '');

  var mode = trip?.mode ?? TripMode.flight;
  DateTime? depDate = parseDay(trip?.depDate ?? '');
  DateTime? arrDate = parseDay(trip?.arrDate ?? '');
  var depTime = trip?.depTime ?? '';
  var arrTime = trip?.arrTime ?? '';

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      Future<void> pickTime(bool departure) async {
        final current = parseHm(departure ? depTime : arrTime);
        final t = await showTimePicker(
            context: ctx, initialTime: current ?? const TimeOfDay(hour: 9, minute: 0));
        if (t == null) return;
        set(() {
          if (departure) {
            depTime = hmKey(t.hour, t.minute);
          } else {
            arrTime = hmKey(t.hour, t.minute);
          }
        });
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ctx.t(trip == null ? 'trip_add' : 'trip_edit'), style: ctx.tt.titleLarge),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in TripMode.all)
                ChoiceChip(
                  avatar: Icon(tripIcon(m), size: 18),
                  label: Text(tripModeLabel(ctx, m)),
                  selected: mode == m,
                  onSelected: (_) => set(() => mode = m),
                ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: from,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: ctx.t('from'),
                    prefixIcon: const Icon(Icons.trip_origin_rounded, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: to,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: ctx.t('to'),
                    prefixIcon: const Icon(Icons.place_outlined, size: 20),
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FormFieldButton(
                  icon: Icons.flight_takeoff_rounded,
                  label: ctx.t('trip_departs'),
                  value: depDate == null ? ctx.t('pick_date') : ctx.dayLabel(depDate!, short: true),
                  onTap: () async {
                    final picked = await pickDay(ctx, initial: depDate, allowNone: false);
                    if (picked?.value != null) {
                      set(() {
                        depDate = picked!.value;
                        if (arrDate != null && arrDate!.isBefore(depDate!)) arrDate = depDate;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldButton(
                  icon: Icons.schedule_rounded,
                  label: ctx.t('time'),
                  value: depTime.isEmpty ? ctx.t('no_time') : ctx.timeOfHm(depTime),
                  onTap: () => pickTime(true),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FormFieldButton(
                  icon: Icons.flight_land_rounded,
                  label: ctx.t('trip_arrives'),
                  value: arrDate == null ? ctx.t('optional') : ctx.dayLabel(arrDate!, short: true),
                  onTap: () async {
                    final picked = await pickDay(ctx, initial: arrDate ?? depDate, allowNone: true);
                    if (picked != null) set(() => arrDate = picked.value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldButton(
                  icon: Icons.schedule_outlined,
                  label: ctx.t('time'),
                  value: arrTime.isEmpty ? ctx.t('no_time') : ctx.timeOfHm(arrTime),
                  onTap: () => pickTime(false),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: operator,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: ctx.t(switch (mode) {
                  TripMode.flight => 'trip_airline_hint',
                  TripMode.train => 'trip_train_hint',
                  TripMode.bus => 'trip_bus_hint',
                  TripMode.car => 'trip_car_hint',
                  _ => 'trip_operator',
                }),
                prefixIcon: Icon(tripIcon(mode), size: 20),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: pnr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: ctx.t('trip_pnr'),
                    prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: seat,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: ctx.t('trip_seat'),
                    prefixIcon: const Icon(Icons.event_seat_outlined, size: 20),
                    isDense: true,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: ctx.t('trip_cost'),
                prefixText: '${Money.symbol} ',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
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
            FilledButton(
              onPressed: () {
                if (from.text.trim().isEmpty && to.text.trim().isEmpty) {
                  showToast(ctx, ctx.t('trip_enter_route'));
                  return;
                }
                if (depDate == null) {
                  showToast(ctx, ctx.t('trip_enter_date'));
                  return;
                }
                s.save(Trip(
                  id: trip?.id ?? '',
                  mode: mode,
                  from: from.text.trim(),
                  to: to.text.trim(),
                  depDate: dayKey(depDate!),
                  depTime: depTime,
                  arrDate: arrDate == null ? '' : dayKey(arrDate!),
                  arrTime: arrTime,
                  pnr: pnr.text.trim(),
                  operator: operator.text.trim(),
                  seat: seat.text.trim(),
                  notes: notes.text.trim(),
                  cost: double.tryParse(cost.text.trim()) ?? 0,
                  status: trip?.status ?? 'upcoming',
                  packing: trip?.packing ?? [],
                ));
                Navigator.pop(ctx);
              },
              child: Text(ctx.t('save')),
            ),
          ]),
        ),
      );
    });
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in [from, to, pnr, operator, seat, notes, cost]) {
        c.dispose();
      }
    });
  });
}

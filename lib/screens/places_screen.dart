import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../services/location_service.dart';
import '../ui/kit.dart';

/// Saved places and addresses, plus a dedicated "Where did I park?" slot.
///
/// Every saved address is one tap from Maps (tap the card) and one tap from
/// the clipboard (the copy button) — those are the two things people actually
/// do with a saved address. Parking captures GPS when it can, but the typed
/// note (level, row, landmark) stays the primary record, because indoor car
/// parks are exactly where GPS is least reliable.
class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  /// Stored verbatim in Firebase — the labels below are only for display.
  static const categories = ['Home', 'Work', 'College', 'Food', 'Shop', 'Health', 'Other'];

  static IconData iconFor(String category) => switch (category) {
        'Home' => Icons.home_rounded,
        'Work' => Icons.work_rounded,
        'College' => Icons.school_rounded,
        'Food' => Icons.restaurant_rounded,
        'Shop' => Icons.storefront_rounded,
        'Health' => Icons.local_hospital_rounded,
        _ => Icons.place_rounded,
      };

  static String labelFor(BuildContext context, String category) => switch (category) {
        'Home' => context.t('pl_home'),
        'Work' => context.t('pl_work'),
        'College' => context.t('pl_college'),
        'Food' => context.t('pl_food'),
        'Shop' => context.t('pl_shop'),
        'Health' => context.t('pl_health'),
        'Other' => context.t('pl_other'),
        _ => category,
      };

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('places'),
      builder: (context, snap) {
        final places = snap.data ?? const <Map<String, dynamic>>[];
        // Group by the category the record already carries; anything we don't
        // recognise falls into "Other" rather than inventing a new section.
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final p in places) {
          final c = str(p['category']);
          groups.putIfAbsent(categories.contains(c) ? c : 'Other', () => []).add(p);
        }
        for (final g in groups.values) {
          g.sort((a, b) => str(a['name']).toLowerCase().compareTo(str(b['name']).toLowerCase()));
        }
        final order = [for (final c in categories) if (groups.containsKey(c)) c];

        return AppPage(
          title: context.t('m_places'),
          subtitle: context.t('places_sub'),
          fab: FloatingActionButton.extended(
            heroTag: 'placeFab',
            onPressed: () => openPlaceEditor(context),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: Text(context.t('place_add')),
          ),
          slivers: [
            SliverToBoxAdapter(child: _ParkingCard(db: db)),
            if (places.isEmpty && snap.hasData)
              SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.place_outlined,
                  color: AppColors.mPlaces,
                  title: context.t('place_none'),
                  message: context.t('place_none_msg'),
                  actionLabel: context.t('place_add'),
                  onAction: () => openPlaceEditor(context),
                ),
              )
            else
              for (final c in order) ...[
                SliverToBoxAdapter(
                  child: SectionTitle(
                    labelFor(context, c),
                    trailing: Text('${groups[c]!.length}',
                        style: context.tt.labelSmall?.copyWith(color: context.tokens.textFaint)),
                  ),
                ),
                SliverList.list(
                  children: [for (final p in groups[c]!) _PlaceCard(db: db, place: p)],
                ),
              ],
          ],
        );
      },
    );
  }
}

/// One saved address. Tap opens Maps, the copy button takes the address.
class _PlaceCard extends StatelessWidget {
  final DbService db;
  final Map<String, dynamic> place;
  const _PlaceCard({required this.db, required this.place});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final name = str(place['name']);
    final address = str(place['address']);
    final hasAddress = address.isNotEmpty;

    return SwipeTile(
      swipeKey: ValueKey('place_${place['id']}'),
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        _removePlace(context, db, place);
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        onTap: hasAddress
            ? () => _openMaps(context, address)
            : () => openPlaceEditor(context, existing: place),
        onLongPress: () => openPlaceEditor(context, existing: place),
        child: Row(children: [
          IconBadge(
            icon: PlacesScreen.iconFor(str(place['category'])),
            color: AppColors.mPlaces,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                name.isEmpty ? context.t('place_untitled') : name,
                style: context.tt.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                hasAddress ? address : context.t('place_no_address'),
                style: context.tt.bodySmall
                    ?.copyWith(color: hasAddress ? tk.textMuted : tk.textFaint),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (hasAddress)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.t('place_copy_address'),
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => _copyToClipboard(context, address, context.t('place_address_copied')),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.t('edit'),
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => openPlaceEditor(context, existing: place),
          ),
        ]),
      ),
    );
  }
}

/// The parked-car slot: one record, always pinned above the list.
class _ParkingCard extends StatelessWidget {
  final DbService db;
  const _ParkingCard({required this.db});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('parking'),
      builder: (context, snap) {
        final list = snap.data ?? const <Map<String, dynamic>>[];
        final spot = list.isEmpty ? null : list.first;
        final note = spot == null ? '' : str(spot['note']);
        final at = spot == null ? null : DateTime.tryParse(str(spot['at']));
        final lat = spot == null ? null : (spot['lat'] as num?)?.toDouble();
        final lng = spot == null ? null : (spot['lng'] as num?)?.toDouble();

        return DhCard(
          margin: const EdgeInsets.only(top: 2, bottom: 6),
          color: spot == null ? null : tk.tint(tk.warning),
          borderColor: spot == null ? null : tk.warning.withValues(alpha: 0.35),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(icon: Icons.local_parking_rounded, color: tk.warning, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('park_title'), style: context.tt.titleSmall),
                  const SizedBox(height: 2),
                  if (spot == null)
                    Text(context.t('park_none_msg'), style: context.tt.bodySmall)
                  else ...[
                    Text(note,
                        style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    if (at != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: MetaChip(Icons.schedule_rounded, context.relative(at)),
                      ),
                  ],
                ]),
              ),
              if (spot != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t('remove'),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    final id = str(spot['id']);
                    final data = Map<String, dynamic>.from(spot)..remove('id');
                    db.remove('parking', id);
                    showUndo(context, context.t('park_cleared'), () => db.set('parking', id, data));
                  },
                ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 8, children: [
              if (lat != null && lng != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: Text(context.t('park_navigate')),
                  onPressed: () =>
                      _launch(context, LocationService.mapsUrl(lat, lng),
                          context.t('place_open_failed')),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(context.t(spot == null ? 'park_save' : 'park_update')),
                onPressed: () => openParkingEditor(context, db, existing: spot),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- actions

void _copyToClipboard(BuildContext context, String text, String message) {
  Clipboard.setData(ClipboardData(text: text));
  showToast(context, message, icon: Icons.copy_rounded);
}

Future<void> _launch(BuildContext context, String url, String errorMessage) async {
  final uri = Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  showToast(context, errorMessage, icon: Icons.error_outline_rounded);
}

Future<void> _openMaps(BuildContext context, String address) => _launch(
      context,
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
      context.t('place_open_failed'),
    );

void _removePlace(BuildContext context, DbService db, Map<String, dynamic> place) {
  final id = str(place['id']);
  final data = Map<String, dynamic>.from(place)..remove('id');
  db.remove('places', id);
  showUndo(context, context.t('place_removed'), () => db.set('places', id, data));
}

// ---------------------------------------------------------------- editors

/// Add or edit one saved place.
Future<void> openPlaceEditor(BuildContext context, {Map<String, dynamic>? existing}) async {
  final db = DbService.instance;
  final name = TextEditingController(text: str(existing?['name']));
  final address = TextEditingController(text: str(existing?['address']));
  var category = str(existing?['category']);
  if (!PlacesScreen.categories.contains(category)) category = 'Other';

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ctx.t(existing == null ? 'place_add' : 'place_edit'), style: ctx.tt.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: ctx.t('place_name_hint'),
                  prefixIcon: const Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ctx.t('place_address_hint'),
                  prefixIcon: const Icon(Icons.signpost_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Text(ctx.t('category'), style: ctx.tt.labelMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in PlacesScreen.categories)
                  ChoiceChip(
                    avatar: Icon(PlacesScreen.iconFor(c),
                        size: 16,
                        color: category == c ? ctx.cs.primary : ctx.tokens.textMuted),
                    label: Text(PlacesScreen.labelFor(ctx, c)),
                    selected: category == c,
                    onSelected: (_) => set(() => category = c),
                  ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                if (existing != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(ctx.t('delete')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (context.mounted) _removePlace(context, db, existing);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty) {
                      showToast(ctx, ctx.t('place_enter_name'));
                      return;
                    }
                    final data = <String, dynamic>{
                      'name': name.text.trim(),
                      'address': address.text.trim(),
                      'category': category,
                    };
                    Navigator.pop(ctx);
                    if (existing == null) {
                      await db.add('places', data);
                      return;
                    }
                    final id = str(existing['id']);
                    // Merge, so fields written elsewhere (links, extras) survive.
                    final previous = {for (final k in data.keys) k: existing[k]};
                    await db.update('places', id, data);
                    if (!context.mounted) return;
                    showUndo(context, context.t('place_updated'),
                        () => db.update('places', id, previous));
                  },
                  child: Text(ctx.t('save')),
                ),
              ]),
            ],
          ),
        ),
      );
    });
  });
  // Dispose after the sheet's exit animation, never while it is still on screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in [name, address]) {
        c.dispose();
      }
    });
  });
}

/// Save (or replace) the parking spot. GPS is attached when it's available;
/// the typed note stands on its own when it isn't.
Future<void> openParkingEditor(BuildContext context, DbService db,
    {Map<String, dynamic>? existing}) async {
  final note = TextEditingController(text: str(existing?['note']));

  await showAppSheet<void>(context, builder: (ctx) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(ctx.t('park_title'), subtitle: ctx.t('park_sub')),
            TextField(
              controller: note,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ctx.t('park_hint'),
                prefixIcon: const Icon(Icons.local_parking_rounded),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: Text(ctx.t('save')),
              onPressed: () async {
                final text = note.text.trim();
                if (text.isEmpty) {
                  showToast(ctx, ctx.t('park_enter_note'));
                  return;
                }
                Navigator.pop(ctx);
                if (context.mounted) {
                  showToast(context, context.t('park_locating'),
                      icon: Icons.my_location_rounded);
                }
                final data = <String, dynamic>{
                  'note': text,
                  'at': DateTime.now().toIso8601String(),
                };
                final fix = await LocationService.instance.current();
                final pos = fix.position;
                if (pos != null) {
                  data['lat'] = pos.latitude;
                  data['lng'] = pos.longitude;
                }
                // One slot only — replace whatever was there.
                if (existing != null) {
                  await db.set('parking', str(existing['id']), data);
                } else {
                  await db.add('parking', data);
                }
                if (!context.mounted) return;
                showToast(
                  context,
                  context.t(pos == null ? 'park_no_gps' : 'park_saved'),
                  icon: Icons.local_parking_rounded,
                );
              },
            ),
          ],
        ),
      ),
    );
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), note.dispose);
  });
}

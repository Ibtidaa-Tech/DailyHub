import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../features/plan/pickers.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';
import '../ui/kit.dart';

/// Parcel tracker — what's on its way, the day it lands, and when the return
/// window closes (the part people actually miss).
///
/// The expected day is the hero fact on every card: "Arriving tomorrow" is
/// what you open this screen for. Everything else (courier, tracking number,
/// return window) sits underneath it.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  /// Stored verbatim in Firebase. Brand names stay as they are; only "Other"
  /// is a word that needs translating.
  static const carriers = [
    'Amazon', 'Flipkart', 'Myntra', 'Blue Dart', 'Delhivery',
    'India Post', 'DTDC', 'Ekart', 'Other',
  ];

  static String carrierLabel(BuildContext context, String carrier) =>
      carrier == 'Other' ? context.t('trip_other') : carrier;

  /// Public tracking pages. The tracking number is appended where the
  /// courier's URL supports it; otherwise it opens the tracking home page.
  static String? trackUrl(String carrier, String number) {
    final n = Uri.encodeComponent(number.trim());
    return switch (carrier) {
      'Blue Dart' => 'https://www.bluedart.com/tracking?trackFor=0&trackNo=$n',
      'Delhivery' => 'https://www.delhivery.com/track/package/$n',
      'India Post' =>
        'https://www.indiapost.gov.in/_layouts/15/dop.portal.tracking/trackconsignment.aspx',
      'DTDC' => 'https://www.dtdc.in/trace.asp',
      'Amazon' => 'https://www.amazon.in/gp/css/order-history',
      'Flipkart' => 'https://www.flipkart.com/account/orders',
      'Myntra' => 'https://www.myntra.com/my/orders',
      'Ekart' => 'https://ekartlogistics.com/shipmenttrack/$n',
      _ => null,
    };
  }

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  int _tab = 0; // 0 = on the way, 1 = delivered

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream('packages'),
      builder: (context, snap) {
        final all = [...?snap.data]
          // Soonest first; parcels without a date sit at the end.
          ..sort((a, b) {
            final x = str(a['expected']);
            final y = str(b['expected']);
            return (x.isEmpty ? '9999' : x).compareTo(y.isEmpty ? '9999' : y);
          });
        final active = all.where((p) => p['delivered'] != true).toList();
        final delivered = all.where((p) => p['delivered'] == true).toList().reversed.toList();
        final list = _tab == 0 ? active : delivered;

        return AppPage(
          title: context.t('m_packages'),
          subtitle: context.t('pkg_sub'),
          fab: FloatingActionButton.extended(
            heroTag: 'pkgFab',
            onPressed: () => openPackageEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.t('pkg_add')),
          ),
          header: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PillTabs<int>(
              items: [
                (0, active.isEmpty
                    ? context.t('pkg_on_the_way')
                    : '${context.t('pkg_on_the_way')} · ${active.length}'),
                (1, delivered.isEmpty
                    ? context.t('pkg_delivered_tab')
                    : '${context.t('pkg_delivered_tab')} · ${delivered.length}'),
              ],
              value: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          slivers: [
            if (list.isEmpty && snap.hasData)
              SliverToBoxAdapter(
                child: EmptyView(
                  icon: _tab == 0
                      ? Icons.local_shipping_outlined
                      : Icons.inventory_2_outlined,
                  color: AppColors.mPackages,
                  title: context.t(_tab == 0 ? 'pkg_none' : 'pkg_none_delivered'),
                  message: _tab == 0 ? context.t('pkg_none_msg') : null,
                  actionLabel: _tab == 0 ? context.t('pkg_add') : null,
                  onAction: _tab == 0 ? () => openPackageEditor(context) : null,
                ),
              )
            else
              SliverList.list(
                children: [for (final p in list) _PackageCard(db: db, pkg: p)],
              ),
          ],
        );
      },
    );
  }
}

/// One parcel. The expected day is the headline; actions sit below it.
class _PackageCard extends StatelessWidget {
  final DbService db;
  final Map<String, dynamic> pkg;
  const _PackageCard({required this.db, required this.pkg});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final delivered = pkg['delivered'] == true;
    final expected = parseDay(str(pkg['expected']));
    final returnBy = parseDay(str(pkg['returnBy']));
    final carrier = str(pkg['carrier']);
    final tracking = str(pkg['tracking']);
    final item = str(pkg['item']);
    final today = todayDate();
    final isLate = !delivered && expected != null && expected.isBefore(today);
    final returnLeft = returnBy == null ? null : daysBetween(today, returnBy);
    final url = PackagesScreen.trackUrl(carrier, tracking);
    final accent = delivered ? tk.success : (isLate ? tk.danger : AppColors.mPackages);

    return SwipeTile(
      swipeKey: ValueKey('pkg_${pkg['id']}'),
      rightIcon: delivered ? Icons.undo_rounded : Icons.inventory_2_rounded,
      rightColor: delivered ? tk.textMuted : tk.success,
      rightLabel: context.t(delivered ? 'pkg_reopen' : 'pkg_mark_delivered'),
      onSwipeRight: () async {
        _setDelivered(context, db, pkg, !delivered);
        return false; // the stream moves it to the other tab
      },
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        await _removePackage(context, db, pkg);
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        onTap: () => openPackageEditor(context, existing: pkg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconBadge(
              icon: delivered ? Icons.inventory_2_rounded : Icons.local_shipping_rounded,
              color: accent,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      item.isEmpty ? context.t('pkg_untitled') : item,
                      style: context.tt.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isLate) ...[
                    const SizedBox(width: 6),
                    Pill(context.t('pkg_late'), color: tk.danger),
                  ],
                ]),
                const SizedBox(height: 3),
                // The hero fact.
                Text(
                  _whenLabel(context,
                      expected: expected, delivered: delivered, isLate: isLate),
                  style: context.tt.titleMedium?.copyWith(color: accent, fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (carrier.isNotEmpty || returnLeft != null) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 12, runSpacing: 2, children: [
                    if (carrier.isNotEmpty)
                      MetaChip(Icons.storefront_outlined,
                          PackagesScreen.carrierLabel(context, carrier)),
                    if (returnBy != null && returnLeft != null && returnLeft >= 0)
                      MetaChip(
                        Icons.assignment_return_outlined,
                        context.tr('pkg_return_closes', {'x': context.dayLabel(returnBy)}),
                        color: returnLeft <= 3 ? tk.warning : null,
                      ),
                  ]),
                ],
              ]),
            ),
          ]),
          if (tracking.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TrackingChip(tracking: tracking),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (url != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: Text(context.t('pkg_track')),
                onPressed: () =>
                    _launch(context, url, context.t('pkg_track_failed')),
              ),
            if (delivered)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: Text(context.t('pkg_reopen')),
                onPressed: () => _setDelivered(context, db, pkg, false),
              )
            else
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: Text(context.t('pkg_mark_delivered')),
                onPressed: () => _setDelivered(context, db, pkg, true),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// The tracking number, one tap from the clipboard.
class _TrackingChip extends StatelessWidget {
  final String tracking;
  const _TrackingChip({required this.tracking});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Material(
      color: tk.subtle,
      borderRadius: BorderRadius.circular(Radii.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.s),
        onTap: () {
          Clipboard.setData(ClipboardData(text: tracking));
          showToast(context, context.t('pkg_copied'), icon: Icons.copy_rounded);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(Icons.qr_code_2_rounded, size: 16, color: tk.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tracking,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelMedium?.copyWith(letterSpacing: 0.3),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, size: 15, color: tk.textMuted),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers

String _whenLabel(
  BuildContext context, {
  required DateTime? expected,
  required bool delivered,
  required bool isLate,
}) {
  if (delivered) return context.t('pkg_delivered');
  if (expected == null) return context.t('pkg_no_date');
  if (isLate) return context.tr('pkg_late_since', {'x': context.dayLabel(expected)});
  final days = daysBetween(todayDate(), expected);
  if (days == 0) return context.t('pkg_arrives_today');
  if (days == 1) return context.t('pkg_arrives_tomorrow');
  return context.tr('pkg_arrives_on', {'x': context.dayLabel(expected)});
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

void _setDelivered(BuildContext context, DbService db, Map<String, dynamic> pkg, bool value) {
  final id = str(pkg['id']);
  db.update('packages', id, {'delivered': value});
  showUndo(
    context,
    context.t(value ? 'pkg_marked_delivered' : 'pkg_marked_on_way'),
    () => db.update('packages', id, {'delivered': !value}),
  );
}

Future<void> _removePackage(
    BuildContext context, DbService db, Map<String, dynamic> pkg) async {
  final id = str(pkg['id']);
  final data = Map<String, dynamic>.from(pkg)..remove('id');
  await NotificationService.instance.cancel('pkg_$id');
  await db.remove('packages', id);
  if (!context.mounted) return;
  showUndo(context, context.t('pkg_removed'), () => db.set('packages', id, data));
}

// ----------------------------------------------------------------- editor

/// Add or edit a parcel. Saving also re-arms the "arriving today" nudge.
Future<void> openPackageEditor(BuildContext context, {Map<String, dynamic>? existing}) async {
  final db = DbService.instance;
  final item = TextEditingController(text: str(existing?['item']));
  final tracking = TextEditingController(text: str(existing?['tracking']));
  var carrier = str(existing?['carrier']);
  if (!PackagesScreen.carriers.contains(carrier)) {
    carrier = existing == null ? 'Amazon' : 'Other';
  }
  var expected = existing == null
      ? addDays(todayDate(), 3)
      : parseDay(str(existing['expected']));
  var returnBy = existing == null ? null : parseDay(str(existing['returnBy']));

  await showAppSheet<void>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ctx.t(existing == null ? 'pkg_add' : 'pkg_edit'), style: ctx.tt.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: item,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: ctx.t('pkg_item_hint'),
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Text(ctx.t('pkg_courier'), style: ctx.tt.labelMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in PackagesScreen.carriers)
                  ChoiceChip(
                    label: Text(PackagesScreen.carrierLabel(ctx, c)),
                    selected: carrier == c,
                    onSelected: (_) => set(() => carrier = c),
                  ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: tracking,
                decoration: InputDecoration(
                  hintText: '${ctx.t('pkg_tracking')} · ${ctx.t('optional')}',
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                ),
              ),
              const SizedBox(height: 12),
              FormFieldButton(
                icon: Icons.event_rounded,
                label: ctx.t('pkg_expected'),
                value: expected == null ? ctx.t('pkg_no_date') : ctx.dayLabel(expected!),
                onTap: () async {
                  final picked = await pickDay(ctx, initial: expected, title: ctx.t('pkg_expected'));
                  if (picked != null) set(() => expected = picked.value);
                },
              ),
              const SizedBox(height: 10),
              FormFieldButton(
                icon: Icons.assignment_return_outlined,
                label: ctx.t('pkg_return_by'),
                value: returnBy == null ? ctx.t('none') : ctx.dayLabel(returnBy!),
                onTap: () async {
                  final picked = await pickDay(ctx,
                      initial: returnBy ?? addDays(todayDate(), 10), title: ctx.t('pkg_return_by'));
                  if (picked != null) set(() => returnBy = picked.value);
                },
              ),
              const SizedBox(height: 18),
              Row(children: [
                if (existing != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(ctx.t('delete')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (context.mounted) _removePackage(context, db, existing);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final name = item.text.trim();
                    if (name.isEmpty) {
                      showToast(ctx, ctx.t('pkg_enter_item'));
                      return;
                    }
                    final due = expected;
                    final notifyTitle = ctx.t('pkg_notify_title');
                    final data = <String, dynamic>{
                      'item': name,
                      'carrier': carrier,
                      'tracking': tracking.text.trim(),
                      'expected': due == null ? '' : dayKey(due),
                      'returnBy': returnBy == null ? '' : dayKey(returnBy!),
                      'delivered': existing?['delivered'] ?? false,
                    };
                    Navigator.pop(ctx);
                    String id;
                    if (existing == null) {
                      id = await db.add('packages', data);
                    } else {
                      id = str(existing['id']);
                      // Merge, so fields written elsewhere survive the edit.
                      final previous = {for (final k in data.keys) k: existing[k]};
                      await db.update('packages', id, data);
                      if (context.mounted) {
                        showUndo(context, context.t('pkg_updated'),
                            () => db.update('packages', id, previous));
                      }
                    }
                    // Nudge on the morning it's due.
                    await NotificationService.instance.cancel('pkg_$id');
                    if (due != null && data['delivered'] != true) {
                      await NotificationService.instance.scheduleAt(
                        key: 'pkg_$id',
                        title: notifyTitle,
                        body: name,
                        when: DateTime(due.year, due.month, due.day, 9),
                      );
                    }
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
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in [item, tracking]) {
        c.dispose();
      }
    });
  });
}

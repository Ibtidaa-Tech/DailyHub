import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_models.dart';
import '../../data/tracker_store.dart';
import '../../ui/kit.dart';
import 'tracker_ui.dart';

/// The paper sheet, on screen: dates down the side, habits across the top.
///
/// The date column is frozen and the habit columns scroll sideways, which is
/// the only way 11+ columns stay usable on a phone. Two horizontal
/// controllers (header + body) are kept in step by hand; a single scroll view
/// around both would take the date column with it.
class TrackerGrid extends StatefulWidget {
  final Challenge challenge;
  final TrackerStore store;
  final void Function(TrackerItem item, DateTime day) onTick;
  final void Function(TrackerItem item)? onItemTap;

  /// A mentor looking at a student's sheet: everything visible, nothing
  /// tappable. Only the person doing the habit records it.
  final bool readOnly;

  const TrackerGrid({
    super.key,
    required this.challenge,
    required this.store,
    required this.onTick,
    this.onItemTap,
    this.readOnly = false,
  });

  @override
  State<TrackerGrid> createState() => _TrackerGridState();
}

class _TrackerGridState extends State<TrackerGrid> {
  static const double _dateW = 78;
  static const double _colW = 56;
  static const double _rowH = 42;
  static const double _headH = 62;

  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  final ScrollController _v = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _headerH.addListener(() => _mirror(_headerH, _bodyH));
    _bodyH.addListener(() => _mirror(_bodyH, _headerH));
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    _v.dispose();
    super.dispose();
  }

  /// Copies one horizontal offset onto the other. The guard stops the two
  /// listeners bouncing the value back and forth forever.
  void _mirror(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients || !from.hasClients) return;
    if ((to.offset - from.offset).abs() < 0.5) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(
      to.position.minScrollExtent,
      to.position.maxScrollExtent,
    ));
    _syncing = false;
  }

  /// Opens on today rather than on day 1, which is three weeks of scrolling
  /// away by the end of a run.
  void _jumpToToday({bool animate = false}) {
    if (!_v.hasClients) return;
    final days = widget.challenge.allDays();
    final idx = days.indexWhere((d) => sameDay(d, todayDate()));
    if (idx < 0) return;
    final target = (idx * _rowH - _rowH * 2)
        .clamp(_v.position.minScrollExtent, _v.position.maxScrollExtent);
    if (animate) {
      _v.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _v.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final store = widget.store;
    final items = store.itemsOf(c.id);
    final days = c.allDays();
    final tk = context.tokens;
    final today = todayDate();

    if (items.isEmpty) {
      return EmptyView(
        icon: Icons.grid_on_rounded,
        title: context.t('tr_no_items_title'),
        message: context.t('tr_no_items_msg'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One container with a uniform border around the whole table. A
        // per-section border plus a borderRadius is not allowed — BoxDecoration
        // throws when a radius meets a border that isn't uniform on all sides.
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border.all(color: tk.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              // -------------------------------------------------- header
              Container(
                color: tk.subtle,
                child: Row(children: [
                  SizedBox(
                    width: _dateW,
                    height: _headH,
                    child: Center(
                      child: Text(context.t('tr_date'),
                          style: context.tt.labelSmall?.copyWith(color: tk.textMuted)),
                    ),
                  ),
                  Container(width: 1, height: _headH, color: tk.border),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _headerH,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Row(children: [
                        for (final i in items) _headerCell(i),
                      ]),
                    ),
                  ),
                ]),
              ),
              Container(height: 1, color: tk.border),
              // ---------------------------------------------------- body
              Expanded(
                child: SingleChildScrollView(
                  controller: _v,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Frozen date column.
                    Column(children: [
                      for (final d in days) _dateCell(d, today),
                    ]),
                    Container(width: 1, height: days.length * _rowH, color: tk.border),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _bodyH,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: Column(children: [
                          for (final d in days) _bodyRow(d, items, today),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(context.t('tr_scroll_hint'), style: context.tt.bodySmall)),
          TextButton.icon(
            onPressed: () => _jumpToToday(animate: true),
            icon: const Icon(Icons.today_rounded, size: 16),
            label: Text(context.t('tr_jump_today')),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ]),
        const SizedBox(height: 4),
        const TickLegend(),
      ],
    );
  }

  Widget _headerCell(TrackerItem i) {
    final color = AppColors.swatch(i.color);
    return SizedBox(
      width: _colW,
      height: _headH,
      child: InkWell(
        onTap: widget.onItemTap == null ? null : () => widget.onItemTap!(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(i.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              i.name,
              maxLines: i.currentTarget == null ? 2 : 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.tt.labelSmall?.copyWith(
                fontSize: 9.5,
                height: 1.1,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            // The number you are aiming at today, under the name. Each day's
            // own target lives in that day's details, where history belongs.
            if (i.currentTarget != null)
              Text(
                i.currentTarget!.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelSmall?.copyWith(
                  fontSize: 8.5,
                  height: 1.1,
                  color: context.tokens.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _dateCell(DateTime d, DateTime today) {
    final tk = context.tokens;
    final isToday = sameDay(d, today);
    final n = widget.challenge.dayNumber(d);
    return Container(
      width: _dateW,
      height: _rowH,
      decoration: BoxDecoration(
        color: isToday ? context.cs.primaryContainer : (d.weekday == DateTime.sunday ? tk.subtle : null),
        border: Border(bottom: BorderSide(color: tk.border.withValues(alpha: 0.6))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.fmtDate(d, 'd MMM'),
                  style: context.tt.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: isToday ? context.cs.primary : null,
                  )),
              Text(context.fmtDate(d, 'EEE'),
                  style: context.tt.bodySmall?.copyWith(fontSize: 9.5, color: tk.textMuted)),
            ],
          ),
        ),
        if (n != null)
          Text('$n',
              style: context.tt.labelSmall?.copyWith(
                fontSize: 9,
                color: isToday ? context.cs.primary : tk.textFaint,
              )),
      ]),
    );
  }

  Widget _bodyRow(DateTime d, List<TrackerItem> items, DateTime today) {
    final tk = context.tokens;
    final isToday = sameDay(d, today);
    final isFuture = d.isAfter(today);
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: isToday
            ? context.cs.primaryContainer.withValues(alpha: 0.35)
            : (d.weekday == DateTime.sunday ? tk.subtle.withValues(alpha: 0.5) : null),
        border: Border(bottom: BorderSide(color: tk.border.withValues(alpha: 0.6))),
      ),
      child: Row(children: [
        for (final i in items)
          SizedBox(
            width: _colW,
            child: Center(
              child: TickBox(
                status: widget.store.statusOf(widget.challenge, i, d),
                color: AppColors.swatch(i.color),
                outOfRange: !i.runsOn(d),
                enabled: !widget.readOnly && !isFuture && i.runsOn(d),
                onTap: () => widget.onTick(i, d),
              ),
            ),
          ),
      ]),
    );
  }
}

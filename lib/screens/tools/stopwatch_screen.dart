import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../services/notification_service.dart';
import '../../ui/kit.dart';

/// Stopwatch with laps, and a countdown timer.
///
/// Both live in this one State so switching tabs never kills a running clock,
/// and both tickers are cancelled in [dispose] so nothing outlives the screen.
/// The countdown works off a deadline rather than by subtracting a second per
/// tick, so a stalled frame can't leave it slow or stuck.
class StopwatchScreen extends StatefulWidget {
  const StopwatchScreen({super.key});

  @override
  State<StopwatchScreen> createState() => _StopwatchScreenState();
}

String _fmtDuration(Duration d, {bool millis = false}) {
  final v = d.isNegative ? Duration.zero : d;
  final h = v.inHours;
  final m = v.inMinutes % 60;
  final s = v.inSeconds % 60;
  final ms = (v.inMilliseconds % 1000) ~/ 10;
  final base = h > 0
      ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return millis ? '$base.${ms.toString().padLeft(2, '0')}' : base;
}

class _StopwatchScreenState extends State<StopwatchScreen> {
  static const Duration _minTimer = Duration(minutes: 1);

  int _tab = 0;

  // Stopwatch
  final _watch = Stopwatch();
  Timer? _swTicker;
  final _laps = <Duration>[];

  // Countdown
  Duration _total = const Duration(minutes: 5);
  Duration _left = const Duration(minutes: 5);
  DateTime? _deadline;
  Timer? _tmTicker;

  bool get _timerRunning => _deadline != null;

  @override
  void dispose() {
    _swTicker?.cancel();
    _tmTicker?.cancel();
    _swTicker = null;
    _tmTicker = null;
    super.dispose();
  }

  // ----------------------------------------------------------- stopwatch

  void _swToggle() {
    HapticFeedback.selectionClick();
    // Cancel first, always: a double tap must never leave two tickers running.
    _swTicker?.cancel();
    _swTicker = null;
    setState(() {
      if (_watch.isRunning) {
        _watch.stop();
      } else {
        _watch.start();
        _swTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
          if (!mounted) return;
          setState(() {});
        });
      }
    });
  }

  Future<void> _swReset() async {
    // Laps can't be brought back once the watch is zeroed, so ask first —
    // but only when there is actually something to lose.
    if (_laps.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: context.t('reset'),
        message: context.t('sw_reset_q'),
        confirm: context.t('reset'),
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final had = _laps.isNotEmpty;
    HapticFeedback.mediumImpact();
    _swTicker?.cancel();
    _swTicker = null;
    setState(() {
      _watch
        ..stop()
        ..reset();
      _laps.clear();
    });
    if (had) showToast(context, context.t('sw_laps_cleared'), icon: Icons.replay_rounded);
  }

  void _swLap() {
    HapticFeedback.selectionClick();
    setState(() => _laps.add(_watch.elapsed));
  }

  // --------------------------------------------------------------- timer

  void _tmStart() {
    if (_left <= Duration.zero) return;
    HapticFeedback.selectionClick();
    _tmTicker?.cancel();
    setState(() => _deadline = DateTime.now().add(_left));
    _tmTicker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tmTick());
  }

  void _tmTick() {
    if (!mounted) return;
    final end = _deadline;
    if (end == null) {
      _tmStop();
      return;
    }
    final rem = end.difference(DateTime.now());
    if (rem <= Duration.zero) {
      _tmFinish();
    } else {
      setState(() => _left = rem);
    }
  }

  /// Stops the ticker without touching what's left on the clock.
  void _tmStop() {
    _tmTicker?.cancel();
    _tmTicker = null;
    if (mounted) setState(() => _deadline = null);
  }

  void _tmPause() {
    HapticFeedback.selectionClick();
    final end = _deadline;
    final rem = end == null ? _left : end.difference(DateTime.now());
    _tmTicker?.cancel();
    _tmTicker = null;
    setState(() {
      _deadline = null;
      _left = rem <= Duration.zero ? Duration.zero : rem;
    });
  }

  void _tmFinish() {
    _tmTicker?.cancel();
    _tmTicker = null;
    if (!mounted) return;
    setState(() {
      _deadline = null;
      _left = Duration.zero;
    });
    HapticFeedback.heavyImpact();
    // Fires even if the screen is backgrounded on mobile.
    NotificationService.instance.showNow(
      context.t('sw_finished'),
      context.tr('sw_finished_msg', {'d': _fmtDuration(_total)}),
    );
    showToast(context, context.t('sw_finished'), icon: Icons.alarm_on_rounded);
  }

  void _tmReset() {
    HapticFeedback.mediumImpact();
    _tmTicker?.cancel();
    _tmTicker = null;
    setState(() {
      _deadline = null;
      _left = _total;
    });
  }

  void _tmSetLength(Duration d) {
    if (d < _minTimer) {
      showToast(context, context.t('sw_pick_length'), icon: Icons.timer_outlined);
      return;
    }
    HapticFeedback.selectionClick();
    _tmTicker?.cancel();
    _tmTicker = null;
    setState(() {
      _deadline = null;
      _total = d;
      _left = d;
    });
  }

  Future<void> _tmPickLength() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _total.inHours % 24, minute: _total.inMinutes % 60),
      helpText: context.t('sw_set_timer'),
    );
    if (picked == null || !mounted) return;
    _tmSetLength(Duration(hours: picked.hour, minutes: picked.minute));
  }

  // ---------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: context.t('tool_time'),
      subtitle: context.t('tool_time_sub'),
      maxWidth: 560,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: PillTabs<int>(
          items: [(0, context.t('sw_stopwatch')), (1, context.t('sw_timer'))],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      slivers: _tab == 1 ? _timerSlivers(context) : _stopwatchSlivers(context),
    );
  }

  List<Widget> _stopwatchSlivers(BuildContext context) {
    const accent = AppColors.mHabits;
    final elapsed = _watch.elapsed;
    final idle = elapsed == Duration.zero && !_watch.isRunning;

    return [
      SliverToBoxAdapter(
        child: Column(children: [
          const SizedBox(height: 18),
          _BigTime(text: _fmtDuration(elapsed, millis: true), color: accent),
          const SizedBox(height: 8),
          Text(
            _watch.isRunning ? context.t('sw_running') : context.t('sw_paused'),
            style: context.tt.labelMedium?.copyWith(color: context.tokens.textMuted),
          ),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: idle ? null : _swReset,
                child: Text(context.t('reset'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _swToggle,
                child: Text(_watch.isRunning ? context.t('pause') : context.t('start'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _watch.isRunning ? _swLap : null,
                child: Text(context.t('sw_lap'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          const SizedBox(height: 10),
        ]),
      ),
      if (_laps.isEmpty)
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.timer_outlined,
            color: accent,
            title: context.t('sw_no_laps'),
            message: context.t('sw_no_laps_msg'),
            compact: true,
          ),
        )
      else ...[
        SliverToBoxAdapter(child: SectionTitle(context.t('sw_lap'))),
        SliverList.builder(
          itemCount: _laps.length,
          itemBuilder: (context, i) {
            final idx = _laps.length - 1 - i;
            final lap = _laps[idx];
            final prev = idx == 0 ? Duration.zero : _laps[idx - 1];
            return DhCard(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Text(context.tr('sw_lap_n', {'n': idx + 1}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelMedium
                          ?.copyWith(color: context.tokens.textMuted)),
                ),
                Text(_fmtDuration(lap - prev, millis: true),
                    style: context.tt.titleSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 14),
                Text(_fmtDuration(lap, millis: true),
                    style: context.tt.bodySmall?.copyWith(
                        color: context.tokens.textFaint,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            );
          },
        ),
      ],
    ];
  }

  List<Widget> _timerSlivers(BuildContext context) {
    final tk = context.tokens;
    final urgent = _left.inSeconds <= 10 && _timerRunning;
    final accent = urgent ? tk.danger : AppColors.mHabits;
    final totalMs = _total.inMilliseconds;
    // `.clamp` is declared on num and returns num, so the result is forced back
    // to double before it reaches ProgressRing's `value`.
    final double progress = totalMs <= 0
        ? 0.0
        : (1 - _left.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();

    return [
      SliverToBoxAdapter(
        child: Column(children: [
          const SizedBox(height: 14),
          Center(
            child: ProgressRing(
              value: progress,
              size: 206,
              stroke: 12,
              color: accent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _BigTime(text: _fmtDuration(_left), color: accent, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [1, 3, 5, 10, 15, 30, 60])
                ChoiceChip(
                  label: Text(context.tr('sw_mins', {'n': m})),
                  selected: _total.inMinutes == m && !_timerRunning,
                  onSelected: (_) => _tmSetLength(Duration(minutes: m)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _left == _total && !_timerRunning ? null : _tmReset,
                child: Text(context.t('reset'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _timerRunning
                    ? _tmPause
                    : (_left <= Duration.zero ? null : _tmStart),
                child: Text(_timerRunning ? context.t('pause') : context.t('start'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: Text(context.t('sw_custom')),
            onPressed: _tmPickLength,
          ),
        ]),
      ),
    ];
  }
}

/// The clock itself: tabular figures so the digits never shuffle sideways.
class _BigTime extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const _BigTime({required this.text, required this.color, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style: context.tt.displaySmall?.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../services/notification_service.dart';
import '../../ui/kit.dart';

/// Pomodoro focus timer. Keeps time from an end timestamp, so it stays
/// correct if the app is backgrounded, and a notification fires when the
/// session ends even if the app is closed.
class FocusScreen extends StatefulWidget {
  final Task? task;
  const FocusScreen({super.key, this.task});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  static const _logKey = 'dh_focus_log';
  int _focusMin = 25;
  int _breakMin = 5;
  bool _onBreak = false;
  DateTime? _endsAt;
  Duration _left = const Duration(minutes: 25);
  Timer? _tick;
  Task? _task;
  int _todayMin = 0;
  int _todaySessions = 0;

  bool get _running => _endsAt != null;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _loadLog();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = jsonDecode(prefs.getString(_logKey) ?? '{}') as Map<String, dynamic>;
      final today = m[dayKey(DateTime.now())];
      if (today is Map && mounted) {
        setState(() {
          _todayMin = toI(today['min']);
          _todaySessions = toI(today['n']);
        });
      }
    } catch (_) {}
  }

  Future<void> _logSession(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = jsonDecode(prefs.getString(_logKey) ?? '{}') as Map<String, dynamic>;
      final k = dayKey(DateTime.now());
      final cur = m[k] is Map ? Map<String, dynamic>.from(m[k]) : <String, dynamic>{};
      cur['min'] = toI(cur['min']) + minutes;
      cur['n'] = toI(cur['n']) + 1;
      m[k] = cur;
      // Keep the last 60 days only.
      final keys = m.keys.toList()..sort();
      while (keys.length > 60) {
        m.remove(keys.removeAt(0));
      }
      await prefs.setString(_logKey, jsonEncode(m));
      if (mounted) {
        setState(() {
          _todayMin = toI(cur['min']);
          _todaySessions = toI(cur['n']);
        });
      }
    } catch (_) {}
  }

  void _start() {
    HapticFeedback.mediumImpact();
    final end = DateTime.now().add(_left);
    setState(() => _endsAt = end);
    NotificationService.instance.scheduleAt(
      key: 'focus_end',
      title: context.t(_onBreak ? 'focus_break_over' : 'focus_session_done'),
      body: _task?.title ?? context.t('focus_take_break'),
      when: end,
    );
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
  }

  void _pause() {
    _tick?.cancel();
    NotificationService.instance.cancel('focus_end');
    setState(() {
      if (_endsAt != null) _left = _endsAt!.difference(DateTime.now());
      _endsAt = null;
    });
  }

  void _reset() {
    _tick?.cancel();
    NotificationService.instance.cancel('focus_end');
    setState(() {
      _endsAt = null;
      _left = Duration(minutes: _onBreak ? _breakMin : _focusMin);
    });
  }

  void _onTick() {
    final end = _endsAt;
    if (end == null) return;
    final left = end.difference(DateTime.now());
    if (left <= Duration.zero) {
      _tick?.cancel();
      HapticFeedback.heavyImpact();
      final wasBreak = _onBreak;
      if (!wasBreak) {
        _logSession(_focusMin);
        final t = _task;
        if (t != null) context.read<PlanStore>().addFocus(t, _focusMin);
      }
      setState(() {
        _endsAt = null;
        _onBreak = !wasBreak;
        _left = Duration(minutes: _onBreak ? _breakMin : _focusMin);
      });
      showToast(context, context.t(wasBreak ? 'focus_break_over' : 'focus_session_done'), icon: Icons.celebration_rounded);
      return;
    }
    setState(() => _left = left);
  }

  String _fmt(Duration d) {
    final s = d.inSeconds.clamp(0, 99 * 60);
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _pickTask() async {
    final plan = context.read<PlanStore>();
    final t = await showAppSheet<Task>(context, builder: (ctx) {
      final tasks = plan.open.take(40).toList();
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: Column(children: [
            SheetHeader(ctx.t('focus_pick_task')),
            Expanded(
              child: tasks.isEmpty
                  ? Center(child: Text(ctx.t('no_open_tasks'), style: ctx.tt.bodySmall))
                  : ListView(children: [
                      for (final t in tasks)
                        ListTile(
                          leading: Icon(Icons.radio_button_unchecked_rounded, color: Prio.color(t.priority)),
                          title: Text(t.title),
                          onTap: () => Navigator.pop(ctx, t),
                        ),
                    ]),
            ),
          ]),
        ),
      );
    });
    if (t != null) setState(() => _task = t);
  }

  @override
  Widget build(BuildContext context) {
    final total = Duration(minutes: _onBreak ? _breakMin : _focusMin).inSeconds;
    final progress = total == 0 ? 0.0 : 1 - _left.inSeconds / total;
    final color = _onBreak ? context.tokens.success : context.cs.primary;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('m_focus'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Center(
                child: Pill(context.t(_onBreak ? 'focus_break' : 'focus_focus'), color: color, icon: _onBreak ? Icons.coffee_rounded : Icons.bolt_rounded),
              ),
              const SizedBox(height: 18),
              Center(
                child: ProgressRing(
                  value: progress,
                  size: 250,
                  stroke: 14,
                  color: color,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_fmt(_left), style: context.tt.displaySmall?.copyWith(fontSize: 52, fontFeatures: const [FontFeature.tabularFigures()])),
                    Text(context.tr('focus_min_session', {'n': _onBreak ? _breakMin : _focusMin}), style: context.tt.bodySmall),
                  ]),
                ),
              ),
              const SizedBox(height: 22),
              DhCard(
                onTap: _running ? null : _pickTask,
                child: Row(children: [
                  Icon(Icons.task_alt_rounded, color: context.tokens.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_task?.title ?? context.t('focus_no_task'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodyLarge),
                  ),
                  if (!_running) Icon(Icons.expand_more_rounded, color: context.tokens.textFaint),
                ]),
              ),
              if (!_running) ...[
                const SizedBox(height: 10),
                ChipRow<int>(
                  items: const [(15, '15'), (25, '25'), (45, '45'), (60, '60')],
                  value: _focusMin,
                  leading: Text(context.t('focus_minutes'), style: context.tt.labelMedium),
                  onSelected: (v) => setState(() {
                    _focusMin = v;
                    if (!_onBreak) _left = Duration(minutes: v);
                  }),
                ),
                const SizedBox(height: 6),
                ChipRow<int>(
                  items: const [(5, '5'), (10, '10'), (15, '15')],
                  value: _breakMin,
                  leading: Text(context.t('focus_break_minutes'), style: context.tt.labelMedium),
                  onSelected: (v) => setState(() {
                    _breakMin = v;
                    if (_onBreak) _left = Duration(minutes: v);
                  }),
                ),
              ],
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(context.t('reset')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: _running ? _pause : _start,
                    icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    label: Text(context.t(_running ? 'pause' : 'start')),
                  ),
                ),
              ]),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: StatBlock(label: context.t('focus_today'), value: context.tr('dur_min', {'n': _todayMin}))),
                Expanded(child: StatBlock(label: context.t('focus_sessions'), value: '$_todaySessions')),
                if (_task != null && _task!.focus > 0)
                  Expanded(child: StatBlock(label: context.t('focus_on_task'), value: context.tr('dur_min', {'n': _task!.focus}))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

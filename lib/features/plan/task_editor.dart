import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/quick_parse.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import 'focus_screen.dart';
import 'pickers.dart';

/// Opens the task editor sheet (new or existing task).
Future<void> openTaskEditor(
  BuildContext context, {
  Task? task,
  DateTime? day,
  String? list,
  String? initialTitle,
  String? priority,
}) {
  final store = context.read<PlanStore>();
  final ws = context.read<WorkspaceProvider>();
  return showAppSheet(
    context,
    expand: task != null,
    builder: (ctx) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: ws),
      ],
      child: _TaskSheet(task: task, day: day, list: list, initialTitle: initialTitle, priority: priority),
    ),
  );
}

class _TaskSheet extends StatefulWidget {
  final Task? task;
  final DateTime? day;
  final String? list;
  final String? initialTitle;
  final String? priority;
  const _TaskSheet({this.task, this.day, this.list, this.initialTitle, this.priority});
  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late Task _t;
  late final TextEditingController _title;
  late final TextEditingController _desc;
  final TextEditingController _sub = TextEditingController();
  late final PlanStore _store;
  late final bool _canEdit;
  bool _saved = false;
  bool _dirty = false;
  Parsed? _hint;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    _store = context.read<PlanStore>();
    final ws = context.read<WorkspaceProvider>();
    _canEdit = _isNew ? ws.canAdd : ws.canEdit;
    _t = widget.task?.copy() ??
        Task(
          date: widget.day == null ? '' : dayKey(widget.day!),
          list: widget.list ?? '',
          priority: widget.priority ?? Prio.none,
        );
    _title = TextEditingController(text: widget.task?.title ?? widget.initialTitle ?? '');
    _desc = TextEditingController(text: _t.desc);
    _title.addListener(_onTitle);
    _desc.addListener(() => _dirty = true);
    if (widget.initialTitle != null) _onTitle();
  }

  void _onTitle() {
    _dirty = true;
    if (!_isNew) return;
    final p = QuickParse.parse(_title.text);
    final useful = p.date != null || p.tags.isNotEmpty || p.priority != 'none' || p.repeat != 'none';
    final next = useful && p.title.isNotEmpty ? p : null;
    if ((next == null) != (_hint == null) || (next != null && _hint != null && next.source != _hint!.source)) {
      setState(() => _hint = next);
    }
  }

  void _applyHint() {
    final p = _hint;
    if (p == null) return;
    setState(() {
      if (p.date != null) {
        _t.date = dayKey(p.date!);
        _t.time = p.hasTime ? hmOf(p.date!) : _t.time;
      }
      if (p.repeat != 'none') _t.repeat = p.repeat;
      if (p.priority != 'none') _t.priority = p.priority;
      _t.tags = {..._t.tags, ...p.tags}.toList();
      _title.removeListener(_onTitle);
      _title.text = p.title;
      _title.addListener(_onTitle);
      _hint = null;
    });
  }

  @override
  void dispose() {
    // Existing tasks save automatically when the sheet is closed.
    if (!_saved && !_isNew && _dirty && _canEdit && _title.text.trim().isNotEmpty) {
      _commit();
    }
    _title.dispose();
    _desc.dispose();
    _sub.dispose();
    super.dispose();
  }

  void _commit() {
    _t.title = _title.text.trim();
    _t.desc = _desc.text.trim();
    if (_t.remind > 0 && !_t.hasTime) _t.remind = 0;
    _store.saveTask(_t);
    _saved = true;
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    if (_isNew && _hint != null) _applyHint();
    _commit();
    Navigator.pop(context);
    showToast(context, context.t(_isNew ? 'task_added' : 'saved'), icon: Icons.check_circle_rounded);
  }

  void _set(VoidCallback f) {
    _dirty = true;
    setState(f);
  }

  Future<void> _pickDate() async {
    final r = await pickDay(context, initial: _t.dueDate);
    if (r == null) return;
    _set(() {
      _t.date = r.value == null ? '' : dayKey(r.value!);
      if (r.value == null) {
        _t.time = '';
        _t.repeat = 'none';
      }
    });
  }

  Future<void> _pickTime() async {
    final r = await pickTime(context, initial: parseHm(_t.time));
    if (r == null) return;
    _set(() {
      _t.time = r.value == null ? '' : hmKey(r.value!.hour, r.value!.minute);
      if (r.value != null && _t.date.isEmpty) _t.date = dayKey(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final list = _store.listById(_t.list);
    final overdue = _t.isOverdue();
    return SafeArea(
      child: Column(
        mainAxisSize: _isNew ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Flexible(
            fit: _isNew ? FlexFit.loose : FlexFit.tight,
            child: ListView(
              shrinkWrap: _isNew,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!_isNew)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 4),
                      child: CheckDot(
                        checked: _t.isDone,
                        color: Prio.color(_t.priority),
                        onTap: _canEdit
                            ? () {
                                _store.toggleTask(widget.task!);
                                _saved = true;
                                Navigator.pop(context);
                              }
                            : null,
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _title,
                      enabled: _canEdit,
                      autofocus: _isNew,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: context.tt.titleLarge,
                      decoration: InputDecoration(
                        hintText: context.t('task_title_hint'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: _isNew ? (_) => _save() : null,
                    ),
                  ),
                ]),
                if (_hint != null) _HintBar(parsed: _hint!, onApply: _applyHint),
                TextField(
                  controller: _desc,
                  enabled: _canEdit,
                  maxLines: null,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: context.tt.bodyMedium,
                  decoration: InputDecoration(
                    hintText: context.t('add_details'),
                    prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Chip(
                    icon: Icons.event_rounded,
                    label: _t.dueDate == null ? context.t('date') : context.dayLabel(_t.dueDate!),
                    active: _t.dueDate != null,
                    color: overdue ? tk.danger : null,
                    onTap: _canEdit ? _pickDate : null,
                  ),
                  _Chip(
                    icon: Icons.schedule_rounded,
                    label: _t.hasTime ? context.timeOfHm(_t.time) : context.t('time'),
                    active: _t.hasTime,
                    onTap: _canEdit ? _pickTime : null,
                  ),
                  if (_t.hasTime)
                    _Chip(
                      icon: _t.remind < 0 ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
                      label: remindLabel(context, _t.remind),
                      active: _t.remind >= 0,
                      onTap: _canEdit
                          ? () async {
                              final r = await pickRemind(context, _t.remind);
                              if (r != null) _set(() => _t.remind = r);
                            }
                          : null,
                    ),
                  _Chip(
                    icon: Icons.repeat_rounded,
                    label: _t.repeat == 'none' ? context.t('repeat') : repeatLabel(context, _t.repeat),
                    active: _t.repeat != 'none',
                    onTap: _canEdit
                        ? () async {
                            final r = await pickRepeat(context, _t.repeat);
                            if (r != null) {
                              _set(() {
                                _t.repeat = r;
                                if (r != 'none' && _t.date.isEmpty) _t.date = dayKey(DateTime.now());
                              });
                            }
                          }
                        : null,
                  ),
                  _Chip(
                    icon: _t.priority == Prio.none ? Icons.outlined_flag_rounded : Icons.flag_rounded,
                    label: _t.priority == Prio.none ? context.t('priority') : prioLabel(context, _t.priority),
                    active: _t.priority != Prio.none,
                    color: _t.priority == Prio.none ? null : Prio.color(_t.priority),
                    onTap: _canEdit
                        ? () async {
                            final r = await pickPriority(context, _t.priority);
                            if (r != null) _set(() => _t.priority = r);
                          }
                        : null,
                  ),
                  _Chip(
                    icon: Icons.folder_outlined,
                    emoji: list?.emoji,
                    label: list?.name ?? context.t('inbox'),
                    active: list != null,
                    onTap: _canEdit
                        ? () async {
                            final r = await pickList(context, _t.list);
                            if (r != null) _set(() => _t.list = r.value ?? '');
                          }
                        : null,
                  ),
                  _Chip(
                    icon: Icons.tag_rounded,
                    label: _t.tags.isEmpty ? context.t('tags') : _t.tags.map((e) => '#$e').join(' '),
                    active: _t.tags.isNotEmpty,
                    onTap: _canEdit
                        ? () async {
                            final r = await pickTags(context, _t.tags);
                            if (r != null) _set(() => _t.tags = r);
                          }
                        : null,
                  ),
                ]),
                const SizedBox(height: 16),
                _subtasks(context),
                if (!_isNew && (_t.focus > 0 || toI(_t.raw['doneCount']) > 0)) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 14, children: [
                    if (_t.focus > 0) MetaChip(Icons.timer_outlined, context.tr('focused_min', {'n': _t.focus})),
                    if (toI(_t.raw['doneCount']) > 0)
                      MetaChip(Icons.repeat_rounded, context.tr('done_times', {'n': toI(_t.raw['doneCount'])})),
                  ]),
                ],
              ],
            ),
          ),
          _bottomBar(context),
        ],
      ),
    );
  }

  Widget _subtasks(BuildContext context) {
    final tk = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_t.subtasks.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 2),
          child: Text('${context.t('subtasks')} · ${_t.subDone}/${_t.subtasks.length}',
              style: context.tt.labelSmall?.copyWith(color: tk.textMuted)),
        ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (a, b) => _set(() {
          final s = _t.subtasks.removeAt(a);
          _t.subtasks.insert(b.clamp(0, _t.subtasks.length), s);
        }),
        children: [
          for (var i = 0; i < _t.subtasks.length; i++)
            Row(
              key: ValueKey('sub_${i}_${_t.subtasks[i].title}'),
              children: [
                Checkbox(
                  value: _t.subtasks[i].done,
                  onChanged: _canEdit ? (v) => _set(() => _t.subtasks[i].done = v ?? false) : null,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: !_canEdit
                        ? null
                        : () async {
                            final v = await promptText(context, title: context.t('edit_subtask'), initial: _t.subtasks[i].title);
                            if (v != null && v.trim().isNotEmpty) _set(() => _t.subtasks[i].title = v.trim());
                          },
                    child: Text(_t.subtasks[i].title,
                        style: context.tt.bodyMedium?.copyWith(
                          decoration: _t.subtasks[i].done ? TextDecoration.lineThrough : null,
                          color: _t.subtasks[i].done ? tk.textFaint : null,
                        )),
                  ),
                ),
                if (_canEdit)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: tk.textFaint),
                    onPressed: () => _set(() => _t.subtasks.removeAt(i)),
                  ),
                if (_canEdit)
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator_rounded, size: 18, color: tk.textFaint),
                    ),
                  ),
              ],
            ),
        ],
      ),
      if (_canEdit)
        TextField(
          controller: _sub,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('add_subtask'),
            prefixIcon: const Icon(Icons.add_rounded, size: 20),
            isDense: true,
          ),
          onSubmitted: (v) {
            if (v.trim().isEmpty) return;
            _set(() => _t.subtasks.add(SubItem(v.trim())));
            _sub.clear();
          },
        ),
    ]);
  }

  Widget _bottomBar(BuildContext context) {
    final tk = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: tk.border))),
      child: Row(children: [
        if (!_isNew && context.read<WorkspaceProvider>().canEdit)
          IconButton(
            tooltip: context.t('delete'),
            icon: Icon(Icons.delete_outline_rounded, color: tk.danger),
            onPressed: () {
              final t = widget.task!;
              final data = _store.deleteTask(t);
              _saved = true;
              Navigator.pop(context);
              showUndo(context, context.t('task_deleted'), () => _store.restoreTask(t.id, data));
            },
          ),
        if (!_isNew)
          IconButton(
            tooltip: context.t('m_focus'),
            icon: Icon(Icons.timer_outlined, color: tk.textMuted),
            onPressed: () {
              if (_dirty) _commit();
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => FocusScreen(task: widget.task)));
            },
          ),
        if (!_isNew)
          IconButton(
            tooltip: context.t('duplicate'),
            icon: Icon(Icons.copy_rounded, color: tk.textMuted, size: 20),
            onPressed: () {
              final c = _t.copy();
              final dup = Task.fromMap({...c.toMap(), 'id': ''})
                ..title = _title.text.trim()
                ..status = 'upcoming'
                ..createdAt = '';
              _store.saveTask(dup);
              showToast(context, context.t('duplicated'));
            },
          ),
        const Spacer(),
        if (_canEdit)
          FilledButton(
            onPressed: _save,
            child: Text(context.t(_isNew ? 'add_task' : 'save')),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String? emoji;
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback? onTap;
  const _Chip({required this.icon, required this.label, this.active = false, this.color, this.onTap, this.emoji});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final c = color ?? (active ? context.cs.primary : tk.textMuted);
    return Material(
      color: active ? tk.tint(c) : tk.subtle,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 14)) else Icon(icon, size: 17, color: c),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelMedium?.copyWith(color: active ? c : context.cs.onSurface)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "We understood: Tomorrow 5 PM · #work — Apply"
class _HintBar extends StatelessWidget {
  final Parsed parsed;
  final VoidCallback onApply;
  const _HintBar({required this.parsed, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final bits = <String>[
      if (parsed.date != null) context.dayTimeLabel(parsed.date!, hasTime: parsed.hasTime),
      if (parsed.repeat != 'none') repeatLabel(context, parsed.repeat),
      if (parsed.priority != 'none') prioLabel(context, parsed.priority),
      ...parsed.tags.map((t) => '#$t'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onApply,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: context.cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(bits.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.labelMedium?.copyWith(color: context.cs.primary)),
              ),
              Text(context.t('apply'), style: context.tt.labelLarge?.copyWith(color: context.cs.primary)),
            ]),
          ),
        ),
      ),
    );
  }
}

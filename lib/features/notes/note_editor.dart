import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/life_store.dart';
import '../../data/models.dart';
import '../../data/plan_store.dart';
import '../../ui/kit.dart';
import '../../widgets/attachment_picker.dart';
import '../../widgets/voice_note_recorder.dart';
import '../plan/reminder_editor.dart';
import '../plan/task_editor.dart';
import 'notes_screen.dart';

Future<void> openNoteEditor(BuildContext context, {Note? note, bool checklist = false}) {
  final notes = context.read<NotesStore>();
  final plan = context.read<PlanStore>();
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: plan),
      ],
      child: NoteEditorScreen(note: note, checklist: checklist),
    ),
  ));
}

/// Full-screen note editor. Saves automatically while you type.
class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final bool checklist;
  const NoteEditorScreen({super.key, this.note, this.checklist = false});
  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late Note _n;
  late final TextEditingController _title;
  late final TextEditingController _body;
  final List<TextEditingController> _items = [];
  final List<FocusNode> _itemFocus = [];
  late final NotesStore _store;
  Timer? _debounce;
  bool _dirty = false;
  bool _showChecked = true;

  @override
  void initState() {
    super.initState();
    _store = context.read<NotesStore>();
    _n = widget.note == null
        ? Note(isChecklist: widget.checklist)
        : Note.fromMap({...widget.note!.toMap(), 'id': widget.note!.id});
    _title = TextEditingController(text: _n.title)..addListener(_changed);
    _body = TextEditingController(text: _n.body)..addListener(_changed);
    if (_n.isChecklist && _n.checklist.isEmpty) _n.checklist.add(SubItem(''));
    _syncItemControllers();
  }

  void _syncItemControllers() {
    // Old controllers may still be attached to fields in this frame, so
    // they are disposed only after the rebuild.
    final oldC = List.of(_items);
    final oldF = List.of(_itemFocus);
    if (oldC.isNotEmpty || oldF.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in oldC) {
          c.dispose();
        }
        for (final f in oldF) {
          f.dispose();
        }
      });
    }
    _items.clear();
    _itemFocus.clear();
    for (final it in _n.checklist) {
      final c = TextEditingController(text: it.title);
      c.addListener(() {
        it.title = c.text;
        _changed();
      });
      _items.add(c);
      _itemFocus.add(FocusNode());
    }
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _save);
  }

  void _save() {
    if (!_dirty) return;
    _n.title = _title.text;
    _n.body = _body.text;
    if (_n.isEmpty) return;
    if (_n.id.isEmpty) {
      final id = _store.save(_n);
      // Keep the same SubItem objects: the checklist controllers write into them.
      final old = _n;
      _n = Note.fromMap({...old.toMap(), 'id': id})..checklist = old.checklist;
    } else {
      _store.save(_n);
    }
    _dirty = false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _title.dispose();
    _body.dispose();
    for (final c in _items) {
      c.dispose();
    }
    for (final f in _itemFocus) {
      f.dispose();
    }
    super.dispose();
  }

  void _toggleChecklist() {
    setState(() {
      if (_n.isChecklist) {
        _n.body = _n.checklist.where((c) => c.title.trim().isNotEmpty).map((c) => c.title).join('\n');
        _body.text = _n.body;
        _n.checklist = [];
        _n.isChecklist = false;
      } else {
        final lines = _body.text.split('\n').where((l) => l.trim().isNotEmpty).toList();
        _n.checklist = lines.isEmpty ? [SubItem('')] : lines.map((l) => SubItem(l.trim())).toList();
        _n.isChecklist = true;
        _body.text = '';
      }
      _syncItemControllers();
      _changed();
    });
  }

  void _addItem({int? after}) {
    setState(() {
      final i = after == null ? _n.checklist.length : after + 1;
      _n.checklist.insert(i, SubItem(''));
      _syncItemControllers();
      _changed();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = after == null ? _itemFocus.length - 1 : after + 1;
      if (i >= 0 && i < _itemFocus.length) _itemFocus[i].requestFocus();
    });
  }

  Future<void> _labels() async {
    final all = {..._store.labels, ..._n.labels}.toList()..sort();
    final selected = {..._n.labels};
    final c = TextEditingController();
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        void add() {
          final v = c.text.trim();
          if (v.isEmpty) return;
          set(() {
            if (!all.contains(v)) all.add(v);
            selected.add(v);
            c.clear();
          });
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetHeader(ctx.t('labels'), actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('done'))),
              ]),
              TextField(
                controller: c,
                decoration: InputDecoration(
                  hintText: ctx.t('new_label'),
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                  suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: add),
                ),
                onSubmitted: (_) => add(),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final l in all)
                  FilterChip(
                    label: Text(l),
                    selected: selected.contains(l),
                    onSelected: (v) => set(() => v ? selected.add(l) : selected.remove(l)),
                  ),
              ]),
            ]),
          ),
        );
      });
    });
    // Dispose after the sheet's exit animation, not while its field still uses it.
    WidgetsBinding.instance.addPostFrameCallback((_) => Future<void>.delayed(const Duration(milliseconds: 400), c.dispose));
    if (!mounted) return;
    setState(() => _n.labels = selected.toList());
    _changed();
  }

  Future<void> _more() async {
    final a = await showAppSheet<String>(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            OptionTile(icon: Icons.check_circle_outline_rounded, color: AppColors.mTasks, title: ctx.t('make_task'), onTap: () => Navigator.pop(ctx, 'task')),
            OptionTile(icon: Icons.notifications_active_outlined, color: AppColors.mReminders, title: ctx.t('make_reminder'), onTap: () => Navigator.pop(ctx, 'rem')),
            OptionTile(icon: Icons.share_outlined, title: ctx.t('share'), onTap: () => Navigator.pop(ctx, 'share')),
            OptionTile(icon: Icons.copy_rounded, title: ctx.t('duplicate'), onTap: () => Navigator.pop(ctx, 'dup')),
            OptionTile(icon: Icons.delete_outline_rounded, title: ctx.t('delete'), destructive: true, onTap: () => Navigator.pop(ctx, 'delete')),
          ]),
        ),
      );
    });
    if (a == null || !mounted) return;
    final text = _n.isChecklist
        ? _n.checklist.map((c) => '${c.done ? '☑' : '☐'} ${c.title}').join('\n')
        : _body.text;
    final headline = _title.text.trim().isNotEmpty ? _title.text.trim() : text.split('\n').first.trim();
    switch (a) {
      case 'task':
        await openTaskEditor(context, initialTitle: headline);
        break;
      case 'rem':
        await openReminderEditor(context, title: headline);
        break;
      case 'share':
        if ('${_title.text}\n$text'.trim().isNotEmpty) await Share.share('${_title.text}\n\n$text'.trim());
        break;
      case 'dup':
        _save();
        _store.save(Note.fromMap({..._n.toMap(), 'id': ''})..createdAt = '');
        if (mounted) showToast(context, context.t('duplicated'));
        break;
      case 'delete':
        _debounce?.cancel();
        _dirty = false;
        if (_n.id.isNotEmpty) {
          final data = _store.delete(_n);
          final id = _n.id;
          final store = _store;
          Navigator.pop(context);
          showUndo(context, context.t('note_deleted'), () => store.restore(id, data));
        } else {
          Navigator.pop(context);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final bg = NoteColors.of(context, _n.color);
    final unchecked = <int>[];
    final checked = <int>[];
    for (var i = 0; i < _n.checklist.length; i++) {
      (_n.checklist[i].done ? checked : unchecked).add(i);
    }
    return Scaffold(
      backgroundColor: _n.color == 0 ? tk.bg : bg,
      appBar: AppBar(
        backgroundColor: _n.color == 0 ? tk.bg : bg,
        actions: [
          IconButton(
            tooltip: context.t(_n.pinned ? 'unpin' : 'pin'),
            icon: Icon(_n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
            onPressed: () => setState(() {
              _n.pinned = !_n.pinned;
              _changed();
            }),
          ),
          IconButton(
            tooltip: context.t('labels'),
            icon: const Icon(Icons.label_outline_rounded),
            onPressed: _labels,
          ),
          IconButton(
            tooltip: context.t(_n.archived ? 'unarchive' : 'archive'),
            icon: Icon(_n.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            onPressed: () {
              setState(() => _n.archived = !_n.archived);
              _dirty = true;
              _save();
              Navigator.pop(context);
            },
          ),
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _more),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    style: context.tt.headlineSmall,
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: context.t('title'),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_n.isChecklist)
                    TextField(
                      controller: _body,
                      autofocus: widget.note == null && !widget.checklist,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      minLines: 8,
                      style: context.tt.bodyLarge?.copyWith(height: 1.5),
                      decoration: InputDecoration(
                        hintText: context.t('note_hint'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  else ...[
                    for (final i in unchecked) _itemRow(context, i),
                    TextButton.icon(
                      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.t('add_item')),
                    ),
                    if (checked.isNotEmpty) ...[
                      const Divider(),
                      InkWell(
                        onTap: () => setState(() => _showChecked = !_showChecked),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Icon(_showChecked ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: tk.textMuted),
                            const SizedBox(width: 6),
                            Text(context.tn('checked_items', checked.length), style: context.tt.labelMedium),
                          ]),
                        ),
                      ),
                      if (_showChecked) for (final i in checked) _itemRow(context, i),
                    ],
                  ],
                  const SizedBox(height: 16),
                  if (_n.labels.isNotEmpty)
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final l in _n.labels)
                        InputChip(
                          label: Text(l),
                          onDeleted: () => setState(() {
                            _n.labels.remove(l);
                            _changed();
                          }),
                        ),
                    ]),
                  const SizedBox(height: 12),
                  AttachmentPicker(
                    urls: _n.photos,
                    folder: 'notes',
                    label: context.t('photos'),
                    onChanged: (l) => setState(() {
                      _n.photos = l;
                      _changed();
                    }),
                  ),
                  const SizedBox(height: 8),
                  VoiceNoteRecorder(
                    urls: _n.voice,
                    onChanged: (l) => setState(() {
                      _n.voice = l;
                      _changed();
                    }),
                  ),
                ]),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: tk.border.withValues(alpha: 0.6)))),
            child: Row(children: [
              IconButton(
                tooltip: context.t(_n.isChecklist ? 'as_text' : 'as_checklist'),
                icon: Icon(_n.isChecklist ? Icons.notes_rounded : Icons.checklist_rounded),
                onPressed: _toggleChecklist,
              ),
              IconButton(
                tooltip: context.t('color'),
                icon: const Icon(Icons.palette_outlined),
                onPressed: () async {
                  final i = await showAppSheet<int>(context, builder: (ctx) {
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Wrap(spacing: 12, runSpacing: 12, children: [
                          for (var i = 0; i < NoteColors.light.length; i++)
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx, i),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: NoteColors.of(ctx, i),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: i == _n.color ? ctx.cs.primary : ctx.tokens.border, width: i == _n.color ? 3 : 1),
                                ),
                                child: i == 0 ? Icon(Icons.format_color_reset_outlined, size: 18, color: ctx.tokens.textMuted) : null,
                              ),
                            ),
                        ]),
                      ),
                    );
                  });
                  if (i != null && mounted) {
                    setState(() => _n.color = i);
                    _changed();
                  }
                },
              ),
              const Spacer(),
              Text(
                _n.updatedAt.isEmpty
                    ? context.t('new_note')
                    : context.tr('edited_x', {'x': context.relative(DateTime.tryParse(_n.updatedAt) ?? DateTime.now())}),
                style: context.tt.bodySmall,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _itemRow(BuildContext context, int i) {
    final it = _n.checklist[i];
    final tk = context.tokens;
    return Row(children: [
      Checkbox(
        value: it.done,
        onChanged: (v) => setState(() {
          it.done = v ?? false;
          _changed();
        }),
      ),
      Expanded(
        child: TextField(
          controller: _items[i],
          focusNode: _itemFocus[i],
          textCapitalization: TextCapitalization.sentences,
          style: context.tt.bodyLarge?.copyWith(
            decoration: it.done ? TextDecoration.lineThrough : null,
            color: it.done ? tk.textFaint : null,
          ),
          decoration: InputDecoration(
            hintText: context.t('list_item'),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
          ),
          onSubmitted: (_) => _addItem(after: i),
        ),
      ),
      IconButton(
        icon: Icon(Icons.close_rounded, size: 18, color: tk.textFaint),
        onPressed: () => setState(() {
          _n.checklist.removeAt(i);
          _syncItemControllers();
          _changed();
        }),
      ),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import '../services/notification_service.dart';
import '../services/vault_service.dart';
import '../ui/kit.dart';

/// Document types, as stored. The stored value never changes — only the label
/// shown next to it is translated, so old records keep working.
const List<String> kVaultDocTypes = [
  'Aadhaar',
  'PAN',
  'Passport',
  'Driving Licence',
  'Voter ID',
  'College ID',
  'Insurance',
  'Certificate',
  'Other',
];

/// Translated name for a stored document type.
String vaultTypeLabel(BuildContext context, String stored) => switch (stored) {
      'Aadhaar' => context.t('vt_t_aadhaar'),
      'PAN' => context.t('vt_t_pan'),
      'Passport' => context.t('vt_t_passport'),
      'Driving Licence' => context.t('vt_t_licence'),
      'Voter ID' => context.t('vt_t_voter'),
      'College ID' => context.t('vt_t_college'),
      'Insurance' => context.t('vt_t_insurance'),
      'Certificate' => context.t('vt_t_certificate'),
      _ => context.t('vt_t_other'),
    };

String _str(Object? v) => (v ?? '').toString();

/// Sheet controllers outlive the exit animation, so they are disposed after it
/// finishes rather than on the next frame.
void _disposeLater(List<TextEditingController> cs) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in cs) {
        c.dispose();
      }
    });
  });
}

/// 'yyyy-MM-dd' for storage — the shape the vault has always written.
String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The encrypted vault: documents and passwords, kept on this device only and
/// never synced. Unlocked with the device's own biometrics or PIN.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _vault = VaultService.instance;
  bool _unlocked = false;
  bool _checking = true;
  bool _biometrics = false;
  bool _loading = false;
  int _tab = 0; // 0 documents, 1 passwords
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _pwds = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final available = await _vault.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometrics = available;
      _checking = false;
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final docs = await _vault.documents();
    final pwds = await _vault.passwords();
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _pwds = pwds;
      _loading = false;
    });
  }

  Future<void> _attemptUnlock() async {
    final ok = await _vault.unlock();
    if (!mounted) return;
    if (!ok) {
      showToast(context, context.t('vt_unlock_cancelled'), icon: Icons.lock_outline_rounded);
      return;
    }
    setState(() => _unlocked = true);
    await _load();
    // Shown once, before any data exists — Android provides no hook that runs
    // at uninstall time, so this is the only honest moment to warn.
    final seen = await _vault.warningAcknowledged();
    if (!seen && mounted) await _showSafetyNote(acknowledge: true);
  }

  void _lock() {
    setState(() {
      _unlocked = false;
      _docs = [];
      _pwds = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_vault.supported) return _unavailablePage(context);
    if (_checking) {
      return AppPage(
        title: context.t('m_vault'),
        slivers: const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 90),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      );
    }
    if (!_unlocked) return _lockedPage(context);
    return _vaultPage(context);
  }

  // ---------------------------------------------------------------- states

  Widget _unavailablePage(BuildContext context) {
    return AppPage(
      title: context.t('m_vault'),
      slivers: [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.phonelink_lock_outlined,
            color: AppColors.mVault,
            title: context.t('vt_mobile_only'),
            message: context.t('vt_mobile_only_msg'),
          ),
        ),
      ],
    );
  }

  /// Calm, plain locked state: one badge, one sentence, one button.
  Widget _lockedPage(BuildContext context) {
    final tk = context.tokens;
    return AppPage(
      title: context.t('m_vault'),
      subtitle: context.t('vt_sub'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Column(children: [
              IconBadge(
                icon: _biometrics ? Icons.lock_rounded : Icons.lock_person_outlined,
                color: AppColors.mVault,
                size: 84,
                radius: 28,
              ),
              const SizedBox(height: 18),
              Text(
                context.t(_biometrics ? 'vt_locked' : 'vt_no_lock'),
                textAlign: TextAlign.center,
                style: context.tt.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.t(_biometrics ? 'vt_locked_msg' : 'vt_no_lock_msg'),
                textAlign: TextAlign.center,
                style: context.tt.bodyMedium?.copyWith(color: tk.textMuted),
              ),
              const SizedBox(height: 22),
              if (_biometrics)
                FilledButton.icon(
                  onPressed: _attemptUnlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(context.t('unlock')),
                ),
              const SizedBox(height: 26),
              _OnDeviceNote(onTap: () => _showSafetyNote()),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _vaultPage(BuildContext context) {
    final docs = _tab == 0;
    return AppPage(
      title: context.t('m_vault'),
      subtitle: context.t('vt_sub'),
      actions: [
        IconButton(
          tooltip: context.t('vt_lock_now'),
          icon: const Icon(Icons.lock_outline_rounded),
          onPressed: _lock,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            if (v == 'backup') _backup();
            if (v == 'restore') _restore();
            if (v == 'safety') _showSafetyNote();
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'backup', child: Text(ctx.t('vt_backup'))),
            PopupMenuItem(value: 'restore', child: Text(ctx.t('vt_restore'))),
            PopupMenuItem(value: 'safety', child: Text(ctx.t('vt_safety'))),
          ],
        ),
      ],
      header: Column(children: [
        _OnDeviceNote(onTap: () => _showSafetyNote()),
        const SizedBox(height: 10),
        PillTabs<int>(
          items: [
            (0, context.t('vt_tab_docs')),
            (1, context.t('vt_tab_passwords')),
          ],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ]),
      fab: FloatingActionButton.extended(
        onPressed: () => docs ? _docEditor() : _pwdEditor(),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t(docs ? 'vt_add_doc' : 'vt_add_pwd')),
      ),
      slivers: _loading
          ? const [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ]
          : (docs ? _docSlivers(context) : _pwdSlivers(context)),
    );
  }

  // ------------------------------------------------------------- documents

  List<Widget> _docSlivers(BuildContext context) {
    if (_docs.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.badge_outlined,
            color: AppColors.mVault,
            title: context.t('vt_no_docs'),
            message: context.t('vt_no_docs_msg'),
            actionLabel: context.t('vt_add_doc'),
            onAction: () => _docEditor(),
          ),
        ),
      ];
    }
    return [
      SliverList.list(
        children: [
          const SizedBox(height: 6),
          for (final d in _docs)
            _VaultCard(
              key: ValueKey('doc_${_str(d['id'])}'),
              icon: Icons.badge_outlined,
              title: _str(d['name']),
              meta: [
                if (_str(d['type']).isNotEmpty)
                  (Icons.category_outlined, vaultTypeLabel(context, _str(d['type'])), false),
                if (DateTime.tryParse(_str(d['expiry'])) != null)
                  (
                    Icons.event_outlined,
                    context.tr('vt_expires_on',
                        {'d': context.fmtDate(DateTime.parse(_str(d['expiry'])), 'd MMM yyyy')}),
                    _expiringSoon(_str(d['expiry'])),
                  ),
              ],
              badge: _expiringSoon(_str(d['expiry'])) ? context.t('vt_expiring_soon') : null,
              secretLabel: context.t('vt_doc_number'),
              secret: _str(d['number']),
              notes: _str(d['notes']),
              onEdit: () => _docEditor(existing: d),
              onDelete: () => _deleteDoc(d),
            ),
        ],
      ),
    ];
  }

  static bool _expiringSoon(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return false;
    return d.difference(DateTime.now()).inDays < 60;
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final ok = await confirmDialog(
      context,
      title: context.t('vt_delete_q'),
      message: context.t('vt_delete_msg'),
      confirm: context.t('delete'),
      danger: true,
    );
    if (!ok || !mounted) return;
    final id = _str(doc['id']);
    await NotificationService.instance.cancel('doc_$id');
    await _vault.deleteDocument(id);
    if (!mounted) return;
    showToast(context, context.t('vt_deleted'), icon: Icons.lock_rounded);
    await _load();
  }

  Future<void> _docEditor({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: _str(existing?['name']));
    final number = TextEditingController(text: _str(existing?['number']));
    final notes = TextEditingController(text: _str(existing?['notes']));
    // An unrecognised stored type must still open — the dropdown asserts if its
    // value is not one of the items.
    final stored = _str(existing?['type']);
    var type = kVaultDocTypes.contains(stored) ? stored : 'Other';
    DateTime? expiry = DateTime.tryParse(_str(existing?['expiry']));

    final expiringTitle = context.t('vt_expiring_notif');

    await showAppSheet<void>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  ctx.t(existing == null ? 'vt_add_doc' : 'vt_edit_doc'),
                  subtitle: ctx.t('vt_on_device'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: name,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ctx.t('vt_doc_label')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: ctx.t('vt_doc_type')),
                  items: [
                    for (final t in kVaultDocTypes)
                      DropdownMenuItem(
                        value: t,
                        child: Text(vaultTypeLabel(ctx, t),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => set(() => type = v ?? 'Other'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: number,
                  decoration: InputDecoration(labelText: ctx.t('vt_doc_number')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: ctx.t('vt_notes_opt')),
                ),
                const SizedBox(height: 12),
                FormFieldButton(
                  icon: Icons.event_outlined,
                  label: ctx.t('vt_expiry'),
                  value: expiry == null ? ctx.t('none') : ctx.fmtDate(expiry!, 'd MMM yyyy'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: expiry ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) set(() => expiry = picked);
                  },
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty) {
                      showToast(ctx, ctx.t('vt_need_label'));
                      return;
                    }
                    final label = name.text.trim();
                    final body = ctx.tr('vt_expiring_body', {'x': label});
                    final when = expiry;
                    final doc = <String, dynamic>{
                      'id': existing?['id'],
                      'name': label,
                      'type': type,
                      'number': number.text.trim(),
                      'notes': notes.text.trim(),
                      'expiry': when == null ? '' : _isoDate(when),
                    };
                    await _vault.saveDocument(doc);
                    // Remind 30 days before expiry. The notification text
                    // deliberately carries no document number.
                    final id = _str(doc['id']);
                    await NotificationService.instance.cancel('doc_$id');
                    if (when != null) {
                      await NotificationService.instance.scheduleAt(
                        key: 'doc_$id',
                        title: expiringTitle,
                        body: body,
                        when: when.subtract(const Duration(days: 30)),
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                  child: Text(ctx.t('save')),
                ),
              ],
            ),
          ),
        );
      });
    });
    _disposeLater([name, number, notes]);
  }

  // ------------------------------------------------------------- passwords

  List<Widget> _pwdSlivers(BuildContext context) {
    if (_pwds.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyView(
            icon: Icons.key_outlined,
            color: AppColors.mVault,
            title: context.t('vt_no_pwd'),
            message: context.t('vt_no_pwd_msg'),
            actionLabel: context.t('vt_add_pwd'),
            onAction: () => _pwdEditor(),
          ),
        ),
      ];
    }
    return [
      SliverList.list(
        children: [
          const SizedBox(height: 6),
          for (final e in _pwds)
            _VaultCard(
              key: ValueKey('pwd_${_str(e['id'])}'),
              icon: Icons.key_outlined,
              title: _str(e['label']),
              meta: [
                if (_str(e['username']).isNotEmpty)
                  (Icons.person_outline_rounded, _str(e['username']), false),
              ],
              secretLabel: context.t('password'),
              secret: _str(e['secret']),
              notes: _str(e['notes']),
              onEdit: () => _pwdEditor(existing: e),
              onDelete: () => _deletePwd(e),
            ),
        ],
      ),
    ];
  }

  Future<void> _deletePwd(Map<String, dynamic> entry) async {
    final ok = await confirmDialog(
      context,
      title: context.t('vt_delete_q'),
      message: context.t('vt_delete_msg'),
      confirm: context.t('delete'),
      danger: true,
    );
    if (!ok || !mounted) return;
    await _vault.deletePassword(_str(entry['id']));
    if (!mounted) return;
    showToast(context, context.t('vt_deleted'), icon: Icons.lock_rounded);
    await _load();
  }

  Future<void> _pwdEditor({Map<String, dynamic>? existing}) async {
    final label = TextEditingController(text: _str(existing?['label']));
    final user = TextEditingController(text: _str(existing?['username']));
    final secret = TextEditingController(text: _str(existing?['secret']));
    final notes = TextEditingController(text: _str(existing?['notes']));
    var hidden = true;

    await showAppSheet<void>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  ctx.t(existing == null ? 'vt_add_pwd' : 'vt_edit_pwd'),
                  subtitle: ctx.t('vt_on_device'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: label,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ctx.t('vt_pwd_label')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: user,
                  decoration: InputDecoration(labelText: ctx.t('vt_username_opt')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: secret,
                  obscureText: hidden,
                  decoration: InputDecoration(
                    labelText: ctx.t('vt_secret'),
                    suffixIcon: IconButton(
                      tooltip: ctx.t(hidden ? 'show' : 'hide'),
                      icon: Icon(hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded),
                      onPressed: () => set(() => hidden = !hidden),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: ctx.t('vt_notes_opt')),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    if (label.text.trim().isEmpty) {
                      showToast(ctx, ctx.t('vt_need_label'));
                      return;
                    }
                    await _vault.savePassword({
                      'id': existing?['id'],
                      'label': label.text.trim(),
                      'username': user.text.trim(),
                      'secret': secret.text,
                      'notes': notes.text.trim(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                  child: Text(ctx.t('save')),
                ),
              ],
            ),
          ),
        );
      });
    });
    _disposeLater([label, user, secret, notes]);
  }

  // -------------------------------------------------------- safety, backup

  /// Android exposes no uninstall callback, so the warning is shown on first
  /// unlock — before anything is stored — and stays reachable afterwards.
  Future<void> _showSafetyNote({bool acknowledge = false}) async {
    // On first unlock the sheet can only be left through the button, so the
    // warning is not swiped past before anything is stored.
    await showAppSheet<void>(context, dismissible: !acknowledge, builder: (ctx) {
      final tk = ctx.tokens;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(ctx.t('vt_warn_title'), subtitle: ctx.t('vt_sub')),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const IconBadge(icon: Icons.shield_outlined, color: AppColors.mVault, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(ctx.t('vt_warn_intro'), style: ctx.tt.bodyMedium),
                ),
              ]),
              const SizedBox(height: 18),
              SectionTitle(ctx.t('vt_warn_cost'), padding: const EdgeInsets.fromLTRB(0, 0, 0, 8)),
              for (final line in [
                ctx.t('vt_warn_p1'),
                ctx.t('vt_warn_p2'),
                ctx.t('vt_warn_p3'),
                ctx.t('vt_warn_p4'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.remove_rounded, size: 15, color: tk.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(line, style: ctx.tt.bodyMedium)),
                  ]),
                ),
              const SizedBox(height: 12),
              DhCard(
                color: tk.tint(tk.warning),
                borderColor: Colors.transparent,
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: tk.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(ctx.t('vt_warn_outro'),
                        style: ctx.tt.bodySmall?.copyWith(color: ctx.cs.onSurface)),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  if (acknowledge) await _vault.acknowledgeWarning();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(ctx.t(acknowledge ? 'vt_understood' : 'done')),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Produces a plaintext JSON backup via the share sheet.
  Future<void> _backup() async {
    final proceed = await confirmDialog(
      context,
      title: context.t('vt_backup'),
      message: context.t('vt_backup_msg'),
      confirm: context.t('continue'),
    );
    if (!proceed || !mounted) return;

    // Re-authenticate: exporting secrets is exactly when to ask again.
    final ok = await _vault.unlock();
    if (!ok || !mounted) return;

    final subject = context.t('vt_backup_subject');
    final json = await _vault.exportJson();
    if (!mounted) return;
    await Share.share(json, subject: subject);
  }

  Future<void> _restore() async {
    final paste = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('vt_restore')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ctx.t('vt_restore_msg'), style: ctx.tt.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: paste,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(hintText: ctx.t('vt_paste_hint')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, paste.text), child: Text(ctx.t('restore'))),
        ],
      ),
    );
    _disposeLater([paste]);
    if (raw == null || raw.trim().isEmpty || !mounted) return;

    try {
      final count = await _vault.importJson(raw);
      if (!mounted) return;
      showToast(context, context.tn('vt_restored', count), icon: Icons.check_rounded);
      await _load();
    } catch (_) {
      if (!mounted) return;
      showToast(context, context.t('vt_restore_failed'), icon: Icons.error_outline_rounded);
    }
  }
}

/// The promise, stated on screen rather than buried in a menu.
class _OnDeviceNote extends StatelessWidget {
  final VoidCallback onTap;
  const _OnDeviceNote({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return DhCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      color: tk.tint(AppColors.mVault),
      borderColor: Colors.transparent,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.phonelink_lock_outlined, size: 20, color: AppColors.mVault),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('vt_on_device'), style: context.tt.titleSmall),
            const SizedBox(height: 3),
            Text(context.t('vt_on_device_msg'),
                style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
          ]),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, size: 18, color: tk.textFaint),
      ]),
    );
  }
}

/// One vault entry: a title, a little metadata, and the secret itself kept
/// masked until the eye is tapped.
class _VaultCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<(IconData, String, bool)> meta;
  final String? badge;
  final String secretLabel;
  final String secret;
  final String notes;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VaultCard({
    super.key,
    required this.icon,
    required this.title,
    required this.meta,
    this.badge,
    required this.secretLabel,
    required this.secret,
    required this.notes,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      onTap: onEdit,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(icon: icon, color: AppColors.mVault, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    title.isEmpty ? context.t('nothing_here') : title,
                    style: context.tt.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Pill(badge!, color: tk.warning),
                ],
              ]),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Wrap(spacing: 10, runSpacing: 2, children: [
                  for (final m in meta) MetaChip(m.$1, m.$2, color: m.$3 ? tk.warning : null),
                ]),
              ],
            ]),
          ),
          IconButton(
            tooltip: context.t('more_options'),
            icon: Icon(Icons.more_horiz_rounded, color: tk.textMuted),
            onPressed: () => _menu(context),
          ),
        ]),
        if (secret.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _SecretRow(label: secretLabel, value: secret),
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(notes,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
          ),
        ],
      ]),
    );
  }

  void _menu(BuildContext context) {
    showAppSheet<void>(context, builder: (ctx) {
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(title.isEmpty ? ctx.t('m_vault') : title),
          OptionTile(
            icon: Icons.edit_outlined,
            title: ctx.t('edit'),
            onTap: () {
              Navigator.pop(ctx);
              onEdit();
            },
          ),
          OptionTile(
            icon: Icons.delete_outline_rounded,
            title: ctx.t('delete'),
            destructive: true,
            onTap: () {
              Navigator.pop(ctx);
              onDelete();
            },
          ),
          const SizedBox(height: 8),
        ]),
      );
    });
  }
}

/// A secret that stays masked until asked for, and copies in a single tap.
class _SecretRow extends StatefulWidget {
  final String label;
  final String value;
  const _SecretRow({required this.label, required this.value});

  @override
  State<_SecretRow> createState() => _SecretRowState();
}

class _SecretRowState extends State<_SecretRow> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    // `String * n` needs an int; num.clamp returns num.
    final masked = '•' * widget.value.length.clamp(4, 16).toInt();
    return Material(
      color: tk.subtle,
      borderRadius: BorderRadius.circular(Radii.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.value));
          HapticFeedback.selectionClick();
          showToast(context, context.tr('vt_copied', {'x': widget.label}),
              icon: Icons.content_copy_rounded);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.bodySmall?.copyWith(fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.content_copy_rounded, size: 11, color: tk.textFaint),
                ]),
                const SizedBox(height: 2),
                Text(
                  _shown ? widget.value : masked,
                  maxLines: _shown ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.titleSmall?.copyWith(
                    fontSize: 15.5,
                    letterSpacing: _shown ? 0.3 : 2.4,
                    color: _shown ? context.cs.onSurface : tk.textMuted,
                  ),
                ),
              ]),
            ),
            IconButton(
              tooltip: context.t(_shown ? 'hide' : 'show'),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _shown ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 20,
                color: tk.textMuted,
              ),
              onPressed: () => setState(() => _shown = !_shown),
            ),
          ]),
        ),
      ),
    );
  }
}

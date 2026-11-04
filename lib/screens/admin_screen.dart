import 'package:flutter/material.dart';

import '../core/admin_config.dart';
import '../core/format.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services/admin_service.dart';
import '../ui/kit.dart';

/// The collections the admin tools know about: (db key, label key, icon, colour).
const List<(String, String, IconData, Color)> _kCollections = [
  ('todos', 'm_tasks', Icons.check_circle_outline_rounded, AppColors.mTasks),
  ('trips', 'm_trips', Icons.flight_rounded, AppColors.mTrips),
  ('notes', 'm_notes', Icons.sticky_note_2_outlined, AppColors.mNotes),
  ('reminders', 'm_reminders', Icons.alarm_rounded, AppColors.mReminders),
  ('txns', 'm_money', Icons.account_balance_wallet_outlined, AppColors.mMoney),
  ('goals', 'm_goals', Icons.flag_rounded, AppColors.mGoals),
  ('habits', 'm_habits', Icons.local_fire_department_rounded, AppColors.mHabits),
  ('journal', 'm_journal', Icons.auto_stories_rounded, AppColors.mJournal),
  ('bookmarks', 'm_bookmarks', Icons.bookmark_rounded, AppColors.mBookmarks),
];

/// Label for a raw collection key, falling back to the key itself.
String _collectionLabel(BuildContext context, String key) {
  for (final c in _kCollections) {
    if (c.$1 == key) return context.t(c.$2);
  }
  return key;
}

/// Tabs. Fixed ids so hiding the superadmin tab never shifts the others.
class _Tab {
  static const int overview = 0, users = 1, admins = 2, broadcast = 3, audit = 4;
}

/// Superadmin master dashboard: aggregate stats, user management, content
/// inspection, broadcast, and the audit log of admin actions.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _admin = AdminService.instance;
  final _search = TextEditingController();
  final _bTitle = TextEditingController();
  final _bMessage = TextEditingController();

  late final bool _isSuper;
  int _tab = _Tab.overview;
  Map<String, int>? _stats;
  List<Map<String, dynamic>>? _users;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _isSuper = _admin.isSuperAdmin;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _bTitle.dispose();
    _bMessage.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Also called after awaited admin actions; the screen may be gone by then.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final users = await _admin.listUsers();
      final stats = await _admin.stats();
      if (!mounted) return;
      setState(() {
        _users = users;
        _stats = stats;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _nameOf(BuildContext context, Map<String, dynamic> u) {
    final n = str(u['name']).trim();
    return n.isEmpty ? context.t('someone') : n;
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: context.t('m_admin'),
      subtitle: context.t('md_admin'),
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: context.t('refresh'),
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChipRow<int>(
          items: [
            (_Tab.overview, context.t('adm_overview')),
            (_Tab.users, context.t('adm_users')),
            if (_isSuper) (_Tab.admins, context.t('adm_admins')),
            (_Tab.broadcast, context.t('adm_broadcast')),
            (_Tab.audit, context.t('adm_audit')),
          ],
          value: _tab,
          onSelected: (v) => setState(() => _tab = v),
        ),
      ),
      slivers: _slivers(context),
    );
  }

  List<Widget> _slivers(BuildContext context) {
    // Broadcast and the audit log come straight from their own streams, so
    // they still work even when the user list could not be read.
    if (_tab == _Tab.broadcast) return _broadcast(context);
    if (_tab == _Tab.audit) return _auditLog(context);
    if (_loading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 70),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_failed) {
      return [
        SliverToBoxAdapter(
          child: Column(children: [
            EmptyView(
              icon: Icons.lock_outline_rounded,
              color: AppColors.mEmergency,
              title: context.t('adm_denied'),
              message: context.t('adm_denied_msg'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.t('retry')),
              onPressed: _load,
            ),
          ]),
        ),
      ];
    }
    return switch (_tab) {
      _Tab.users => _userList(context),
      _Tab.admins => _adminManager(context),
      _ => _overview(context),
    };
  }

  // ------------------------------------------------------------- overview

  List<Widget> _overview(BuildContext context) {
    final s = _stats ?? const <String, int>{};
    final users = _users ?? const <Map<String, dynamic>>[];
    final disabled = users.where((u) => u['disabled'] == true).length;
    var total = 0;
    var biggest = 0;
    for (final c in _kCollections) {
      final n = s[c.$1] ?? 0;
      total += n;
      if (n > biggest) biggest = n;
    }
    return [
      SliverToBoxAdapter(
        child: DhCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: StatBlock(
                label: context.t('adm_users'),
                value: '${s['users'] ?? users.length}',
                color: AppColors.mEmergency,
              ),
            ),
            Expanded(
              child: StatBlock(
                label: context.t('adm_items'),
                value: '$total',
                color: context.cs.primary,
              ),
            ),
            Expanded(
              child: StatBlock(
                label: context.t('adm_disabled'),
                value: '$disabled',
                color: disabled > 0 ? context.tokens.danger : context.tokens.textMuted,
              ),
            ),
          ]),
        ),
      ),
      SliverToBoxAdapter(child: SectionTitle(context.t('adm_by_feature'))),
      SliverList.list(
        children: [
          for (final c in _kCollections)
            DhCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                IconBadge(icon: c.$3, color: c.$4, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t(c.$2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.titleSmall),
                    const SizedBox(height: 6),
                    ProgressBar(
                      value: biggest == 0 ? 0.0 : (s[c.$1] ?? 0) / biggest,
                      color: c.$4,
                      height: 6,
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Text('${s[c.$1] ?? 0}', style: context.tt.labelLarge),
              ]),
            ),
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------- users

  List<Widget> _userList(BuildContext context) {
    final all = _users ?? const <Map<String, dynamic>>[];
    final q = _search.text.trim().toLowerCase();
    int itemsOf(Map<String, dynamic> u) =>
        _kCollections.fold<int>(0, (n, c) => n + toI(u['count_${c.$1}']));

    final users = all.where((u) {
      if (q.isEmpty) return true;
      return str(u['name']).toLowerCase().contains(q) ||
          str(u['uid']).toLowerCase().contains(q) ||
          str(u['phone']).toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final offA = a['disabled'] == true ? 1 : 0;
        final offB = b['disabled'] == true ? 1 : 0;
        if (offA != offB) return offA - offB;
        return itemsOf(b).compareTo(itemsOf(a));
      });

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.t('adm_search_users'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
      ),
      if (users.isEmpty)
        SliverToBoxAdapter(
          child: EmptyView(
            compact: true,
            icon: Icons.people_outline_rounded,
            color: AppColors.mEmergency,
            title: context.t(q.isEmpty ? 'adm_no_users' : 'no_results'),
            message: q.isEmpty ? null : context.tr('no_results_for', {'q': q}),
          ),
        )
      else
        SliverList.list(
          children: [
            for (final u in users) _userRow(context, u, itemsOf(u)),
          ],
        ),
    ];
  }

  Widget _userRow(BuildContext context, Map<String, dynamic> u, int items) {
    final tk = context.tokens;
    final disabled = u['disabled'] == true;
    final name = _nameOf(context, u);
    final created = parseDay(str(u['createdAt']));
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      onTap: () => _openUser(u),
      child: Row(children: [
        InitialsAvatar(name, size: 42, color: disabled ? tk.textMuted : null),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.titleSmall?.copyWith(
                        color: disabled ? tk.textMuted : null)),
              ),
              if (disabled) ...[
                const SizedBox(width: 6),
                Pill(context.t('adm_disabled'), color: tk.danger, icon: Icons.block_rounded),
              ],
            ]),
            const SizedBox(height: 3),
            Wrap(spacing: 10, runSpacing: 2, children: [
              MetaChip(Icons.inventory_2_outlined, context.tn('adm_n_items', items)),
              if (created != null)
                MetaChip(Icons.event_outlined, context.fmtDate(created, 'd MMM yyyy')),
            ]),
            const SizedBox(height: 2),
            Text(str(u['uid']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodySmall?.copyWith(color: tk.textFaint, fontSize: 11)),
          ]),
        ),
        PopupMenuButton<String>(
          tooltip: context.t('more_options'),
          icon: Icon(Icons.more_vert_rounded, color: tk.textMuted),
          onSelected: (v) => _userAction(v, u),
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'view', child: Text(ctx.t('adm_view_content'))),
            PopupMenuItem(
                value: 'toggle',
                child: Text(ctx.t(disabled ? 'adm_enable' : 'adm_disable'))),
            PopupMenuItem(
              value: 'delete',
              child: Text(ctx.t('adm_delete_data'),
                  style: TextStyle(color: ctx.tokens.danger)),
            ),
          ],
        ),
      ]),
    );
  }

  void _openUser(Map<String, dynamic> u) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _UserContentScreen(uid: str(u['uid']), name: _nameOf(context, u)),
      ),
    );
  }

  Future<void> _userAction(String action, Map<String, dynamic> u) async {
    final uid = str(u['uid']);
    final name = _nameOf(context, u);
    final disabled = u['disabled'] == true;

    if (action == 'view') {
      _openUser(u);
      return;
    }

    if (action == 'toggle') {
      if (!disabled) {
        final ok = await confirmDialog(
          context,
          title: context.tr('adm_disable_q', {'name': name}),
          message: context.t('adm_disable_msg'),
          confirm: context.t('adm_disable'),
          danger: true,
        );
        if (!ok || !mounted) return;
      }
      await _admin.setDisabled(uid, !disabled);
      if (!mounted) return;
      showToast(context, context.t(disabled ? 'adm_account_enabled' : 'account_disabled'));
      await _load();
      return;
    }

    if (action == 'delete') {
      final ok = await confirmDialog(
        context,
        title: context.tr('adm_delete_q', {'name': name}),
        message: context.t('adm_delete_msg'),
        confirm: context.t('delete'),
        danger: true,
      );
      if (!ok || !mounted) return;
      await _admin.deleteUserData(uid);
      if (!mounted) return;
      showToast(context, context.tr('adm_deleted', {'name': name}));
      await _load();
    }
  }

  // --------------------------------------------------------------- admins

  /// Superadmin-only: grant or revoke admin rights.
  List<Widget> _adminManager(BuildContext context) {
    final tk = context.tokens;
    final users = _users ?? const <Map<String, dynamic>>[];
    return [
      SliverToBoxAdapter(
        child: DhCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const IconBadge(icon: Icons.verified_user_rounded, color: AppColors.mEmergency, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('adm_superadmin'), style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Text(AdminConfig.superAdminEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.labelMedium),
                const SizedBox(height: 6),
                Text(context.t('adm_superadmin_msg'), style: context.tt.bodySmall),
              ]),
            ),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: StreamBuilder<Set<String>>(
          stream: _admin.adminUidsStream(),
          builder: (context, snap) {
            final adminUids = snap.data ?? <String>{};
            if (users.isEmpty) {
              return EmptyView(
                compact: true,
                icon: Icons.people_outline_rounded,
                color: AppColors.mEmergency,
                title: context.t('adm_no_users'),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionTitle(context.tn('adm_n_admins', adminUids.length)),
              for (final u in users)
                Builder(builder: (context) {
                  final uid = str(u['uid']);
                  final isAdmin = adminUids.contains(uid);
                  final name = _nameOf(context, u);
                  return DhCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    child: Row(children: [
                      InitialsAvatar(name,
                          size: 40, color: isAdmin ? AppColors.mEmergency : null),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tt.titleSmall),
                          Text(uid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tt.bodySmall
                                  ?.copyWith(color: tk.textFaint, fontSize: 11)),
                        ]),
                      ),
                      Switch(
                        value: isAdmin,
                        onChanged: (v) => _setAdmin(uid, name, v),
                      ),
                    ]),
                  );
                }),
            ]);
          },
        ),
      ),
    ];
  }

  Future<void> _setAdmin(String uid, String name, bool grant) async {
    final ok = await confirmDialog(
      context,
      title: context.tr(grant ? 'adm_grant_q' : 'adm_revoke_q', {'name': name}),
      message: context.t(grant ? 'adm_grant_msg' : 'adm_revoke_msg'),
      confirm: context.t(grant ? 'adm_grant' : 'adm_revoke'),
      danger: !grant,
    );
    if (!ok || !mounted) return;
    try {
      await _admin.setAdmin(uid, grant);
      if (!mounted) return;
      showToast(context, context.t(grant ? 'adm_granted' : 'adm_revoked'));
    } catch (_) {
      if (mounted) showToast(context, context.t('adm_grant_failed'));
    }
  }

  // ------------------------------------------------------------ broadcast

  List<Widget> _broadcast(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: _admin.broadcastStream(),
          builder: (context, snap) {
            final b = snap.data;
            if (b == null) return const SizedBox.shrink();
            final at = DateTime.tryParse(str(b['at']));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionTitle(context.t('adm_live_announcement')),
              DhCard(
                borderColor: context.cs.primary,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    IconBadge(icon: Icons.campaign_rounded, color: context.cs.primary, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(str(b['title']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.titleSmall),
                    ),
                  ]),
                  if (str(b['message']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(str(b['message']), style: context.tt.bodyMedium),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    if (at != null) MetaChip(Icons.schedule_rounded, context.relative(at)),
                    if (str(b['by']).isNotEmpty)
                      MetaChip(Icons.person_outline_rounded, str(b['by'])),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: context.tokens.danger),
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: Text(context.t('adm_clear')),
                    onPressed: _clearBroadcast,
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
      SliverToBoxAdapter(child: SectionTitle(context.t('adm_broadcast_title'))),
      SliverToBoxAdapter(
        child: DhCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t('adm_broadcast_sub'), style: context.tt.bodySmall),
            const SizedBox(height: 14),
            TextField(
              controller: _bTitle,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t('title'),
                prefixIcon: const Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bMessage,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: context.t('adm_message')),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(context.t('adm_send_all')),
              onPressed: _sendBroadcast,
            ),
          ]),
        ),
      ),
    ];
  }

  Future<void> _sendBroadcast() async {
    final title = _bTitle.text.trim();
    if (title.isEmpty) {
      showToast(context, context.t('adm_enter_title'));
      return;
    }
    final ok = await confirmDialog(
      context,
      title: context.t('adm_send_q'),
      message: context.t('adm_send_msg'),
      confirm: context.t('adm_send_all'),
    );
    if (!ok || !mounted) return;
    await _admin.broadcast(title, _bMessage.text.trim());
    if (!mounted) return;
    _bTitle.clear();
    _bMessage.clear();
    FocusScope.of(context).unfocus();
    showToast(context, context.t('adm_sent'), icon: Icons.campaign_rounded);
  }

  Future<void> _clearBroadcast() async {
    final ok = await confirmDialog(
      context,
      title: context.t('adm_clear_q'),
      message: context.t('adm_clear_msg'),
      confirm: context.t('adm_clear'),
      danger: true,
    );
    if (!ok || !mounted) return;
    await _admin.clearBroadcast();
    if (!mounted) return;
    showToast(context, context.t('adm_cleared'));
  }

  // ------------------------------------------------------------ audit log

  List<Widget> _auditLog(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _admin.auditStream(),
          builder: (context, snap) {
            final logs = snap.data;
            if (logs == null) {
              return const Padding(
                padding: EdgeInsets.only(top: 70),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (logs.isEmpty) {
              return EmptyView(
                icon: Icons.receipt_long_rounded,
                color: AppColors.mEmergency,
                title: context.t('adm_no_audit'),
                message: context.t('adm_no_audit_msg'),
              );
            }
            return Column(
              children: [for (final l in logs) _auditRow(context, l)],
            );
          },
        ),
      ),
    ];
  }

  Widget _auditRow(BuildContext context, Map<String, dynamic> l) {
    final tk = context.tokens;
    final action = str(l['action']);
    final at = DateTime.tryParse(str(l['at']));
    final destructive = action == 'deleteData' || action == 'disable';
    final color = destructive ? tk.danger : (action == 'read' ? AppColors.mInsights : tk.textMuted);
    final icon = switch (action) {
      'read' => Icons.visibility_outlined,
      'deleteData' => Icons.delete_forever_rounded,
      'disable' => Icons.block_rounded,
      'enable' => Icons.check_circle_outline_rounded,
      'grantAdmin' => Icons.admin_panel_settings_rounded,
      'revokeAdmin' => Icons.person_remove_outlined,
      _ => Icons.info_outline_rounded,
    };
    final label = switch (action) {
      'read' => context.t('adm_act_read'),
      'deleteData' => context.t('adm_act_delete'),
      'disable' => context.t('adm_act_disable'),
      'enable' => context.t('adm_act_enable'),
      'grantAdmin' => context.t('adm_act_grant'),
      'revokeAdmin' => context.t('adm_act_revoke'),
      _ => context.t('adm_act_other'),
    };
    final coll = str(l['collection']);
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(children: [
        IconBadge(icon: icon, color: color, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
              ),
              if (coll.isNotEmpty && coll != 'all' && coll != 'account' && coll != 'admins') ...[
                const SizedBox(width: 6),
                Pill(_collectionLabel(context, coll), color: color),
              ],
            ]),
            const SizedBox(height: 3),
            Text(
              '${str(l['adminEmail']).isEmpty ? str(l['adminUid']) : str(l['adminEmail'])} → ${str(l['targetUid'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.tt.bodySmall,
            ),
            if (at != null)
              Text(context.relative(at),
                  style: context.tt.bodySmall?.copyWith(color: tk.textFaint)),
          ]),
        ),
      ]),
    );
  }
}

/// Inspect one user's content. Every collection opened writes an audit entry.
class _UserContentScreen extends StatefulWidget {
  final String uid;
  final String name;
  const _UserContentScreen({required this.uid, required this.name});

  @override
  State<_UserContentScreen> createState() => _UserContentScreenState();
}

class _UserContentScreenState extends State<_UserContentScreen> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final collection = _kCollections[_i];
    return AppPage(
      title: widget.name,
      subtitle: context.t('adm_view_content'),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChipRow<int>(
          items: [
            for (var i = 0; i < _kCollections.length; i++) (i, context.t(_kCollections[i].$2)),
          ],
          value: _i,
          onSelected: (v) => setState(() => _i = v),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: DhCard(
            color: tk.tint(tk.warning),
            borderColor: tk.warning.withValues(alpha: 0.4),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.privacy_tip_outlined, color: tk.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.t('adm_privacy_warn'), style: context.tt.bodySmall),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: _CollectionView(
            key: ValueKey('${widget.uid}_${collection.$1}'),
            uid: widget.uid,
            collection: collection.$1,
            color: collection.$4,
          ),
        ),
      ],
    );
  }
}

class _CollectionView extends StatefulWidget {
  final String uid;
  final String collection;
  final Color color;
  const _CollectionView({
    super.key,
    required this.uid,
    required this.collection,
    required this.color,
  });

  @override
  State<_CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<_CollectionView> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminService.instance.readUserCollection(widget.uid, widget.collection);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) {
          return EmptyView(
            compact: true,
            icon: Icons.inbox_outlined,
            color: widget.color,
            title: context.t('adm_nothing_here'),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(context.tn('adm_n_items', items.length)),
          for (final raw in items) _ItemCard(item: raw, color: widget.color),
        ]);
      },
    );
  }
}

/// One record, collapsed to its best-guess title with every field underneath.
class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color color;
  const _ItemCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final fields = Map<String, dynamic>.from(item)..remove('id');
    final guessed = [
      str(fields['title']),
      str(fields['name']),
      str(fields['note']),
      str(fields['text']),
      str(fields['body']),
      str(fields['from']),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final title = guessed.isEmpty ? context.t('adm_untitled_item') : guessed;
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: IconBadge(icon: Icons.description_outlined, color: color, size: 34),
        title: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
        children: [
          for (final e in fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.key,
                    style: context.tt.labelSmall?.copyWith(color: tk.textFaint)),
                Text('${e.value}', style: context.tt.bodySmall),
              ]),
            ),
        ],
      ),
    );
  }
}

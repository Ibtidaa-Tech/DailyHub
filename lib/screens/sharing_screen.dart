import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import '../core/workspace_provider.dart';
import '../data/models.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// Workspace sharing — same model as the web app.
///
/// Share by email (looked up via emailToUid), assign a role, change it live,
/// or revoke. Also lists the workspaces others have shared with you, and makes
/// it obvious which one you are looking at right now.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

/// Roles you can hand out. `owner` is never offered — it is yours alone.
const List<String> _grantableRoles = ['master', 'add', 'view'];

Color _roleColor(BuildContext context, String role) => switch (role) {
      'owner' => context.cs.primary,
      'master' => AppColors.mTasks,
      'add' => context.tokens.warning,
      _ => context.tokens.textMuted,
    };

IconData _roleIcon(String role) => switch (role) {
      'owner' => Icons.shield_rounded,
      'master' => Icons.edit_rounded,
      'add' => Icons.add_circle_outline_rounded,
      _ => Icons.visibility_outlined,
    };

class _SharingScreenState extends State<SharingScreen> {
  final _email = TextEditingController();
  String _role = 'view';
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showToast(context, context.t('share_enter_email'));
      return;
    }
    setState(() => _busy = true);
    final db = DbService.instance;
    try {
      final target = await db.lookupUidByEmail(email);
      if (!mounted) return;
      if (target == null) {
        showToast(context, context.t('share_no_user'));
        return;
      }
      if (target == db.uid) {
        showToast(context, context.t('share_not_yourself'));
        return;
      }
      await db.shareWith(email, _role);
      if (!mounted) return;
      _email.clear();
      FocusScope.of(context).unfocus();
      showToast(context, context.t('share_sent'), icon: Icons.check_circle_rounded);
    } catch (_) {
      if (mounted) showToast(context, context.t('share_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manage(Map<String, dynamic> c) async {
    final email = str(c['email']);
    final uid = str(c['uid']);
    final current = _grantableRoles.contains(str(c['role'])) ? str(c['role']) : 'view';
    await showAppSheet<void>(context, builder: (ctx) {
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(email.isEmpty ? ctx.t('someone') : email,
              subtitle: ctx.t('share_change_role')),
          for (final r in _grantableRoles)
            OptionTile(
              icon: _roleIcon(r),
              color: _roleColor(ctx, r),
              title: ctx.t('role_$r'),
              trailing: r == current
                  ? Icon(Icons.check_rounded, color: ctx.cs.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (r == current) return;
                DbService.instance.updateCollaboratorRole(uid, r);
                showToast(context, context.t('share_role_changed'));
              },
            ),
          Divider(height: 1, color: ctx.tokens.border),
          OptionTile(
            icon: Icons.person_remove_outlined,
            destructive: true,
            title: ctx.t('share_remove'),
            onTap: () {
              Navigator.pop(ctx);
              _remove(c);
            },
          ),
          const SizedBox(height: 8),
        ]),
      );
    });
  }

  Future<void> _remove(Map<String, dynamic> c) async {
    final email = str(c['email']);
    final name = email.isEmpty ? context.t('someone') : email;
    final ok = await confirmDialog(
      context,
      title: context.tr('share_remove_q', {'name': name}),
      message: context.t('share_remove_msg'),
      confirm: context.t('remove'),
      danger: true,
    );
    if (!ok || !mounted) return;
    await DbService.instance.removeCollaborator(str(c['uid']));
    if (!mounted) return;
    showToast(context, context.tr('share_removed', {'name': name}));
  }

  void _switchTo(WorkspaceProvider ws, Map<String, dynamic> s) {
    final owner = str(s['ownerName']).isEmpty ? context.t('someone') : str(s['ownerName']);
    final uid = str(s['uid']);
    final role = str(s['role']).isEmpty ? 'view' : str(s['role']);
    ws.switchTo(uid: uid, role: role, name: owner);
    DbService.instance.activeWorkspaceUid = uid;
    showToast(context, context.tr('ws_switched', {'name': owner}),
        icon: Icons.groups_rounded);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    final ws = context.watch<WorkspaceProvider>();

    return AppPage(
      title: context.t('share_workspace'),
      subtitle: context.t('share_workspace_sub'),
      slivers: [
        SliverToBoxAdapter(child: _currentSpace(context, ws)),

        // --------------------------------------------------------- invite
        SliverToBoxAdapter(child: SectionTitle(context.t('share_invite'))),
        SliverToBoxAdapter(child: _inviteCard(context)),

        // ---------------------------------------------------- shared with
        SliverToBoxAdapter(child: SectionTitle(context.t('share_with'))),
        SliverToBoxAdapter(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: db.collaboratorsStream(),
            builder: (context, snap) {
              final list = snap.data ?? const <Map<String, dynamic>>[];
              if (list.isEmpty) {
                return EmptyView(
                  compact: true,
                  icon: Icons.group_add_outlined,
                  color: AppColors.mTasks,
                  title: context.t('share_none'),
                  message: context.t('share_none_msg'),
                );
              }
              return Column(
                children: [for (final c in list) _collaboratorRow(context, c)],
              );
            },
          ),
        ),

        // ------------------------------------------------- shared with me
        SliverToBoxAdapter(child: SectionTitle(context.t('share_with_me'))),
        SliverToBoxAdapter(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: db.sharedWithMeStream(),
            builder: (context, snap) {
              final list = snap.data ?? const <Map<String, dynamic>>[];
              if (list.isEmpty) {
                return EmptyView(
                  compact: true,
                  icon: Icons.workspaces_outlined,
                  color: AppColors.mTasks,
                  title: context.t('share_none_mine'),
                  message: context.t('share_none_mine_msg'),
                );
              }
              return Column(
                children: [for (final s in list) _sharedRow(context, ws, s)],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Which space you are in right now, and the way back to your own.
  Widget _currentSpace(BuildContext context, WorkspaceProvider ws) {
    final own = ws.isOwnWorkspace;
    final role = ws.role.isEmpty ? 'owner' : ws.role;
    return DhCard(
      borderColor: own ? null : context.cs.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(
            icon: own ? Icons.home_rounded : Icons.groups_rounded,
            color: own ? AppColors.mTasks : context.cs.primary,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                own ? context.t('ws_mine') : context.tr('ws_of', {'name': ws.name}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Pill(context.t('role_$role'),
                    color: _roleColor(context, role), icon: _roleIcon(role)),
              ]),
            ]),
          ),
        ]),
        if (!own) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(context.t('ws_back_to_mine')),
            onPressed: () {
              ws.resetToOwn();
              DbService.instance.activeWorkspaceUid = ws.ownUid;
            },
          ),
        ],
      ]),
    );
  }

  Widget _inviteCard(BuildContext context) {
    return DhCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('share_invite_sub'), style: context.tt.bodySmall),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_busy) _share();
          },
          decoration: InputDecoration(
            hintText: context.t('share_email_hint'),
            prefixIcon: const Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Text(context.t('share_role'), style: context.tt.labelMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in _grantableRoles)
            ChoiceChip(
              avatar: Icon(_roleIcon(r), size: 16, color: _roleColor(context, r)),
              label: Text(context.t('role_$r')),
              selected: _role == r,
              onSelected: (_) => setState(() => _role = r),
            ),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _share,
          icon: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.person_add_alt_rounded),
          label: Text(context.t('share')),
        ),
      ]),
    );
  }

  Widget _collaboratorRow(BuildContext context, Map<String, dynamic> c) {
    final email = str(c['email']);
    final role = _grantableRoles.contains(str(c['role'])) ? str(c['role']) : 'view';
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      onTap: () => _manage(c),
      child: Row(children: [
        InitialsAvatar(email.isEmpty ? context.t('someone') : email, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              email.isEmpty ? context.t('someone') : email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Pill(context.t('role_$role'),
                  color: _roleColor(context, role), icon: _roleIcon(role)),
            ]),
          ]),
        ),
        IconButton(
          tooltip: context.t('more_options'),
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () => _manage(c),
        ),
      ]),
    );
  }

  Widget _sharedRow(BuildContext context, WorkspaceProvider ws, Map<String, dynamic> s) {
    final owner = str(s['ownerName']).isEmpty ? context.t('someone') : str(s['ownerName']);
    final role = str(s['role']).isEmpty ? 'view' : str(s['role']);
    final active = ws.workspaceUid == str(s['uid']);
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      borderColor: active ? context.cs.primary : null,
      onTap: active ? null : () => _switchTo(ws, s),
      child: Row(children: [
        InitialsAvatar(owner, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              context.tr('ws_of', {'name': owner}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Pill(context.t('role_$role'),
                  color: _roleColor(context, role), icon: _roleIcon(role)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        if (active)
          Pill(context.t('ws_current'), color: context.cs.primary, filled: true)
        else
          Icon(Icons.chevron_right_rounded, color: context.tokens.textFaint),
      ]),
    );
  }
}

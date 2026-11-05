import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/tracker_store.dart';
import '../../services/mentor_service.dart';
import '../../ui/kit.dart';
import 'challenge_editor.dart';
import 'student_detail.dart';

/// Both sides of the mentor link in one place: people you guide, and people
/// guiding you.
class MentorScreen extends StatefulWidget {
  const MentorScreen({super.key});
  @override
  State<MentorScreen> createState() => _MentorScreenState();
}

class _MentorScreenState extends State<MentorScreen> {
  final MentorService _svc = MentorService.instance;
  late final Stream<List<Map<String, dynamic>>> _students = _svc.myStudents();
  late final Stream<List<Map<String, dynamic>>> _mentors = _svc.myMentors();

  /// The other direction: hand your own tracker to a mentor. Takes effect at
  /// once, because you are giving away a view of your own data.
  Future<void> _giveAccess() async {
    final email = await promptText(
      context,
      title: context.t('tr_give_access'),
      hint: context.t('tr_mentor_email_hint'),
      keyboard: TextInputType.emailAddress,
    );
    if (email == null || email.trim().isEmpty || !mounted) return;
    try {
      await _svc.addMentor(email.trim());
      if (mounted) {
        showToast(context, context.tr('tr_mentor_added', {'name': email.trim()}),
            icon: Icons.school_rounded);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded);
      }
    }
  }

  /// One programme, several students. Each gets their own independent copy,
  /// so a student editing theirs never touches anyone else's.
  Future<void> _assignMany(List<Map<String, dynamic>> students) async {
    final accepted = students
        .where((s) => str(s['status']) == MentorService.accepted)
        .toList();
    if (accepted.isEmpty) {
      showToast(context, context.t('tr_no_accepted_students'), icon: Icons.info_outline_rounded);
      return;
    }

    final chosen = <String>{for (final s in accepted) str(s['id'])};
    final picked = await showAppSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(ctx.t('tr_pick_students')),
            const SizedBox(height: 4),
            GroupCard(children: [
              for (final s in accepted)
                CheckboxListTile(
                  value: chosen.contains(str(s['id'])),
                  onChanged: (v) => setSheet(() {
                    if (v == true) {
                      chosen.add(str(s['id']));
                    } else {
                      chosen.remove(str(s['id']));
                    }
                  }),
                  title: Text(str(s['name']).isEmpty ? str(s['email']) : str(s['name'])),
                  subtitle: Text(str(s['email'])),
                ),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(ctx.tr('tr_assign_count', {'n': chosen.length})),
              ),
            ),
          ]),
        ),
      ),
    );
    if (picked != true || chosen.isEmpty || !mounted) return;

    // Short-lived stores, one per student, purely to write into their data.
    final stores = [for (final uid in chosen) TrackerStore(forUid: uid)];
    try {
      final id = await showChallengeEditor(context, stores: stores);
      if (id != null && mounted) {
        showToast(context, context.tr('tr_assigned_many', {'n': stores.length}),
            icon: Icons.check_rounded);
      }
    } finally {
      for (final s in stores) {
        s.dispose();
      }
    }
  }

  Future<void> _invite() async {
    final email = await promptText(
      context,
      title: context.t('tr_add_student'),
      hint: context.t('tr_student_email_hint'),
      keyboard: TextInputType.emailAddress,
    );
    if (email == null || email.trim().isEmpty || !mounted) return;
    try {
      await _svc.invite(email.trim());
      if (mounted) showToast(context, context.t('tr_invited'), icon: Icons.send_rounded);
    } catch (e) {
      if (mounted) {
        showToast(context, e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: context.t('tr_mentor_title'),
      slivers: [
        // ------------------------------------------------- invites to me
        SliverToBoxAdapter(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _mentors,
            builder: (context, snap) {
              final all = snap.data ?? const <Map<String, dynamic>>[];
              final waiting = all.where((m) => str(m['status']) != MentorService.accepted).toList();
              final active = all.where((m) => str(m['status']) == MentorService.accepted).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final m in waiting) _InviteCard(invite: m, svc: _svc),
                SectionTitle(context.t('tr_my_mentors')),
                GroupCard(children: [
                  OptionTile(
                    icon: Icons.person_add_alt_1_rounded,
                    color: AppColors.mStudy,
                    title: context.t('tr_give_access'),
                    subtitle: context.t('tr_give_access_sub'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _giveAccess,
                  ),
                ]),
                if (active.isEmpty)
                  DhCard(
                    child: Text(context.t('tr_no_mentors'),
                        style: context.tt.bodyMedium?.copyWith(color: context.tokens.textMuted)),
                  )
                else
                  GroupCard(children: [
                    for (final m in active)
                      OptionTile(
                        icon: Icons.school_rounded,
                        color: AppColors.mStudy,
                        title: str(m['name']).isEmpty ? str(m['email']) : str(m['name']),
                        subtitle: str(m['email']),
                        trailing: IconButton(
                          tooltip: context.t('tr_remove_mentor'),
                          icon: Icon(Icons.person_remove_outlined, color: context.tokens.danger),
                          onPressed: () async {
                            final name = str(m['name']).isEmpty ? str(m['email']) : str(m['name']);
                            final ok = await confirmDialog(
                              context,
                              title: context.t('tr_remove_mentor'),
                              message: context.tr('tr_remove_mentor_q', {'name': name}),
                              confirm: context.t('delete'),
                              danger: true,
                            );
                            if (ok) await _svc.removeMentor(str(m['id']));
                          },
                        ),
                      ),
                  ]),
                DhCard(
                  color: context.tokens.tint(AppColors.mTracker),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.shield_outlined, size: 20, color: AppColors.mTracker),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t('tr_what_mentor_sees'), style: context.tt.labelLarge),
                        const SizedBox(height: 2),
                        Text(context.t('tr_what_mentor_sees_msg'), style: context.tt.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              ]);
            },
          ),
        ),
        // ---------------------------------------------------- my students
        SliverToBoxAdapter(child: SectionTitle(context.t('tr_my_students'))),
        SliverToBoxAdapter(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _students,
            builder: (context, snap) {
              final list = snap.data ?? const <Map<String, dynamic>>[];
              if (list.isEmpty) {
                return EmptyView(
                  icon: Icons.groups_rounded,
                  color: AppColors.mStudy,
                  title: context.t('tr_no_students_title'),
                  message: context.t('tr_no_students_msg'),
                  actionLabel: context.t('tr_add_student'),
                  onAction: _invite,
                  compact: true,
                );
              }
              return Column(children: [
                GroupCard(children: [
                  for (final s in list) _StudentTile(student: s, svc: _svc),
                ]),
                GroupCard(children: [
                  OptionTile(
                    icon: Icons.groups_rounded,
                    color: AppColors.mTracker,
                    title: context.t('tr_assign_many'),
                    subtitle: context.t('tr_assign_many_sub'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _assignMany(list),
                  ),
                ]),
              ]);
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
      fab: FloatingActionButton.extended(
        heroTag: 'mentorAdd',
        onPressed: _invite,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: Text(context.t('tr_add_student')),
      ),
    );
  }
}

/// A pending invite, shown to the student with what it actually grants.
class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> invite;
  final MentorService svc;
  const _InviteCard({required this.invite, required this.svc});

  @override
  Widget build(BuildContext context) {
    final name = str(invite['name']).isEmpty ? str(invite['email']) : str(invite['name']);
    final uid = str(invite['id']);
    return DhCard(
      color: context.tokens.tint(AppColors.mStudy),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(icon: Icons.school_rounded, color: AppColors.mStudy, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('tr_invite_you', {'name': name}), style: context.tt.titleSmall),
              Text(str(invite['email']), style: context.tt.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(context.t('tr_invite_explain'),
            style: context.tt.bodySmall?.copyWith(color: context.tokens.textMuted)),
        const SizedBox(height: 10),
        Row(children: [
          TextButton(
            onPressed: () => svc.removeMentor(uid),
            child: Text(context.t('tr_decline')),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () async {
              await svc.accept(uid);
              if (context.mounted) showToast(context, context.t('tr_accept'), icon: Icons.check_rounded);
            },
            child: Text(context.t('tr_accept')),
          ),
        ]),
      ]),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final Map<String, dynamic> student;
  final MentorService svc;
  const _StudentTile({required this.student, required this.svc});

  @override
  Widget build(BuildContext context) {
    final name = str(student['name']).isEmpty ? str(student['email']) : str(student['name']);
    final uid = str(student['id']);
    final isPending = str(student['status']) != MentorService.accepted;
    return OptionTile(
      icon: isPending ? Icons.hourglass_empty_rounded : Icons.person_rounded,
      color: isPending ? context.tokens.textMuted : AppColors.mTracker,
      title: name,
      subtitle: isPending ? context.t('tr_pending_invite') : str(student['email']),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: context.t('tr_remove_student'),
          icon: Icon(Icons.person_remove_outlined, size: 20, color: context.tokens.danger),
          onPressed: () async {
            final ok = await confirmDialog(
              context,
              title: context.t('tr_remove_student'),
              message: context.tr('tr_remove_student_q', {'name': name}),
              confirm: context.t('delete'),
              danger: true,
            );
            if (ok) await svc.removeStudent(uid);
          },
        ),
        if (!isPending) const Icon(Icons.chevron_right_rounded),
      ]),
      onTap: isPending
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentDetailScreen(studentUid: uid, name: name)),
              ),
    );
  }
}

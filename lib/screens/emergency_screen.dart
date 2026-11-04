import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

String _str(Object? v) => (v ?? '').toString();

/// Blood groups are written the same way in every Indian language, so they are
/// symbols rather than translatable text.
const List<String> kBloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

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

/// Emergency information, built for the worst moment to be reading a screen:
/// big targets, one tap to call, and medical details already on display.
///
/// This stays deliberately light on sensitive detail. Identity documents and
/// anything you'd call a secret belong in the encrypted device-only vault.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  /// Indian national emergency numbers, with translated labels.
  static List<(String, String, IconData)> helplines(BuildContext c) => [
        ('112', c.t('emg_h_all'), Icons.emergency_rounded),
        ('100', c.t('emg_h_police'), Icons.local_police_outlined),
        ('101', c.t('emg_h_fire'), Icons.local_fire_department_outlined),
        ('102', c.t('emg_h_ambulance'), Icons.medical_services_outlined),
        ('108', c.t('emg_h_disaster'), Icons.health_and_safety_outlined),
        ('1091', c.t('emg_h_women'), Icons.support_agent_rounded),
        ('1098', c.t('emg_h_child'), Icons.child_care_outlined),
      ];

  static Future<void> dial(BuildContext context, String number) async {
    final digits = number.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (digits.isEmpty) return;
    HapticFeedback.mediumImpact();
    final uri = Uri.parse('tel:$digits');
    final ok = await canLaunchUrl(uri);
    if (!context.mounted) return;
    if (ok) {
      await launchUrl(uri);
      return;
    }
    showToast(context, context.tr('emg_call_failed', {'n': number}),
        icon: Icons.phone_disabled_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final db = DbService.instance;
    final tk = context.tokens;

    return AppPage(
      title: context.t('m_emergency'),
      subtitle: context.t('emg_sub'),
      fab: FloatingActionButton.extended(
        onPressed: () => _contactEditor(context, db),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(context.t('emg_add_contact')),
      ),
      header: _SosButton(onTap: () => dial(context, '112')),
      slivers: [
        // ---------------------------------------------------- medical info
        SliverToBoxAdapter(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: db.stream('emergencyNotes'),
            builder: (context, snap) {
              final notes = snap.data ?? const <Map<String, dynamic>>[];
              final med = notes.isEmpty ? null : notes.first;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle(
                  context.t('emg_medical'),
                  action: med == null ? null : context.t('edit'),
                  onAction: med == null ? null : () => _medicalEditor(context, db, med),
                ),
                _MedicalCard(
                  data: med,
                  onEdit: () => _medicalEditor(context, db, med),
                ),
              ]);
            },
          ),
        ),

        // -------------------------------------------------------- contacts
        SliverToBoxAdapter(child: SectionTitle(context.t('emg_contacts'))),
        SliverToBoxAdapter(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: db.stream('emergencyContacts'),
            builder: (context, snap) {
              final contacts = snap.data ?? const <Map<String, dynamic>>[];
              if (contacts.isEmpty) {
                return EmptyView(
                  icon: Icons.contact_phone_outlined,
                  color: AppColors.mEmergency,
                  title: context.t('emg_no_contacts'),
                  message: context.t('emg_no_contacts_msg'),
                  actionLabel: context.t('emg_add_contact'),
                  onAction: () => _contactEditor(context, db),
                  compact: true,
                );
              }
              return Column(
                children: [
                  for (final c in contacts)
                    _ContactCard(
                      key: ValueKey('emg_${_str(c['id'])}'),
                      id: _str(c['id']),
                      name: _str(c['name']),
                      phone: _str(c['phone']),
                      relation: _str(c['relation']),
                      onCall: () => dial(context, _str(c['phone'])),
                      onEdit: () => _contactEditor(context, db, existing: c),
                      onDelete: () => _deleteContact(context, db, c),
                    ),
                ],
              );
            },
          ),
        ),

        // ------------------------------------------------------ helplines
        SliverToBoxAdapter(child: SectionTitle(context.t('emg_helplines'))),
        SliverList.list(
          children: [
            for (final h in helplines(context))
              _HelplineRow(
                number: h.$1,
                label: h.$2,
                icon: h.$3,
                onTap: () => dial(context, h.$1),
              ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_sync_outlined, size: 15, color: tk.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.t('emg_synced_note'),
                    style: context.tt.bodySmall?.copyWith(color: tk.textFaint)),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- editors

  Future<void> _deleteContact(
      BuildContext context, DbService db, Map<String, dynamic> c) async {
    final id = _str(c['id']);
    final data = Map<String, dynamic>.from(c)..remove('id');
    await db.remove('emergencyContacts', id);
    if (!context.mounted) return;
    showUndo(context, context.t('emg_contact_removed'),
        () => db.set('emergencyContacts', id, data));
  }

  Future<void> _contactEditor(BuildContext context, DbService db,
      {Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: _str(existing?['name']));
    final phone = TextEditingController(text: _str(existing?['phone']));
    final relation = TextEditingController(text: _str(existing?['relation']));

    await showAppSheet<void>(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(ctx.t(existing == null ? 'emg_add_contact' : 'emg_edit_contact')),
              const SizedBox(height: 6),
              TextField(
                controller: name,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: ctx.t('name'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: ctx.t('emg_phone'),
                  prefixIcon: const Icon(Icons.call_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: relation,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: ctx.t('emg_relation'),
                  prefixIcon: const Icon(Icons.diversity_1_outlined),
                ),
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
                      _deleteContact(context, db, existing);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                      showToast(ctx, ctx.t('emg_need_name_phone'));
                      return;
                    }
                    final data = <String, dynamic>{
                      'name': name.text.trim(),
                      'phone': phone.text.trim(),
                      'relation': relation.text.trim(),
                    };
                    if (existing == null) {
                      await db.add('emergencyContacts', data);
                    } else {
                      await db.set('emergencyContacts', _str(existing['id']), data);
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!context.mounted) return;
                    showToast(context, context.t('emg_contact_saved'), icon: Icons.check_rounded);
                  },
                  child: Text(ctx.t('save')),
                ),
              ]),
            ],
          ),
        ),
      );
    });
    _disposeLater([name, phone, relation]);
  }

  Future<void> _medicalEditor(
      BuildContext context, DbService db, Map<String, dynamic>? existing) async {
    final allergies = TextEditingController(text: _str(existing?['allergies']));
    final conditions = TextEditingController(text: _str(existing?['conditions']));
    final notes = TextEditingController(text: _str(existing?['text']));
    var blood = _str(existing?['blood']);

    await showAppSheet<void>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(ctx.t('emg_edit_medical'), subtitle: ctx.t('emg_medical_msg')),
                const SizedBox(height: 6),
                Text(ctx.t('emg_blood'), style: ctx.tt.labelMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in kBloodGroups)
                    ChoiceChip(
                      label: Text(g),
                      selected: blood == g,
                      onSelected: (_) => set(() => blood = blood == g ? '' : g),
                    ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: allergies,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: ctx.t('emg_allergies'),
                    prefixIcon: const Icon(Icons.dangerous_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: conditions,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: ctx.t('emg_conditions'),
                    prefixIcon: const Icon(Icons.monitor_heart_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: ctx.t('emg_other_notes'),
                    hintText: ctx.t('emg_notes_hint'),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    final data = <String, dynamic>{
                      'blood': blood,
                      'allergies': allergies.text.trim(),
                      'conditions': conditions.text.trim(),
                      'text': notes.text.trim(),
                    };
                    if (existing == null) {
                      await db.add('emergencyNotes', data);
                    } else {
                      await db.set('emergencyNotes', _str(existing['id']), data);
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!context.mounted) return;
                    showToast(context, context.t('emg_medical_saved'), icon: Icons.check_rounded);
                  },
                  child: Text(ctx.t('save')),
                ),
              ],
            ),
          ),
        );
      });
    });
    _disposeLater([allergies, conditions, notes]);
  }
}

/// The one thing that must work without reading anything: call 112.
class _SosButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SosButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const red = AppColors.mEmergency;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: red,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    context.t('emg_call_112'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t('emg_call_112_msg'),
                    maxLines: 2,
                    style: context.tt.bodySmall
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.call_rounded, color: Colors.white, size: 26),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Blood group, allergies and conditions, readable at a glance by someone who
/// has never held this phone before.
class _MedicalCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final VoidCallback onEdit;
  const _MedicalCard({required this.data, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final blood = _str(data?['blood']);
    final allergies = _str(data?['allergies']);
    final conditions = _str(data?['conditions']);
    final notes = _str(data?['text']);

    if (blood.isEmpty && allergies.isEmpty && conditions.isEmpty && notes.isEmpty) {
      return EmptyView(
        icon: Icons.medical_information_outlined,
        color: AppColors.mEmergency,
        title: context.t('emg_no_medical'),
        message: context.t('emg_no_medical_msg'),
        actionLabel: context.t('emg_edit_medical'),
        onAction: onEdit,
        compact: true,
      );
    }

    return DhCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      onTap: onEdit,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('emg_blood'), style: context.tt.bodySmall),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  blood.isEmpty ? context.t('emg_not_added') : blood,
                  style: blood.isEmpty
                      ? context.tt.titleMedium?.copyWith(color: tk.textFaint)
                      : context.tt.displaySmall?.copyWith(color: tk.danger),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          const IconBadge(
            icon: Icons.medical_information_outlined,
            color: AppColors.mEmergency,
            size: 44,
          ),
        ]),
        if (allergies.isNotEmpty) ...[
          const SizedBox(height: 14),
          _MedicalLine(
            icon: Icons.dangerous_outlined,
            label: context.t('emg_allergies'),
            value: allergies,
            color: tk.danger,
          ),
        ],
        if (conditions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MedicalLine(
            icon: Icons.monitor_heart_outlined,
            label: context.t('emg_conditions'),
            value: conditions,
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MedicalLine(
            icon: Icons.notes_outlined,
            label: context.t('emg_other_notes'),
            value: notes,
          ),
        ],
      ]),
    );
  }
}

class _MedicalLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _MedicalLine({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final c = color ?? tk.textMuted;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 17, color: c),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: context.tt.labelSmall?.copyWith(color: c, letterSpacing: 0.6)),
          const SizedBox(height: 1),
          Text(value, style: context.tt.bodyLarge),
        ]),
      ),
    ]);
  }
}

/// A person to call: the whole card dials, the name is big enough to find
/// without reading carefully.
class _ContactCard extends StatelessWidget {
  final String id;
  final String name;
  final String phone;
  final String relation;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactCard({
    super.key,
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return SwipeTile(
      swipeKey: ValueKey('emgtile_$id'),
      leftIcon: Icons.delete_outline_rounded,
      leftColor: tk.danger,
      leftLabel: context.t('delete'),
      onSwipeLeft: () async {
        onDelete();
        return true;
      },
      child: DhCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        onTap: onCall,
        onLongPress: onEdit,
        child: Row(children: [
          InitialsAvatar(name.isEmpty ? '?' : name, size: 46, color: AppColors.mEmergency),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                name.isEmpty ? context.t('emg_add_contact') : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.titleLarge,
              ),
              const SizedBox(height: 2),
              Wrap(spacing: 10, runSpacing: 2, children: [
                if (relation.isNotEmpty) MetaChip(Icons.diversity_1_outlined, relation),
                if (phone.isNotEmpty) MetaChip(Icons.call_outlined, phone),
              ]),
            ]),
          ),
          const SizedBox(width: 4),
          _CallButton(onTap: onCall),
          IconButton(
            tooltip: context.t('edit'),
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(Icons.more_horiz_rounded, color: tk.textFaint),
            onPressed: onEdit,
          ),
        ]),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('emg_call'),
      child: Material(
        color: context.tokens.tint(context.tokens.success),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.call_rounded, color: context.tokens.success, size: 24),
          ),
        ),
      ),
    );
  }
}

/// A national helpline: one row, one tap, the number always visible.
class _HelplineRow extends StatelessWidget {
  final String number;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _HelplineRow({
    required this.number,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return DhCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      onTap: onTap,
      child: Row(children: [
        IconBadge(icon: icon, color: AppColors.mEmergency, size: 42),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.tt.titleSmall),
        ),
        const SizedBox(width: 10),
        Text(number, style: context.tt.titleLarge?.copyWith(color: tk.danger)),
        const SizedBox(width: 8),
        Icon(Icons.call_rounded, size: 20, color: tk.textFaint),
      ]),
    );
  }
}

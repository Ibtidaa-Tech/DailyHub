import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_version.dart';
import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../screens/admin_screen.dart';
import '../../screens/sharing_screen.dart';
import '../../services/admin_service.dart';
import '../../services/app_lock_service.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/db_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/update_service.dart';
import '../../services/weather_service.dart';
import '../../ui/brand.dart';
import '../../ui/kit.dart';
import '../../widgets/update_dialog.dart';
import '../hub/modules.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final user = FirebaseAuth.instance.currentUser;
    final tk = context.tokens;
    return AppPage(
      title: context.t('settings'),
      slivers: [
        SliverToBoxAdapter(
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: DbService.instance.profileStream(),
            builder: (context, snap) {
              final name = str(snap.data?['name']).isNotEmpty ? str(snap.data?['name']) : (user?.displayName ?? '');
              return DhCard(
                onTap: () => _push(context, const ProfileScreen()),
                child: Row(children: [
                  InitialsAvatar(name.isEmpty ? (user?.email ?? '?') : name, size: 52, color: context.cs.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.isEmpty ? context.t('your_name') : name, style: context.tt.titleMedium),
                      Text(user?.email ?? '', style: context.tt.bodySmall),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: tk.textFaint),
                ]),
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('appearance'))),
        SliverToBoxAdapter(
          child: DhCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('theme'), style: context.tt.labelLarge),
              const SizedBox(height: 8),
              PillTabs<ThemeMode>(
                items: [
                  (ThemeMode.system, context.t('theme_system')),
                  (ThemeMode.light, context.t('theme_light')),
                  (ThemeMode.dark, context.t('theme_dark')),
                ],
                value: s.themeMode,
                onChanged: s.setThemeMode,
              ),
              const SizedBox(height: 16),
              Text(context.t('accent_color'), style: context.tt.labelLarge),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final a in Accents.all)
                  Tooltip(
                    message: context.t(a.nameKey),
                    child: GestureDetector(
                      onTap: () => s.setAccent(a.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: context.isDark ? a.dark : a.light,
                          shape: BoxShape.circle,
                          border: Border.all(color: s.accent == a.id ? context.cs.onSurface : Colors.transparent, width: 3),
                        ),
                        child: s.accent == a.id ? Icon(Icons.check_rounded, color: context.isDark ? Colors.black : Colors.white) : null,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              Text(context.t('language'), style: context.tt.labelLarge),
              const SizedBox(height: 8),
              PillTabs<String>(
                items: const [('en', 'English'), ('hi', 'हिन्दी')],
                value: s.lang,
                onChanged: s.setLang,
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('your_app'))),
        SliverToBoxAdapter(
          child: GroupCard(children: [
            OptionTile(
              icon: Icons.dashboard_customize_outlined,
              color: AppColors.mCalendar,
              title: context.t('manage_modules'),
              subtitle: context.tr('n_modules_on', {'n': Modules.toggleables.where((m) => s.isOn(m.id)).length}),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const ModulesScreen()),
            ),
            OptionTile(
              icon: Icons.view_quilt_outlined,
              color: AppColors.mTasks,
              title: context.t('customize_home'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const HomeLayoutScreen()),
            ),
          ]),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('region'))),
        SliverToBoxAdapter(
          child: GroupCard(children: [
            OptionTile(
              icon: Icons.payments_outlined,
              color: AppColors.mMoney,
              title: context.t('currency'),
              subtitle: '${Money.current.code} · ${Money.current.name}',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const CurrencyScreen()),
            ),
            // The segmented control needs the full row width, so the label sits
            // above it rather than in a ListTile trailing slot (which would
            // squeeze the title to a few characters on a narrow phone).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.calendar_view_week_outlined, color: AppColors.mCalendar),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(context.t('week_starts'),
                        style: context.tt.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.mCalendar)),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: DateTime.monday, label: Text(context.t('monday_short'))),
                      ButtonSegment(value: DateTime.sunday, label: Text(context.t('sunday_short'))),
                    ],
                    selected: {s.weekStart},
                    onSelectionChanged: (v) => s.setWeekStart(v.first),
                  ),
                ),
              ]),
            ),
            SwitchListTile(
              secondary: Icon(Icons.schedule_rounded, color: tk.textMuted),
              title: Text(context.t('use_24h')),
              value: s.use24h,
              onChanged: s.setUse24h,
            ),
          ]),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('notifications'))),
        SliverToBoxAdapter(child: _NotificationSettings(settings: s)),
        SliverToBoxAdapter(child: SectionTitle(context.t('weather'))),
        SliverToBoxAdapter(
          child: GroupCard(children: [
            OptionTile(
              icon: Icons.wb_sunny_outlined,
              color: AppColors.mReminders,
              title: context.t('weather_location'),
              subtitle: s.weatherUseLocation
                  ? context.t('wx_using_location')
                  : (s.weatherCity.isEmpty ? context.t('wx_not_set') : s.weatherCity),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const WeatherCityScreen()),
            ),
          ]),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('privacy_security'))),
        SliverToBoxAdapter(
          child: GroupCard(children: [
            if (AppLockService.instance.supported)
              SwitchListTile(
                secondary: Icon(Icons.fingerprint_rounded, color: tk.textMuted),
                title: Text(context.t('app_lock')),
                subtitle: Text(context.t('app_lock_sub')),
                value: s.appLock,
                onChanged: (v) async {
                  if (v) {
                    final avail = await AppLockService.instance.available();
                    if (!context.mounted) return;
                    if (!avail) {
                      showToast(context, context.t('no_screen_lock'));
                      return;
                    }
                    final ok = await AppLockService.instance.authenticate(context.t('lock_reason'));
                    if (!ok) return;
                  }
                  s.setAppLock(v);
                },
              ),
            OptionTile(
              icon: Icons.group_add_outlined,
              color: AppColors.mTasks,
              title: context.t('share_workspace'),
              subtitle: context.t('share_workspace_sub'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const SharingScreen()),
            ),
          ]),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('your_data'))),
        SliverToBoxAdapter(
          child: GroupCard(children: [
            OptionTile(
              icon: Icons.cloud_download_outlined,
              color: AppColors.mMoney,
              title: context.t('backup_export'),
              subtitle: context.t('backup_export_sub'),
              onTap: () async {
                try {
                  await BackupService.instance.exportAndShare();
                } catch (_) {
                  if (context.mounted) showToast(context, context.t('backup_failed'));
                }
              },
            ),
            OptionTile(
              icon: Icons.cloud_upload_outlined,
              color: AppColors.mInsights,
              title: context.t('backup_restore'),
              subtitle: context.t('backup_restore_sub'),
              onTap: () => _restore(context),
            ),
          ]),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('about'))),
        SliverToBoxAdapter(
          child: StreamBuilder<bool>(
            stream: AdminService.instance.adminStream(),
            builder: (context, snap) => GroupCard(children: [
              OptionTile(
                icon: Icons.system_update_outlined,
                title: context.t('check_updates'),
                subtitle: '${context.t('version')} ${AppVersion.appVersion}',
                onTap: () async {
                  showToast(context, context.t('checking'));
                  final info = await UpdateService.instance.check(ignoreSkipped: true);
                  if (!context.mounted) return;
                  if (info == null) {
                    showToast(context, context.t('up_to_date'), icon: Icons.check_circle_rounded);
                  } else {
                    await showUpdateDialog(context, info);
                  }
                },
              ),
              if (snap.data == true)
                OptionTile(
                  icon: Icons.admin_panel_settings_outlined,
                  color: AppColors.mEmergency,
                  title: context.t('m_admin'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _push(context, const AdminScreen()),
                ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: tk.danger),
              icon: const Icon(Icons.logout_rounded),
              label: Text(context.t('sign_out')),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: context.t('sign_out_q'), message: context.t('sign_out_msg'), confirm: context.t('sign_out'), danger: true);
                if (ok) await AuthService().signOut();
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Column(children: [
              const BrandMark(size: 36),
              const SizedBox(height: 6),
              Text('DailyHub ${AppVersion.appVersion}', style: context.tt.bodySmall),
              Text(context.t('made_with_care'), style: context.tt.bodySmall?.copyWith(fontSize: 11)),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _restore(BuildContext context) async {
    Map<String, dynamic>? data;
    try {
      data = await BackupService.instance.pick();
    } catch (_) {
      if (context.mounted) showToast(context, context.t('not_a_backup'));
      return;
    }
    if (data == null || !context.mounted) return;
    final counts = BackupService.instance.summarize(data);
    final total = counts.values.fold(0, (a, b) => a + b);
    final ok = await confirmDialog(
      context,
      title: context.t('restore_q'),
      message: context.tr('restore_msg', {'n': total}),
      confirm: context.t('restore'),
    );
    if (!ok) return;
    final n = await BackupService.instance.restore(data);
    if (context.mounted) showToast(context, context.tr('restored_n', {'n': n}), icon: Icons.check_circle_rounded);
  }
}

class _NotificationSettings extends StatefulWidget {
  final AppSettings settings;
  const _NotificationSettings({required this.settings});
  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.areEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final tk = context.tokens;
    if (kIsWeb) {
      return DhCard(child: Text(context.t('notif_web'), style: context.tt.bodySmall));
    }
    return GroupCard(children: [
      if (_enabled == false)
        ListTile(
          leading: Icon(Icons.notifications_off_rounded, color: tk.danger),
          title: Text(context.t('notif_off'), style: TextStyle(color: tk.danger, fontWeight: FontWeight.w700)),
          subtitle: Text(context.t('notif_off_sub')),
          trailing: FilledButton(
            onPressed: () async {
              final ok = await NotificationService.instance.requestPermissions();
              if (mounted) setState(() => _enabled = ok);
            },
            child: Text(context.t('enable')),
          ),
        ),
      SwitchListTile(
        secondary: const Text('☀️', style: TextStyle(fontSize: 22)),
        title: Text(context.t('morning_briefing')),
        subtitle: Text(s.morningBriefing ? context.tr('every_day_at', {'t': context.timeOfHm(s.morningTime)}) : context.t('off')),
        value: s.morningBriefing,
        onChanged: (v) => s.setBriefing(morning: v),
      ),
      if (s.morningBriefing)
        OptionTile(
          icon: Icons.schedule_rounded,
          title: context.t('briefing_time'),
          trailing: Text(context.timeOfHm(s.morningTime), style: context.tt.labelLarge),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: parseHm(s.morningTime) ?? const TimeOfDay(hour: 8, minute: 0));
            if (t != null) s.setBriefing(mTime: hmKey(t.hour, t.minute));
          },
        ),
      SwitchListTile(
        secondary: const Text('🌙', style: TextStyle(fontSize: 22)),
        title: Text(context.t('evening_review')),
        subtitle: Text(s.eveningReview ? context.tr('every_day_at', {'t': context.timeOfHm(s.eveningTime)}) : context.t('off')),
        value: s.eveningReview,
        onChanged: (v) => s.setBriefing(evening: v),
      ),
      if (s.eveningReview)
        OptionTile(
          icon: Icons.schedule_rounded,
          title: context.t('review_time'),
          trailing: Text(context.timeOfHm(s.eveningTime), style: context.tt.labelLarge),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: parseHm(s.eveningTime) ?? const TimeOfDay(hour: 21, minute: 0));
            if (t != null) s.setBriefing(eTime: hmKey(t.hour, t.minute));
          },
        ),
      OptionTile(
        icon: Icons.notifications_active_outlined,
        title: context.t('test_notification'),
        onTap: () => NotificationService.instance.showNow('DailyHub', context.t('test_notification_body')),
      ),
    ]);
  }
}

/// Name & phone (shown to people you share with).
class ProfileScreen extends StatefulWidget {
  final bool isSetup;
  const ProfileScreen({super.key, this.isSetup = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DbService.instance.getProfile().then((p) {
      if (!mounted) return;
      setState(() {
        _name.text = str(p?['name']).isNotEmpty ? str(p?['name']) : (FirebaseAuth.instance.currentUser?.displayName ?? '');
        _phone.text = str(p?['phone']);
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showToast(context, context.t('enter_name'));
      return;
    }
    await DbService.instance.saveProfile(_name.text.trim(), _phone.text.trim());
    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(_name.text.trim());
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, context.t('saved'), icon: Icons.check_circle_rounded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('profile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.symmetric(horizontal: sidePad(context, maxWidth: 520), vertical: 16), children: [
              Center(child: InitialsAvatar(_name.text.isEmpty ? '?' : _name.text, size: 84, color: context.cs.primary)),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: context.t('full_name'), prefixIcon: const Icon(Icons.person_outline_rounded)),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: context.t('phone_optional'), prefixIcon: const Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 8),
              Text(FirebaseAuth.instance.currentUser?.email ?? '', style: context.tt.bodySmall),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: Text(context.t('save'))),
            ]),
    );
  }
}

/// Turn features on and off.
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final byGroup = <String, List<ModuleDef>>{};
    for (final m in Modules.toggleables) {
      byGroup.putIfAbsent(m.group, () => []).add(m);
    }
    return AppPage(
      title: context.t('manage_modules'),
      subtitle: context.t('manage_modules_sub'),
      slivers: [
        SliverToBoxAdapter(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in Modules.personas.keys)
              ActionChip(
                avatar: Text(switch (p) { 'student' => '🎓', 'work' => '💼', 'family' => '🏡', _ => '✈️' }),
                label: Text(context.tr('turn_on_x', {'x': context.t('persona_$p')})),
                onPressed: () => s.setModules({...s.modules, ...Modules.personas[p]!}),
              ),
          ]),
        ),
        for (final g in Modules.groups)
          if (byGroup[g] != null) ...[
            SliverToBoxAdapter(child: SectionTitle(context.t('grp_$g'))),
            SliverToBoxAdapter(
              child: GroupCard(children: [
                for (final m in byGroup[g]!)
                  SwitchListTile(
                    secondary: IconBadge(icon: m.icon, color: m.color, size: 36),
                    title: Text(context.t(m.labelKey)),
                    subtitle: Text(context.t(m.descKey)),
                    value: s.isOn(m.id),
                    onChanged: (v) => s.setModule(m.id, v),
                  ),
              ]),
            ),
          ],
      ],
    );
  }
}

/// Reorder and show/hide Home sections.
class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  static IconData _icon(String id) => switch (id) {
        HomeSections.capture => Icons.auto_awesome_rounded,
        HomeSections.agenda => Icons.today_rounded,
        HomeSections.habits => Icons.local_fire_department_rounded,
        HomeSections.money => Icons.account_balance_wallet_rounded,
        _ => Icons.upcoming_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final order = s.homeOrder;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('customize_home'))),
      body: ReorderableListView(
        padding: EdgeInsets.symmetric(horizontal: sidePad(context, maxWidth: 620), vertical: 12),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(context.t('customize_home_hint'), style: context.tt.bodySmall),
        ),
        onReorderItem: (a, b) {
          final list = List.of(order);
          final item = list.removeAt(a);
          list.insert(b.clamp(0, list.length), item);
          s.setHomeOrder(list);
        },
        children: [
          for (final id in order)
            Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: DhCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(children: [
                  Icon(_icon(id), color: context.cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.t('home_$id'), style: context.tt.titleSmall)),
                  Switch(value: !s.homeHidden.contains(id), onChanged: (v) => s.setHomeVisible(id, v)),
                  const Icon(Icons.drag_handle_rounded),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Searchable currency list.
class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});
  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final q = _q.toLowerCase();
    final list = Currencies.all
        .where((c) => q.isEmpty || c.code.toLowerCase().contains(q) || c.name.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('currency'))),
      body: ListView(padding: EdgeInsets.symmetric(horizontal: sidePad(context, maxWidth: 620), vertical: 8), children: [
        TextField(
          autofocus: false,
          decoration: InputDecoration(hintText: context.t('search_currency'), prefixIcon: const Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        const SizedBox(height: 8),
        Text(context.t('currency_hint'), style: context.tt.bodySmall),
        const SizedBox(height: 8),
        GroupCard(children: [
          for (final c in list)
            ListTile(
              leading: SizedBox(
                width: 48,
                child: Text(c.symbol.trim(), style: context.tt.titleMedium, textAlign: TextAlign.center),
              ),
              title: Text(c.name),
              subtitle: Text(c.code),
              trailing: s.currency == c.code ? Icon(Icons.check_circle_rounded, color: context.cs.primary) : null,
              onTap: () {
                s.setCurrency(c.code);
                Navigator.pop(context);
              },
            ),
        ]),
      ]),
    );
  }
}

/// Location-based weather or a chosen city.
class WeatherCityScreen extends StatefulWidget {
  const WeatherCityScreen({super.key});
  @override
  State<WeatherCityScreen> createState() => _WeatherCityScreenState();
}

class _WeatherCityScreenState extends State<WeatherCityScreen> {
  List<GeoPlace> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      final r = await WeatherService.instance.searchCity(q);
      if (mounted) {
        setState(() {
          _results = r;
          _searching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('weather'))),
      body: ListView(padding: EdgeInsets.symmetric(horizontal: sidePad(context, maxWidth: 620), vertical: 8), children: [
        GroupCard(children: [
          SwitchListTile(
            secondary: const Icon(Icons.my_location_rounded),
            title: Text(context.t('wx_use_location')),
            subtitle: Text(context.t('wx_use_location_sub')),
            value: s.weatherUseLocation,
            onChanged: (v) async {
              if (v) {
                final ok = await LocationService.instance.request();
                if (!ok) {
                  if (context.mounted) showToast(context, context.t('location_denied'));
                  return;
                }
              }
              s.setWeather(useLocation: v);
              WeatherService.instance.clear();
            },
          ),
        ]),
        SectionTitle(context.t('wx_city')),
        if (s.weatherCity.isNotEmpty)
          DhCard(
            child: Row(children: [
              const Icon(Icons.place_rounded),
              const SizedBox(width: 10),
              Expanded(child: Text(s.weatherCity, style: context.tt.titleSmall)),
              Icon(Icons.check_circle_rounded, color: context.cs.primary),
            ]),
          ),
        TextField(
          decoration: InputDecoration(hintText: context.t('search_city'), prefixIcon: const Icon(Icons.search_rounded)),
          onChanged: _search,
        ),
        if (_searching) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        for (final p in _results)
          ListTile(
            leading: const Icon(Icons.location_city_rounded),
            title: Text(p.name),
            subtitle: Text(p.label),
            onTap: () {
              s.setWeather(city: p.label, lat: p.lat, lng: p.lng, useLocation: false);
              WeatherService.instance.clear();
              Navigator.pop(context);
            },
          ),
      ]),
    );
  }
}

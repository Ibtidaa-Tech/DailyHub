import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/db_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../ui/brand.dart';
import '../../ui/kit.dart';
import '../hub/modules.dart';
import '../settings/settings_screen.dart';

/// Four short steps: name → who you are → your toolkit → permissions.
/// Everything can be changed later in Settings.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  final _name = TextEditingController();
  int _step = 0;
  final Set<String> _personas = {};
  late Set<String> _modules = {...Modules.baseline};
  bool _notifAsked = false;
  bool _notifOk = false;
  bool _locAsked = false;
  bool _locOk = false;
  bool _saving = false;

  static const _steps = 4;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    _name.text = u?.displayName ?? '';
    DbService.instance.getProfile().then((p) {
      if (!mounted) return;
      final n = str(p?['name']);
      if (n.isNotEmpty && _name.text.isEmpty) setState(() => _name.text = n);
    });
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _page.animateToPage(step, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _next() {
    if (_step == 0 && _name.text.trim().isEmpty) {
      showToast(context, context.t('enter_name'));
      return;
    }
    if (_step == 1) _modules = Modules.forPersonas(_personas);
    if (_step < _steps - 1) {
      _go(_step + 1);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final s = context.read<AppSettings>();
    final name = _name.text.trim();
    try {
      final p = await DbService.instance.getProfile();
      await DbService.instance.saveProfile(name, str(p?['phone']));
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
    } catch (_) {}
    s.setModules({..._modules, ...ModuleDefaults.alwaysOn});
    if (_locOk) s.setWeather(useLocation: true);
    s.setOnboarded(true);
  }

  @override
  Widget build(BuildContext context) {
    final pad = sidePad(context, maxWidth: 560);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
            child: Row(children: [
              if (_step > 0)
                IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _go(_step - 1))
              else
                const SizedBox(width: 48),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < _steps; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _step ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i <= _step ? context.cs.primary : context.tokens.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ]),
              ),
              const _LangToggle(),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _pageWrap(pad, _welcome()),
                _pageWrap(pad, _personaStep()),
                _pageWrap(pad, _modulesStep()),
                _pageWrap(pad, _permissionsStep()),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 16),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _next,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_step == _steps - 1 ? context.t('start_using') : context.t('continue'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pageWrap(double pad, Widget child) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
        child: child,
      );

  Widget _title(String t, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: context.tt.headlineMedium),
        const SizedBox(height: 6),
        Text(sub, style: context.tt.bodyLarge?.copyWith(color: context.tokens.textMuted)),
        const SizedBox(height: 22),
      ]);

  Widget _welcome() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      const BrandMark(size: 72),
      const SizedBox(height: 24),
      _title(context.t('ob_welcome'), context.t('ob_welcome_sub')),
      for (final (icon, key, color) in [
        (Icons.check_circle_rounded, 'ob_point_plan', AppColors.mTasks),
        (Icons.account_balance_wallet_rounded, 'ob_point_money', AppColors.mMoney),
        (Icons.local_fire_department_rounded, 'ob_point_habits', AppColors.mHabits),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            IconBadge(icon: icon, color: color, size: 34),
            const SizedBox(width: 12),
            Expanded(child: Text(context.t(key), style: context.tt.bodyMedium)),
          ]),
        ),
      const SizedBox(height: 18),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _next(),
        decoration: InputDecoration(
          labelText: context.t('ob_your_name'),
          prefixIcon: const Icon(Icons.waving_hand_outlined),
        ),
      ),
    ]);
  }

  Widget _personaStep() {
    const items = [
      ('student', '🎓'),
      ('work', '💼'),
      ('family', '🏡'),
      ('travel', '✈️'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context.t('ob_who'), context.t('ob_who_sub')),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (id, emoji) in items)
            SizedBox(
              width: w,
              child: _SelectCard(
                selected: _personas.contains(id),
                onTap: () => setState(() => _personas.contains(id) ? _personas.remove(id) : _personas.add(id)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 10),
                  Text(context.t('persona_$id'), style: context.tt.titleSmall),
                  const SizedBox(height: 2),
                  Text(context.t('persona_${id}_sub'), style: context.tt.bodySmall, maxLines: 2),
                ]),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 14),
      Text(context.t('ob_who_hint'), style: context.tt.bodySmall),
    ]);
  }

  Widget _modulesStep() {
    final list = Modules.toggleables;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context.t('ob_toolkit'), context.t('ob_toolkit_sub')),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 480 ? 3 : 2;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final m in list)
            SizedBox(
              width: w,
              child: _SelectCard(
                selected: _modules.contains(m.id),
                padding: const EdgeInsets.all(12),
                onTap: () => setState(() => _modules.contains(m.id) ? _modules.remove(m.id) : _modules.add(m.id)),
                child: Row(children: [
                  IconBadge(icon: m.icon, color: m.color, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.t(m.labelKey),
                        style: context.tt.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 14),
      Text(context.t('ob_toolkit_hint'), style: context.tt.bodySmall),
    ]);
  }

  Widget _permissionsStep() {
    final s = context.watch<AppSettings>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(context.t('ob_setup'), context.t('ob_setup_sub')),
      if (!kIsWeb)
        _PermTile(
          icon: Icons.notifications_active_rounded,
          color: AppColors.mReminders,
          title: context.t('ob_notif'),
          subtitle: context.t('ob_notif_sub'),
          done: _notifOk,
          asked: _notifAsked,
          onTap: () async {
            final ok = await NotificationService.instance.requestPermissions();
            if (!mounted) return;
            setState(() {
              _notifAsked = true;
              _notifOk = ok;
            });
          },
        ),
      _PermTile(
        icon: Icons.wb_sunny_rounded,
        color: AppColors.mCountdown,
        title: context.t('ob_weather'),
        subtitle: context.t('ob_weather_sub'),
        done: _locOk || s.weatherLat != null,
        asked: _locAsked,
        onTap: () async {
          final ok = await LocationService.instance.request();
          if (!mounted) return;
          setState(() {
            _locAsked = true;
            _locOk = ok;
          });
          if (!ok) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const WeatherCityScreen()));
          }
        },
      ),
      const SizedBox(height: 8),
      GroupCard(children: [
        OptionTile(
          icon: Icons.payments_outlined,
          color: AppColors.mMoney,
          title: context.t('currency'),
          subtitle: '${Money.current.symbol.trim()}  ${Money.current.name}',
          trailing: Text(context.t('change'), style: TextStyle(color: context.cs.primary, fontWeight: FontWeight.w600)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CurrencyScreen())),
        ),
        if (!kIsWeb)
          SwitchListTile(
            secondary: const Text('☀️', style: TextStyle(fontSize: 22)),
            title: Text(context.t('morning_briefing')),
            subtitle: Text(context.tr('ob_morning_sub', {'t': context.timeOfHm(s.morningTime)})),
            value: s.morningBriefing,
            onChanged: (v) => s.setBriefing(morning: v),
          ),
        if (!kIsWeb)
          SwitchListTile(
            secondary: const Text('🌙', style: TextStyle(fontSize: 22)),
            title: Text(context.t('evening_review')),
            subtitle: Text(context.tr('ob_evening_sub', {'t': context.timeOfHm(s.eveningTime)})),
            value: s.eveningReview,
            onChanged: (v) => s.setBriefing(evening: v),
          ),
      ]),
    ]);
  }
}

class _SelectCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;
  const _SelectCard({required this.selected, required this.onTap, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tk = context.tokens;
    return Material(
      color: selected ? tk.tint(cs.primary) : tk.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? cs.primary : tk.border, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Stack(children: [
          Padding(padding: padding, child: child),
          if (selected)
            Positioned(
              top: 8,
              right: 8,
              child: Icon(Icons.check_circle_rounded, size: 20, color: cs.primary),
            ),
        ]),
      ),
    );
  }
}

class _PermTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool done;
  final bool asked;
  final VoidCallback onTap;
  const _PermTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.asked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DhCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        IconBadge(icon: icon, color: color, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.tt.titleSmall),
            Text(subtitle, style: context.tt.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        done
            ? Icon(Icons.check_circle_rounded, color: context.tokens.success)
            : FilledButton.tonal(onPressed: onTap, child: Text(context.t(asked ? 'retry' : 'allow'))),
      ]),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    return TextButton(
      onPressed: () => s.setLang(s.lang == 'hi' ? 'en' : 'hi'),
      child: Text(s.lang == 'hi' ? 'English' : 'हिन्दी'),
    );
  }
}

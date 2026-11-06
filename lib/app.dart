import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/localization.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'core/workspace_provider.dart';
import 'data/extras_store.dart';
import 'data/life_store.dart';
import 'data/money_store.dart';
import 'data/plan_store.dart';
import 'data/prayer_store.dart';
import 'data/student_store.dart';
import 'data/shopping_store.dart';
import 'data/tracker_store.dart';
import 'data/trip_store.dart';
import 'data/work_store.dart';
import 'features/auth/auth_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/shell.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'services/db_service.dart';
import 'services/planner.dart';
import 'services/widget_bridge.dart';
import 'ui/brand.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

class DailyHubApp extends StatelessWidget {
  const DailyHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final accent = Accents.byId(s.accent);
    return LocaleScope(
      lang: s.lang,
      child: MaterialApp(
        title: 'DailyHub',
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: rootMessengerKey,
        themeMode: s.themeMode,
        theme: AppTheme.build(brightness: Brightness.light, accent: accent),
        darkTheme: AppTheme.build(brightness: Brightness.dark, accent: accent),
        // The session (data stores) wraps the Navigator, so every page and
        // bottom sheet can reach it.
        builder: (context, child) => _ErrorListener(child: SessionHost(child: child ?? const SizedBox.shrink())),
        home: const AuthGate(),
      ),
    );
  }
}

/// Shows write failures (e.g. no permission in a shared workspace) as toasts.
class _ErrorListener extends StatefulWidget {
  final Widget child;
  const _ErrorListener({required this.child});
  @override
  State<_ErrorListener> createState() => _ErrorListenerState();
}

class _ErrorListenerState extends State<_ErrorListener> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = DbService.instance.errors.listen((code) {
      if (!mounted) return;
      final lang = context.read<AppSettings>().lang;
      final msg = AppStrings.of(lang, code == 'permission-denied' ? 'err_permission' : 'err_write');
      rootMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Auth + session state shared with the whole app.
class SessionController extends ChangeNotifier {
  bool authKnown = false;
  User? user;
  bool prefsLoaded = false;
  bool disabled = false;

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

class _Session {
  final PlanStore plan = PlanStore();
  final MoneyStore money = MoneyStore();
  final NotesStore notes = NotesStore();
  final HabitsStore habits = HabitsStore();
  final StudentStore student = StudentStore();
  final TripStore trips = TripStore();
  final ShoppingStore shopping = ShoppingStore();
  final WorkStore work = WorkStore();
  final TrackerStore tracker = TrackerStore();
  final PrayerStore prayer;
  final ExtrasStore extras;
  final List<StreamSubscription<dynamic>> subs = [];
  Timer? prefsTimeout;

  _Session(AppSettings settings)
      : extras = ExtrasStore(settings),
        prayer = PrayerStore(settings);

  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    prefsTimeout?.cancel();
    plan.dispose();
    money.dispose();
    notes.dispose();
    habits.dispose();
    student.dispose();
    trips.dispose();
    shopping.dispose();
    work.dispose();
    tracker.dispose();
    prayer.dispose();
    extras.dispose();
  }
}

/// Owns everything that lives for one signed-in account: data stores,
/// settings sync, the notification planner and workspace switching.
class SessionHost extends StatefulWidget {
  final Widget child;
  const SessionHost({super.key, required this.child});
  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<SessionHost> {
  final SessionController _ctrl = SessionController();
  StreamSubscription<User?>? _authSub;
  _Session? _session;
  late final AppSettings _settings;
  late final WorkspaceProvider _ws;
  String? _wsUid;

  @override
  void initState() {
    super.initState();
    _settings = context.read<AppSettings>();
    _ws = context.read<WorkspaceProvider>();
    _ws.addListener(_onWorkspace);
    _authSub = AuthService().authState.listen(_onUser);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _widgetDebounce?.cancel();
    _settings.removeListener(_feedWidget);
    _ws.removeListener(_onWorkspace);
    _session?.dispose();
    NotificationPlanner.instance.stop();
    _ctrl.dispose();
    super.dispose();
  }

  void _onUser(User? u) {
    final sameUser = _ctrl.authKnown && u?.uid == _ctrl.user?.uid;
    if (sameUser) {
      if (u != null) _ctrl._set(() => _ctrl.user = u);
      return;
    }
    // Account changed: tear down the old session first.
    final hadUser = _ctrl.user != null;
    _widgetDebounce?.cancel();
    _settings.removeListener(_feedWidget);
    _session?.dispose();
    _session = null;
    NotificationPlanner.instance.stop();
    if (hadUser) {
      WidgetBridge.instance.clear();
      NotificationPlanner.instance.clearAll();
      DbService.instance.reset();
      _settings.resetAccountState();
      rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    if (u == null) {
      setState(() {
        _ctrl
          ..authKnown = true
          ..user = null
          ..prefsLoaded = false
          ..disabled = false;
      });
      _ctrl._set(() {});
      return;
    }
    _start(u);
  }

  Timer? _widgetDebounce;

  /// Keeps the Android home-screen widget in step with today's data.
  void _feedWidget() {
    if (!WidgetBridge.instance.supported) return;
    _widgetDebounce?.cancel();
    _widgetDebounce = Timer(const Duration(milliseconds: 900), () {
      final s = _session;
      if (s == null || !mounted) return;
      WidgetBridge.instance.push(
        lang: _settings.lang,
        plan: s.plan,
        money: s.money,
        habits: s.habits,
        extras: s.extras,
        moneyOn: _settings.isOn('money'),
        habitsOn: _settings.isOn('habits'),
      );
    });
  }

  void _start(User u) {
    final db = DbService.instance;
    _ws.resetToOwn();
    db.activeWorkspaceUid = _ws.ownUid;
    _wsUid = _ws.workspaceUid;

    final s = _Session(_settings);
    _session = s;
    _ctrl
      ..authKnown = true
      ..user = u
      ..prefsLoaded = false
      ..disabled = false;

    _settings.onSyncedChange = (m) => db.updateNode('prefs', m);
    s.subs.add(db.watch('prefs').listen((p) {
      _settings.applyRemote(p);
      if (!_ctrl.prefsLoaded) _ctrl._set(() => _ctrl.prefsLoaded = true);
    }));
    s.prefsTimeout = Timer(const Duration(seconds: 5), () {
      if (!_ctrl.prefsLoaded) _ctrl._set(() => _ctrl.prefsLoaded = true);
    });
    s.subs.add(db.watch('profile').listen((p) {
      final d = p?['disabled'] == true;
      if (d != _ctrl.disabled) _ctrl._set(() => _ctrl.disabled = d);
    }));
    NotificationPlanner.instance.start(_settings);
    s.plan.addListener(_feedWidget);
    s.money.addListener(_feedWidget);
    s.habits.addListener(_feedWidget);
    _settings.addListener(_feedWidget);
    _feedWidget();
    if (u.email != null) {
      final escaped = u.email!.toLowerCase().replaceAll('.', ',');
      db.ref('emailToUid/$escaped').set({'uid': u.uid, 'name': u.displayName ?? u.email}).catchError((_) {});
    }
    if (mounted) setState(() {});
    _ctrl._set(() {});
  }

  void _onWorkspace() {
    if (_ws.workspaceUid == _wsUid) return;
    _wsUid = _ws.workspaceUid;
    DbService.instance.activeWorkspaceUid = _ws.workspaceUid;
    _session?.plan.bind();
    _session?.trips.bind();
    _session?.shopping.bind();
    _session?.extras.bind();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return ChangeNotifierProvider.value(value: _ctrl, child: widget.child);
    }
    return MultiProvider(
      key: ValueKey(_ctrl.user?.uid),
      providers: [
        ChangeNotifierProvider.value(value: _ctrl),
        ChangeNotifierProvider.value(value: s.plan),
        ChangeNotifierProvider.value(value: s.money),
        ChangeNotifierProvider.value(value: s.notes),
        ChangeNotifierProvider.value(value: s.habits),
        ChangeNotifierProvider.value(value: s.student),
        ChangeNotifierProvider.value(value: s.trips),
        ChangeNotifierProvider.value(value: s.shopping),
        ChangeNotifierProvider.value(value: s.work),
        ChangeNotifierProvider.value(value: s.tracker),
        ChangeNotifierProvider.value(value: s.prayer),
        ChangeNotifierProvider.value(value: s.extras),
      ],
      child: widget.child,
    );
  }
}

/// Decides what the first screen is: splash, sign-in, onboarding or the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final settings = context.watch<AppSettings>();
    Widget child;
    if (!session.authKnown) {
      child = const SplashView();
    } else if (session.user == null) {
      child = const AuthScreen();
    } else if (session.disabled) {
      child = const _DisabledView();
    } else if (!settings.onboarded && !session.prefsLoaded) {
      child = const SplashView();
    } else if (!settings.onboarded) {
      child = OnboardingScreen(key: ValueKey('onb_${session.user!.uid}'));
    } else {
      child = LockGate(key: ValueKey('lock_${session.user!.uid}'), child: const HomeShell());
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child);
  }
}

class _DisabledView extends StatelessWidget {
  const _DisabledView();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.block_rounded, size: 56, color: context.tokens.danger),
            const SizedBox(height: 16),
            Text(context.t('account_disabled'), style: context.tt.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(context.t('account_disabled_msg'),
                textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: context.tokens.textMuted)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => AuthService().signOut(), child: Text(context.t('sign_out'))),
          ]),
        ),
      ),
    );
  }
}

/// Optional fingerprint/PIN lock. Re-locks after a minute in the background.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _busy = false;
  DateTime? _pausedAt;

  bool get _enabled => context.read<AppSettings>().appLock && AppLockService.instance.supported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_enabled) {
        _unlock();
      } else {
        setState(() => _unlocked = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (_enabled && _unlocked && away.inSeconds >= 60) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_busy) return;
    _busy = true;
    final ok = await AppLockService.instance.authenticate(context.t('lock_reason'));
    _busy = false;
    if (mounted) setState(() => _unlocked = ok);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<AppSettings>().appLock && AppLockService.instance.supported;
    if (!enabled || _unlocked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(size: 76),
            const SizedBox(height: 22),
            Text(context.t('locked_title'), style: context.tt.headlineSmall),
            const SizedBox(height: 6),
            Text(context.t('locked_msg'), style: context.tt.bodyMedium?.copyWith(color: context.tokens.textMuted)),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _unlock,
              icon: const Icon(Icons.fingerprint_rounded),
              label: Text(context.t('unlock')),
            ),
          ]),
        ),
      ),
    );
  }
}

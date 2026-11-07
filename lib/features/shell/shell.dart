import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' show NotificationResponse;
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/workspace_provider.dart';
import '../../data/whereabouts_store.dart';
import '../../services/admin_service.dart';
import '../../services/db_service.dart';
import '../../services/notification_service.dart';
import '../../services/planner.dart';
import '../../services/update_service.dart';
import '../../ui/brand.dart';
import '../../widgets/update_dialog.dart';
import '../capture/add_sheet.dart';
import '../habits/habits_screen.dart';
import '../home/home_screen.dart';
import '../hub/hub_screen.dart';
import '../money/bills_screen.dart';
import '../money/ledger_screen.dart';
import '../money/money_screen.dart';
import '../notes/notes_screen.dart';
import '../plan/plan_screen.dart';
import '../tracker/tracker_screen.dart';

/// Which bottom tab is showing, and requests to jump between them.
class ShellController extends ChangeNotifier {
  String tab = 'home';
  PlanView? planRequest;

  void go(String t, {PlanView? planView}) {
    tab = t;
    if (planView != null) planRequest = planView;
    notifyListeners();
  }
}

class _TabDef {
  final String id;
  final IconData icon;
  final IconData selected;
  final String labelKey;
  const _TabDef(this.id, this.icon, this.selected, this.labelKey);
}

const _allTabs = {
  'home': _TabDef('home', Icons.home_outlined, Icons.home_rounded, 'tab_home'),
  'plan': _TabDef('plan', Icons.event_note_outlined, Icons.event_note_rounded, 'tab_plan'),
  'money': _TabDef('money', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'tab_money'),
  'notes': _TabDef('notes', Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, 'tab_notes'),
  'hub': _TabDef('hub', Icons.grid_view_outlined, Icons.grid_view_rounded, 'tab_hub'),
};

/// Main app frame: Home · Plan · (+) · Money · Hub on phones,
/// a navigation rail on tablets and desktop.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ShellController _ctrl = ShellController();
  StreamSubscription<NotificationResponse>? _tapSub;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launch = NotificationService.instance.launchResponse;
      if (launch != null) {
        NotificationService.instance.launchResponse = null;
        _handleTap(launch);
      }
      final info = await UpdateService.instance.check();
      if (info != null && mounted) await showUpdateDialog(context, info);

      // Today's whereabouts fix, if that module is on and today has none.
      // Uses the coarse, never-prompting call on purpose: opening the app
      // should never throw a permission dialog at you. Until permission is
      // granted from the Where was I screen this does nothing at all.
      if (!mounted) return;
      final settings = context.read<AppSettings>();
      if (settings.modules.contains('whereabouts')) {
        await context.read<WhereaboutsStore>().captureToday();
      }
    });
    _tapSub = NotificationService.instance.taps.listen(_handleTap);
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    _ctrl.removeListener(_onCtrl);
    _ctrl.dispose();
    super.dispose();
  }

  void _onCtrl() => setState(() {});

  void _handleTap(NotificationResponse r) {
    Map<String, dynamic> p = {};
    try {
      p = Map<String, dynamic>.from(jsonDecode(r.payload ?? '{}') as Map);
    } catch (_) {}
    final type = '${p['t'] ?? ''}';
    final id = '${p['id'] ?? ''}';
    if (r.actionId == 'done') {
      NotificationPlanner.instance.completeFromNotification(type, id);
      // Land where the thing just completed actually lives.
      if (type == 'tr') {
        _push(const TrackerScreen());
      } else {
        _ctrl.go('plan');
      }
      return;
    }
    switch (type) {
      case 'task':
      case 'rem':
      case 'brief_e':
        _ctrl.go('plan', planView: PlanView.today);
        break;
      case 'bill':
        _push(const BillsScreen());
        break;
      case 'debt':
        _push(const LedgerScreen());
        break;
      case 'habit':
        _push(const HabitsScreen());
        break;
      case 'tr':
        _push(const TrackerScreen());
        break;
      default:
        _ctrl.go('home');
    }
  }

  void _push(Widget page) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  List<String> _tabs(AppSettings s) => [
        'home',
        'plan',
        if (s.isOn('money')) 'money' else if (s.isOn('notes')) 'notes',
        'hub',
      ];

  Widget _page(String id) => switch (id) {
        'home' => const HomeScreen(),
        'plan' => const PlanScreen(),
        'money' => const MoneyScreen(),
        'notes' => const NotesScreen(isTab: true),
        _ => const HubScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final tabs = _tabs(s);
    if (!tabs.contains(_ctrl.tab)) _ctrl.tab = 'home';
    final index = tabs.indexOf(_ctrl.tab);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final extended = MediaQuery.sizeOf(context).width >= 1100;

    final body = Column(children: [
      const _BroadcastBanner(),
      const _WorkspaceBanner(),
      Expanded(
        child: IndexedStack(
          index: index,
          children: [for (final t in tabs) KeyedSubtree(key: ValueKey(t), child: _page(t))],
        ),
      ),
    ]);

    return ChangeNotifierProvider.value(
      value: _ctrl,
      child: PopScope(
        canPop: _ctrl.tab == 'home',
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _ctrl.go('home');
        },
        child: wide
            ? Scaffold(
                body: Row(children: [
                  _Rail(tabs: tabs, index: index, extended: extended, onTap: (i) => _ctrl.go(tabs[i])),
                  VerticalDivider(width: 1, color: context.tokens.border),
                  Expanded(child: body),
                ]),
              )
            : Scaffold(
                body: body,
                bottomNavigationBar: _BottomBar(
                  tabs: tabs,
                  index: index,
                  onTap: (i) => _ctrl.go(tabs[i]),
                  onAdd: () => showAddSheet(context),
                ),
              ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  const _BottomBar({required this.tabs, required this.index, required this.onTap, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final half = (tabs.length / 2).ceil();
    Widget item(int i) {
      final def = _allTabs[tabs[i]]!;
      final sel = i == index;
      return Expanded(
        child: InkResponse(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap(i);
          },
          radius: 36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? context.cs.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(sel ? def.selected : def.icon,
                    color: sel ? context.cs.primary : tk.textMuted, size: 24),
              ),
              const SizedBox(height: 3),
              Text(context.t(def.labelKey),
                  maxLines: 1,
                  style: context.tt.labelSmall?.copyWith(
                    color: sel ? context.cs.onSurface : tk.textMuted,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: 0,
                  )),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: tk.card,
        border: Border(top: BorderSide(color: tk.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(children: [
            for (var i = 0; i < half; i++) item(i),
            SizedBox(
              width: 72,
              child: Center(
                child: Semantics(
                  button: true,
                  label: context.t('add'),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onAdd();
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: context.cs.primary,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: context.cs.primary.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(Icons.add_rounded, color: context.cs.onPrimary, size: 30),
                    ),
                  ),
                ),
              ),
            ),
            for (var i = half; i < tabs.length; i++) item(i),
          ]),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final bool extended;
  final ValueChanged<int> onTap;
  const _Rail({required this.tabs, required this.index, required this.extended, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 220,
      selectedIndex: index,
      onDestinationSelected: onTap,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 18),
        child: Column(children: [
          extended ? const Wordmark(size: 34) : const BrandMark(size: 40),
          const SizedBox(height: 20),
          extended
              ? FilledButton.icon(
                  onPressed: () => showAddSheet(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.t('add_new')),
                )
              : FloatingActionButton(
                  heroTag: 'railAdd',
                  elevation: 0,
                  onPressed: () => showAddSheet(context),
                  child: const Icon(Icons.add_rounded),
                ),
        ]),
      ),
      destinations: [
        for (final t in tabs)
          NavigationRailDestination(
            icon: Icon(_allTabs[t]!.icon),
            selectedIcon: Icon(_allTabs[t]!.selected),
            label: Text(context.t(_allTabs[t]!.labelKey)),
          ),
      ],
    );
  }
}

/// Visible while viewing someone else's shared workspace.
class _WorkspaceBanner extends StatelessWidget {
  const _WorkspaceBanner();

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceProvider>();
    if (ws.isOwnWorkspace) return const SizedBox.shrink();
    return Material(
      color: context.cs.primary,
      child: InkWell(
        onTap: () {
          ws.resetToOwn();
          DbService.instance.activeWorkspaceUid = ws.ownUid;
        },
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(Icons.group_rounded, color: context.cs.onPrimary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('viewing_ws', {'name': ws.name, 'role': context.t('role_${ws.role}')}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.labelMedium?.copyWith(color: context.cs.onPrimary),
                ),
              ),
              Text(context.t('exit'), style: context.tt.labelMedium?.copyWith(color: context.cs.onPrimary)),
              Icon(Icons.close_rounded, color: context.cs.onPrimary, size: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Admin announcement shown to everyone until cleared (dismissible locally).
class _BroadcastBanner extends StatefulWidget {
  const _BroadcastBanner();
  @override
  State<_BroadcastBanner> createState() => _BroadcastBannerState();
}

class _BroadcastBannerState extends State<_BroadcastBanner> {
  String? _dismissedAt;
  late final Stream<Map<String, dynamic>?> _stream = AdminService.instance.broadcastStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _stream,
      builder: (context, snap) {
        final b = snap.data;
        if (b == null || '${b['title'] ?? ''}'.isEmpty) return const SizedBox.shrink();
        if (_dismissedAt == '${b['at']}') return const SizedBox.shrink();
        final tk = context.tokens;
        return Material(
          color: tk.tint(tk.warning),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(children: [
                Icon(Icons.campaign_rounded, color: tk.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b['title']}', style: context.tt.labelLarge),
                    if ('${b['message'] ?? ''}'.isNotEmpty) Text('${b['message']}', style: context.tt.bodySmall),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _dismissedAt = '${b['at']}'),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

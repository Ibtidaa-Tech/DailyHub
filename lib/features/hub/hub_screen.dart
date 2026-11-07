import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../screens/sharing_screen.dart';
import '../../services/admin_service.dart';
import '../../ui/kit.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/shell.dart';
import 'modules.dart';

/// Every enabled feature, grouped, searchable.
class HubScreen extends StatefulWidget {
  const HubScreen({super.key});
  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  String _q = '';
  late final Stream<bool> _admin = AdminService.instance.adminStream();

  void _open(ModuleDef m) {
    if (m.tab != null) {
      final shell = context.read<ShellController?>();
      if (shell != null) {
        shell.go(m.tab!);
        return;
      }
    }
    final page = m.page;
    if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return StreamBuilder<bool>(
      stream: _admin,
      builder: (context, snap) {
        final isAdmin = snap.data == true;
        final q = _q.toLowerCase();
        final visible = Modules.all.where((m) {
          if (!Modules.visible(m, settings.modules, isAdmin: isAdmin)) return false;
          if (q.isEmpty) return true;
          return context.t(m.labelKey).toLowerCase().contains(q) || context.t(m.descKey).toLowerCase().contains(q);
        }).toList();
        final groups = <String, List<ModuleDef>>{};
        for (final m in visible) {
          groups.putIfAbsent(m.group, () => []).add(m);
        }
        // Sorted by the translated label, not the id, so the order is right
        // in Hindi as well as English.
        for (final list in groups.values) {
          list.sort((a, b) => context
              .t(a.labelKey)
              .toLowerCase()
              .compareTo(context.t(b.labelKey).toLowerCase()));
        }
        return AppPage(
          title: context.t('tab_hub'),
          subtitle: context.t('hub_sub'),
          showBack: false,
          actions: [
            IconButton(
              tooltip: context.t('search'),
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
            IconButton(
              tooltip: context.t('settings'),
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
          slivers: [
            SliverToBoxAdapter(
              child: TextField(
                decoration: InputDecoration(
                  hintText: context.t('find_feature'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            for (final g in Modules.groups)
              if (groups[g] != null) ...[
                SliverToBoxAdapter(child: SectionTitle(context.t('grp_$g'))),
                SliverToBoxAdapter(child: _Grid(items: groups[g]!, onOpen: _open)),
              ],
            SliverToBoxAdapter(child: SectionTitle(context.t('more'))),
            SliverToBoxAdapter(
              child: GroupCard(children: [
                OptionTile(
                  icon: Icons.group_add_outlined,
                  color: AppColors.mTasks,
                  title: context.t('share_workspace'),
                  subtitle: context.t('share_workspace_sub'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SharingScreen())),
                ),
                OptionTile(
                  icon: Icons.dashboard_customize_outlined,
                  color: AppColors.mCalendar,
                  title: context.t('manage_modules'),
                  subtitle: context.t('manage_modules_sub'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModulesScreen())),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  final List<ModuleDef> items;
  final ValueChanged<ModuleDef> onOpen;
  const _Grid({required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 6 : (c.maxWidth >= 420 ? 5 : 4);
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in items)
          SizedBox(
            width: w,
            child: Tooltip(
              message: context.t(m.descKey),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onOpen(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Column(children: [
                    IconBadge(icon: m.icon, color: m.color, size: 52, radius: 16),
                    const SizedBox(height: 6),
                    // Two lines at a fixed height: "Lend & borrow" and
                    // "Priority matrix" were being cut to "Lend & b..." on a
                    // four-column phone grid. The fixed box keeps every tile
                    // the same height whether the label wraps or not.
                    SizedBox(
                      height: 30,
                      child: Text(context.t(m.labelKey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: context.tt.labelMedium
                              ?.copyWith(fontSize: 11, height: 1.2)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

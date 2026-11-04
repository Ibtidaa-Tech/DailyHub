import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../screens/admin_screen.dart';
import '../../screens/bookmarks_screen.dart';
import '../../screens/countdown_screen.dart';
import '../../screens/emergency_screen.dart';
import '../../screens/goals_screen.dart';
import '../../screens/insights_screen.dart';
import '../../screens/journal_screen.dart';
import '../../screens/packages_screen.dart';
import '../../screens/places_screen.dart';
import '../../screens/scanner_screen.dart';
import '../shopping/shopping_screen.dart';
import '../student/student_screen.dart';
import '../../screens/tools/tools_screen.dart';
import '../tracker/mentor_screen.dart';
import '../tracker/tracker_screen.dart';
import '../trips/trips_screen.dart';
import '../../screens/vault_screen.dart';
import '../work/work_screen.dart';
import '../habits/habits_screen.dart';
import '../money/accounts_screen.dart';
import '../money/bills_screen.dart';
import '../money/budgets_screen.dart';
import '../money/categories_screen.dart';
import '../money/ledger_screen.dart';
import '../money/reports_screen.dart';
import '../money/savings_screen.dart';
import '../notes/notes_screen.dart';
import '../plan/focus_screen.dart';
import '../plan/lists_screen.dart';
import '../plan/plan_screen.dart';
import '../plan/reminders_screen.dart';

/// Every feature of DailyHub, grouped for the Hub and onboarding.
class ModuleDef {
  final String id;
  final String labelKey;
  final String descKey;
  final IconData icon;
  final Color color;
  final String group;
  final String? parent; // follows the parent's on/off switch
  final String? tab; // opens a bottom tab instead of a new page
  final Widget Function()? page;
  final bool adminOnly;

  const ModuleDef({
    required this.id,
    required this.labelKey,
    required this.descKey,
    required this.icon,
    required this.color,
    required this.group,
    this.parent,
    this.tab,
    this.page,
    this.adminOnly = false,
  });

  bool get toggleable => parent == null && id != 'tasks' && !adminOnly;
}

class Modules {
  static const groups = ['plan', 'life', 'money', 'home', 'travel', 'study', 'work', 'safety', 'tools'];

  static final List<ModuleDef> all = [
    // PLAN
    const ModuleDef(id: 'tasks', labelKey: 'm_tasks', descKey: 'md_tasks', icon: Icons.check_circle_rounded, color: AppColors.mTasks, group: 'plan', tab: 'plan'),
    ModuleDef(id: 'reminders', labelKey: 'm_reminders', descKey: 'md_reminders', icon: Icons.notifications_active_rounded, color: AppColors.mReminders, group: 'plan', page: () => const RemindersScreen()),
    ModuleDef(id: 'calendar', labelKey: 'm_calendar', descKey: 'md_calendar', icon: Icons.calendar_month_rounded, color: AppColors.mCalendar, group: 'plan', parent: 'tasks', page: () => const PlanScreen(initialView: PlanView.calendar, standalone: true)),
    ModuleDef(id: 'lists', labelKey: 'm_lists', descKey: 'md_lists', icon: Icons.folder_rounded, color: AppColors.mTasks, group: 'plan', parent: 'tasks', page: () => const ListsScreen()),
    ModuleDef(id: 'focus', labelKey: 'm_focus', descKey: 'md_focus', icon: Icons.timer_rounded, color: AppColors.mHabits, group: 'plan', parent: 'tasks', page: () => const FocusScreen()),
    ModuleDef(id: 'matrix', labelKey: 'm_matrix', descKey: 'md_matrix', icon: Icons.grid_view_rounded, color: AppColors.mCalendar, group: 'plan', parent: 'tasks', page: () => const PlanScreen(initialView: PlanView.matrix, standalone: true)),
    // LIFE
    ModuleDef(id: 'notes', labelKey: 'm_notes', descKey: 'md_notes', icon: Icons.sticky_note_2_rounded, color: AppColors.mNotes, group: 'life', page: () => const NotesScreen()),
    ModuleDef(id: 'habits', labelKey: 'm_habits', descKey: 'md_habits', icon: Icons.local_fire_department_rounded, color: AppColors.mHabits, group: 'life', page: () => const HabitsScreen()),
    ModuleDef(id: 'tracker', labelKey: 'm_tracker', descKey: 'md_tracker', icon: Icons.fact_check_rounded, color: AppColors.mTracker, group: 'life', page: () => const TrackerScreen()),
    ModuleDef(id: 'mentor', labelKey: 'm_mentor', descKey: 'md_mentor', icon: Icons.school_rounded, color: AppColors.mStudy, group: 'life', parent: 'tracker', page: () => const MentorScreen()),
    ModuleDef(id: 'goals', labelKey: 'm_goals', descKey: 'md_goals', icon: Icons.flag_rounded, color: AppColors.mGoals, group: 'life', page: () => const GoalsScreen()),
    ModuleDef(id: 'journal', labelKey: 'm_journal', descKey: 'md_journal', icon: Icons.auto_stories_rounded, color: AppColors.mJournal, group: 'life', page: () => const JournalScreen()),
    ModuleDef(id: 'countdowns', labelKey: 'm_countdowns', descKey: 'md_countdowns', icon: Icons.hourglass_bottom_rounded, color: AppColors.mCountdown, group: 'life', page: () => const CountdownScreen()),
    ModuleDef(id: 'insights', labelKey: 'm_insights', descKey: 'md_insights', icon: Icons.insights_rounded, color: AppColors.mInsights, group: 'life', page: () => const InsightsScreen()),
    // MONEY
    const ModuleDef(id: 'money', labelKey: 'm_money', descKey: 'md_money', icon: Icons.account_balance_wallet_rounded, color: AppColors.mMoney, group: 'money', tab: 'money'),
    ModuleDef(id: 'accounts', labelKey: 'm_accounts', descKey: 'md_accounts', icon: Icons.account_balance_rounded, color: AppColors.mMoney, group: 'money', parent: 'money', page: () => const AccountsScreen()),
    ModuleDef(id: 'budgets', labelKey: 'm_budgets', descKey: 'md_budgets', icon: Icons.pie_chart_rounded, color: AppColors.mGoals, group: 'money', parent: 'money', page: () => const BudgetsScreen()),
    ModuleDef(id: 'bills', labelKey: 'm_bills', descKey: 'md_bills', icon: Icons.receipt_long_rounded, color: AppColors.mReminders, group: 'money', parent: 'money', page: () => const BillsScreen()),
    ModuleDef(id: 'ledger', labelKey: 'm_ledger', descKey: 'md_ledger', icon: Icons.handshake_rounded, color: AppColors.mJournal, group: 'money', parent: 'money', page: () => const LedgerScreen()),
    ModuleDef(id: 'savings', labelKey: 'm_savings', descKey: 'md_savings', icon: Icons.savings_rounded, color: AppColors.mTasks, group: 'money', parent: 'money', page: () => const SavingsScreen()),
    ModuleDef(id: 'reports', labelKey: 'm_reports', descKey: 'md_reports', icon: Icons.bar_chart_rounded, color: AppColors.mInsights, group: 'money', parent: 'money', page: () => const ReportsScreen()),
    ModuleDef(id: 'categories', labelKey: 'm_categories', descKey: 'md_categories', icon: Icons.category_rounded, color: AppColors.mWork, group: 'money', parent: 'money', page: () => const CategoriesScreen()),
    // HOME & FAMILY
    ModuleDef(id: 'shopping', labelKey: 'm_shopping', descKey: 'md_shopping', icon: Icons.shopping_cart_rounded, color: AppColors.mShopping, group: 'home', page: () => const ShoppingScreen()),
    ModuleDef(id: 'places', labelKey: 'm_places', descKey: 'md_places', icon: Icons.place_rounded, color: AppColors.mPlaces, group: 'home', page: () => const PlacesScreen()),
    // TRAVEL
    ModuleDef(id: 'trips', labelKey: 'm_trips', descKey: 'md_trips', icon: Icons.flight_takeoff_rounded, color: AppColors.mTrips, group: 'travel', page: () => const TripsScreen()),
    ModuleDef(id: 'packages', labelKey: 'm_packages', descKey: 'md_packages', icon: Icons.local_shipping_rounded, color: AppColors.mPackages, group: 'travel', page: () => const PackagesScreen()),
    // STUDY & WORK
    ModuleDef(id: 'student', labelKey: 'm_student', descKey: 'md_student', icon: Icons.school_rounded, color: AppColors.mStudy, group: 'study', page: () => const StudentScreen()),
    ModuleDef(id: 'work', labelKey: 'm_work', descKey: 'md_work', icon: Icons.work_rounded, color: AppColors.mWork, group: 'work', page: () => const WorkScreen()),
    ModuleDef(id: 'bookmarks', labelKey: 'm_bookmarks', descKey: 'md_bookmarks', icon: Icons.bookmark_rounded, color: AppColors.mBookmarks, group: 'work', page: () => const BookmarksScreen()),
    // SAFETY
    ModuleDef(id: 'vault', labelKey: 'm_vault', descKey: 'md_vault', icon: Icons.lock_rounded, color: AppColors.mVault, group: 'safety', page: () => const VaultScreen()),
    ModuleDef(id: 'emergency', labelKey: 'm_emergency', descKey: 'md_emergency', icon: Icons.emergency_rounded, color: AppColors.mEmergency, group: 'safety', page: () => const EmergencyScreen()),
    // TOOLS
    ModuleDef(id: 'tools', labelKey: 'm_tools', descKey: 'md_tools', icon: Icons.handyman_rounded, color: AppColors.mTools, group: 'tools', page: () => const ToolsScreen()),
    ModuleDef(id: 'scanner', labelKey: 'm_scanner', descKey: 'md_scanner', icon: Icons.qr_code_scanner_rounded, color: AppColors.mWork, group: 'tools', page: () => const ScannerScreen()),
    ModuleDef(id: 'admin', labelKey: 'm_admin', descKey: 'md_admin', icon: Icons.admin_panel_settings_rounded, color: AppColors.mEmergency, group: 'tools', adminOnly: true, page: () => const AdminScreen()),
  ];

  static ModuleDef? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<ModuleDef> get toggleables => all.where((m) => m.toggleable).toList();

  /// Personas offered during onboarding and what they switch on.
  static const Map<String, Set<String>> personas = {
    'student': {'student', 'countdowns', 'goals', 'journal'},
    'work': {'work', 'goals', 'bookmarks', 'insights'},
    'family': {'shopping', 'emergency', 'places'},
    'travel': {'trips', 'places', 'packages'},
  };

  static const Set<String> baseline = {'tasks', 'reminders', 'notes', 'habits', 'money', 'settings'};

  static Set<String> forPersonas(Set<String> chosen) {
    final out = {...baseline};
    for (final p in chosen) {
      out.addAll(personas[p] ?? const {});
    }
    return out;
  }

  /// Whether a module is visible given the user's switches.
  static bool visible(ModuleDef m, Set<String> enabled, {bool isAdmin = false}) {
    if (m.adminOnly) return isAdmin;
    if (m.id == 'tasks') return true;
    if (m.parent != null) return m.parent == 'tasks' || enabled.contains(m.parent);
    return enabled.contains(m.id);
  }
}

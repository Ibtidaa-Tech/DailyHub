import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../ui/kit.dart';
import '../countdown_screen.dart';
import '../scanner_screen.dart';
import 'calculator_screen.dart';
import 'converter_screen.dart';
import 'date_tools_screen.dart';
import 'finance_tools_screen.dart';
import 'stopwatch_screen.dart';

/// Tools hub — the small utilities that make DailyHub useful even when
/// you're not managing your day. Laid out as the same icon grid as the Hub,
/// so the two feel like one place.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <_Tool>[
      _Tool(Icons.calculate_rounded, 'tool_calc', 'tool_calc_sub',
          AppColors.mTasks, () => const CalculatorScreen()),
      _Tool(Icons.straighten_rounded, 'tool_convert', 'tool_convert_sub',
          AppColors.mTools, () => const ConverterScreen()),
      _Tool(Icons.account_balance_wallet_rounded, 'tool_money', 'tool_money_sub',
          AppColors.mMoney, () => const FinanceToolsScreen()),
      _Tool(Icons.event_note_rounded, 'tool_date', 'tool_date_sub',
          AppColors.mCalendar, () => const DateToolsScreen()),
      _Tool(Icons.timer_rounded, 'tool_time', 'tool_time_sub',
          AppColors.mHabits, () => const StopwatchScreen()),
      _Tool(Icons.hourglass_bottom_rounded, 'm_countdowns', 'md_countdowns',
          AppColors.mCountdown, () => const CountdownScreen()),
      _Tool(Icons.qr_code_scanner_rounded, 'm_scanner', 'md_scanner',
          AppColors.mWork, () => const ScannerScreen()),
    ];

    return AppPage(
      title: context.t('m_tools'),
      subtitle: context.t('tools_sub'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Grid(items: tools),
          ),
        ),
      ],
    );
  }
}

class _Tool {
  final IconData icon;
  final String labelKey;
  final String descKey;
  final Color color;
  final Widget Function() page;
  const _Tool(this.icon, this.labelKey, this.descKey, this.color, this.page);
}

/// Same visual language as the Hub grid: a tinted icon badge with a short
/// label, four to six across depending on the width available.
class _Grid extends StatelessWidget {
  final List<_Tool> items;
  const _Grid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 6 : (c.maxWidth >= 420 ? 5 : 4);
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in items)
          SizedBox(
            width: w,
            child: Tooltip(
              message: context.t(t.descKey),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => t.page())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Column(children: [
                    IconBadge(icon: t.icon, color: t.color, size: 52, radius: 16),
                    const SizedBox(height: 6),
                    Text(context.t(t.labelKey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.tt.labelMedium),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

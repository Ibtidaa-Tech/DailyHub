import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../ui/kit.dart';

/// Money calculators: EMI, GST, tip & split, discount and plain percentage.
///
/// Every amount goes through [Money.format] so it follows whichever currency
/// the user picked, and every division is guarded — a NaN or an Infinity
/// reaching `toStringAsFixed` would throw rather than just look wrong.
class FinanceToolsScreen extends StatefulWidget {
  const FinanceToolsScreen({super.key});

  @override
  State<FinanceToolsScreen> createState() => _FinanceToolsScreenState();
}

/// Money, or a dash when the inputs don't make a real number.
String _money(double v) => v.isFinite ? Money.format(v) : '—';

/// Percentage, or a dash. Never calls toStringAsFixed on NaN/Infinity.
String _pct(double v) => v.isFinite ? '${v.toStringAsFixed(2)}%' : '—';

class _FinanceToolsScreenState extends State<FinanceToolsScreen> {
  int _tab = 0;

  final _principal = TextEditingController(text: '500000');
  final _rate = TextEditingController(text: '9');
  final _years = TextEditingController(text: '5');
  final _gstAmount = TextEditingController(text: '1000');
  final _bill = TextEditingController(text: '1000');
  final _price = TextEditingController(text: '2000');
  final _discount = TextEditingController(text: '25');
  final _valueA = TextEditingController(text: '25');
  final _valueB = TextEditingController(text: '200');

  double _gstRate = 18;
  bool _gstInclusive = false;
  double _tipPct = 10;
  int _people = 1;

  List<TextEditingController> get _controllers => [
        _principal, _rate, _years, _gstAmount, _bill,
        _price, _discount, _valueA, _valueB,
      ];

  @override
  void initState() {
    super.initState();
    // Everything recalculates as you type; there is no "calculate" button.
    for (final c in _controllers) {
      c.addListener(_onEdit);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(_onEdit);
      c.dispose();
    }
    super.dispose();
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  /// A non-negative, sanely bounded number from a text field.
  double _readNumber(TextEditingController c) {
    // `double? ?? 0` infers num, not double — the type is written out so the
    // clamped return below stays a double.
    final double v = double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;
    if (!v.isFinite || v < 0) return 0;
    return v > 1e12 ? 1e12 : v;
  }

  Widget _field(TextEditingController c, String labelKey,
      {bool money = false, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: context.tt.titleMedium
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        decoration: InputDecoration(
          labelText: context.t(labelKey),
          prefixText: money ? '${Money.symbol} ' : null,
          suffixText: suffix,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: context.t('tool_money'),
      subtitle: context.t('tool_money_sub'),
      maxWidth: 600,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChipRow<int>(
          items: [
            (0, context.t('fin_emi')),
            (1, context.t('fin_gst')),
            (2, context.t('fin_tip')),
            (3, context.t('fin_discount')),
            (4, context.t('fin_percent')),
          ],
          value: _tab,
          onSelected: (v) => setState(() => _tab = v),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: switch (_tab) {
              1 => _gst(context),
              2 => _tip(context),
              3 => _discountTab(context),
              4 => _percent(context),
              _ => _emi(context),
            },
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- EMI

  Widget _emi(BuildContext context) {
    final p = _readNumber(_principal);
    final annualRate = _readNumber(_rate);
    final years = _readNumber(_years);
    final n = years * 12;
    final r = annualRate / 12 / 100;

    double emi = 0;
    if (p > 0 && n > 0) {
      if (r == 0) {
        // n > 0 here, so this division is safe.
        emi = p / n;
      } else {
        final growth = math.pow(1 + r, n).toDouble();
        final den = growth - 1;
        // den is only zero when r is zero, but a hand-typed rate can be odd.
        emi = den.abs() < 1e-12 ? 0.0 : p * r * growth / den;
      }
    }
    if (!emi.isFinite || emi <= 0) emi = 0;
    final total = emi * n;
    final interest = total - p;
    final ok = emi > 0 && total.isFinite;
    final interestShare = total > 0 ? (interest / total).clamp(0.0, 1.0) : 0.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(_principal, 'fin_loan_amount', money: true),
      _field(_rate, 'fin_rate_year', suffix: '%'),
      _field(_years, 'fin_tenure_years'),
      _ResultCard(
        label: context.t('fin_monthly_emi'),
        value: ok ? _money(emi) : '—',
        color: AppColors.mMoney,
        message: ok ? null : context.t('fin_fill_fields'),
        rows: ok
            ? [
                (context.t('fin_principal'), _money(p)),
                (context.t('fin_total_interest'), _money(interest)),
                (context.t('fin_total_payable'), _money(total)),
                (context.t('fin_months'), n.toStringAsFixed(0)),
              ]
            : const [],
        extra: ok
            ? ProgressBar(value: interestShare.toDouble(), color: AppColors.mMoney)
            : null,
      ),
    ]);
  }

  // ----------------------------------------------------------------- GST

  Widget _gst(BuildContext context) {
    final amount = _readNumber(_gstAmount);
    // Inclusive: the entered amount already contains the tax.
    final divisor = 100 + _gstRate;
    final base = _gstInclusive
        ? (divisor == 0 ? 0.0 : amount * 100 / divisor)
        : amount;
    final gst = base * _gstRate / 100;
    final total = base + gst;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(_gstAmount, 'amount', money: true),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in const [0.0, 5.0, 12.0, 18.0, 28.0])
            ChoiceChip(
              label: Text('${r.toStringAsFixed(0)}%'),
              selected: _gstRate == r,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _gstRate = r);
              },
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.t('fin_incl_gst'), style: context.tt.bodyMedium),
        value: _gstInclusive,
        onChanged: (v) => setState(() => _gstInclusive = v),
      ),
      const SizedBox(height: 4),
      _ResultCard(
        label: context.t('fin_total_with_gst'),
        value: _money(total),
        color: AppColors.mTools,
        rows: [
          (context.t('fin_base_amount'), _money(base)),
          (context.tr('fin_gst_at', {'r': _gstRate.toStringAsFixed(0)}), _money(gst)),
          (context.t('fin_cgst'), _money(gst / 2)),
          (context.t('fin_sgst'), _money(gst / 2)),
        ],
      ),
    ]);
  }

  // ----------------------------------------------------------- Tip/split

  Widget _tip(BuildContext context) {
    final bill = _readNumber(_bill);
    final tip = bill * _tipPct / 100;
    final total = bill + tip;
    final people = _people < 1 ? 1 : _people;
    final each = total / people; // people is never zero

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(_bill, 'fin_bill', money: true),
      Text(context.tr('fin_tip_pct', {'p': _tipPct.toStringAsFixed(0)}),
          style: context.tt.labelLarge),
      Slider(
        value: _tipPct,
        max: 30,
        divisions: 30,
        label: '${_tipPct.toStringAsFixed(0)}%',
        onChanged: (v) => setState(() => _tipPct = v),
      ),
      Row(children: [
        Expanded(child: Text(context.t('fin_split_between'), style: context.tt.bodyMedium)),
        IconButton(
          tooltip: context.t('fin_split_between'),
          icon: const Icon(Icons.remove_circle_outline_rounded),
          onPressed: _people <= 1
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _people--);
                },
        ),
        Text('$_people',
            style: context.tt.titleMedium
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        IconButton(
          tooltip: context.t('split'),
          icon: const Icon(Icons.add_circle_outline_rounded),
          onPressed: _people >= 99
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _people++);
                },
        ),
      ]),
      const SizedBox(height: 4),
      _ResultCard(
        label: people > 1 ? context.t('fin_each_pays') : context.t('fin_total'),
        value: _money(each),
        color: AppColors.mReminders,
        rows: [
          (context.t('fin_bill'), _money(bill)),
          (context.t('fin_tip'), _money(tip)),
          (context.t('fin_total'), _money(total)),
        ],
      ),
    ]);
  }

  // ------------------------------------------------------------ Discount

  Widget _discountTab(BuildContext context) {
    final price = _readNumber(_price);
    final pct = _readNumber(_discount);
    final saved = price * pct / 100;
    final finalPrice = price - saved;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(_price, 'fin_orig_price', money: true),
      _field(_discount, 'fin_discount_pct', suffix: '%'),
      _ResultCard(
        label: context.t('fin_you_pay'),
        value: _money(finalPrice),
        color: AppColors.mPlaces,
        rows: [
          (context.t('fin_original'), _money(price)),
          (context.t('fin_you_save'), _money(saved)),
        ],
      ),
    ]);
  }

  // ---------------------------------------------------------- Percentage

  Widget _percent(BuildContext context) {
    final a = _readNumber(_valueA);
    final b = _readNumber(_valueB);
    final aOfB = b * a / 100;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(_valueA, 'fin_value_a'),
      _field(_valueB, 'fin_value_b'),
      _ResultCard(
        label: context.t('fin_a_pct_of_b'),
        value: aOfB.isFinite ? aOfB.toStringAsFixed(2) : '—',
        color: AppColors.mCalendar,
        rows: [
          (context.t('fin_a_is_pct_of_b'), b == 0 ? '—' : _pct(a / b * 100)),
          (context.t('fin_increase_a_b'), a == 0 ? '—' : _pct((b - a) / a * 100)),
          (
            context.t('fin_a_plus_pct'),
            (a + aOfB).isFinite ? (a + aOfB).toStringAsFixed(2) : '—',
          ),
        ],
      ),
    ]);
  }
}

/// Tinted answer card shared by every tab, so they all read the same way.
class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> rows;
  final Color color;
  final String? message;
  final Widget? extra;
  const _ResultCard({
    required this.label,
    required this.value,
    required this.color,
    this.rows = const [],
    this.message,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return DhCard(
      color: tk.tint(color),
      borderColor: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label,
            textAlign: TextAlign.center,
            style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              maxLines: 1,
              style: context.tt.headlineMedium?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!,
              textAlign: TextAlign.center,
              style: context.tt.bodySmall?.copyWith(color: tk.textMuted)),
        ],
        if (extra != null) ...[
          const SizedBox(height: 14),
          extra!,
        ],
        if (rows.isNotEmpty) ...[
          Divider(height: 26, color: color.withValues(alpha: 0.25)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(r.$1,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodyMedium?.copyWith(color: tk.textMuted)),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(r.$2,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.labelLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

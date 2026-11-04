import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../ui/kit.dart';

/// One unit and its ratio to the category's base unit.
class _Unit {
  final String key; // translation key
  final double ratio;
  const _Unit(this.key, this.ratio);
}

/// A group of units that can be converted between each other.
class _Cat {
  final String key; // translation key
  final IconData icon;
  final List<_Unit> units;
  const _Cat(this.key, this.icon, this.units);
}

/// Unit converter. All categories use simple ratios to a base unit, except
/// temperature, which needs offsets and so is handled separately.
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  static const List<_Cat> _cats = [
    _Cat('uc_length', Icons.straighten_rounded, [
      _Unit('u_mm', 0.001),
      _Unit('u_cm', 0.01),
      _Unit('u_m', 1),
      _Unit('u_km', 1000),
      _Unit('u_in', 0.0254),
      _Unit('u_ft', 0.3048),
      _Unit('u_yd', 0.9144),
      _Unit('u_mi', 1609.344),
    ]),
    _Cat('uc_weight', Icons.monitor_weight_outlined, [
      _Unit('u_mg', 0.000001),
      _Unit('u_g', 0.001),
      _Unit('u_kg', 1),
      _Unit('u_tonne', 1000),
      _Unit('u_oz', 0.0283495),
      _Unit('u_lb', 0.453592),
    ]),
    _Cat('uc_volume', Icons.local_drink_outlined, [
      _Unit('u_ml', 0.001),
      _Unit('u_l', 1),
      _Unit('u_m3', 1000),
      _Unit('u_tsp', 0.00492892),
      _Unit('u_tbsp', 0.0147868),
      _Unit('u_cup', 0.24),
      _Unit('u_gal', 3.78541),
    ]),
    _Cat('uc_area', Icons.crop_square_rounded, [
      _Unit('u_m2', 1),
      _Unit('u_km2', 1000000),
      _Unit('u_ft2', 0.092903),
      _Unit('u_yd2', 0.836127),
      _Unit('u_acre', 4046.86),
      _Unit('u_hectare', 10000),
    ]),
    _Cat('uc_speed', Icons.speed_rounded, [
      _Unit('u_mps', 1),
      _Unit('u_kmph', 0.277778),
      _Unit('u_mph', 0.44704),
      _Unit('u_knot', 0.514444),
    ]),
    _Cat('uc_data', Icons.sd_storage_outlined, [
      _Unit('u_byte', 1),
      _Unit('u_kb', 1024),
      _Unit('u_mb', 1048576),
      _Unit('u_gb', 1073741824),
      _Unit('u_tb', 1099511627776),
    ]),
    _Cat('uc_time', Icons.schedule_rounded, [
      _Unit('u_sec', 1),
      _Unit('u_minute', 60),
      _Unit('u_hour', 3600),
      _Unit('u_day', 86400),
      _Unit('u_week', 604800),
    ]),
    // Ratios are unused here; temperature converts through Celsius instead.
    _Cat('uc_temp', Icons.thermostat_rounded, [
      _Unit('u_celsius', 1),
      _Unit('u_fahrenheit', 1),
      _Unit('u_kelvin', 1),
    ]),
  ];

  int _cat = 0;
  late String _from;
  late String _to;
  final _input = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _resetUnits();
    // Converting as you type means there's never a button to remember.
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  _Cat get _category => _cats[_cat];

  void _resetUnits() {
    final units = _category.units;
    _from = units.first.key;
    _to = units.length > 1 ? units[1].key : units.first.key;
  }

  double _ratioOf(String key) {
    for (final u in _category.units) {
      if (u.key == key) return u.ratio;
    }
    return 1;
  }

  double? get _output {
    final value = double.tryParse(_input.text.trim().replaceAll(',', ''));
    if (value == null || !value.isFinite) return null;
    if (_category.key == 'uc_temp') return _convertTemp(value, _from, _to);
    final fromRatio = _ratioOf(_from);
    final toRatio = _ratioOf(_to);
    // Every ratio above is a positive constant, but never divide blind.
    if (toRatio == 0) return null;
    final out = value * fromRatio / toRatio;
    return out.isFinite ? out : null;
  }

  static double _convertTemp(double v, String from, String to) {
    // Normalise to Celsius first, then out to the target.
    final celsius = switch (from) {
      'u_fahrenheit' => (v - 32) * 5 / 9,
      'u_kelvin' => v - 273.15,
      _ => v,
    };
    return switch (to) {
      'u_fahrenheit' => celsius * 9 / 5 + 32,
      'u_kelvin' => celsius + 273.15,
      _ => celsius,
    };
  }

  Future<void> _pickUnit(bool isFrom) async {
    final current = isFrom ? _from : _to;
    final picked = await showAppSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(ctx.t(isFrom ? 'from' : 'to'), subtitle: ctx.t(_category.key)),
          for (final u in _category.units)
            OptionTile(
              icon: u.key == current
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: u.key == current ? ctx.cs.primary : null,
              title: ctx.t(u.key),
              onTap: () => Navigator.pop(ctx, u.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _swap() {
    HapticFeedback.selectionClick();
    setState(() {
      final t = _from;
      _from = _to;
      _to = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final out = _output;
    const accent = AppColors.mTools;

    return AppPage(
      title: context.t('tool_convert'),
      subtitle: context.t('tool_convert_sub'),
      maxWidth: 600,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChipRow<int>(
          items: [for (var i = 0; i < _cats.length; i++) (i, context.t(_cats[i].key))],
          value: _cat,
          onSelected: (v) => setState(() {
            _cat = v;
            _resetUnits();
          }),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: DhCard(
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            child: Column(children: [
              TextField(
                controller: _input,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                textAlign: TextAlign.end,
                style: context.tt.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  labelText: context.t('conv_value'),
                  suffixText: context.t(_from),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FormFieldButton(
                    icon: _category.icon,
                    label: context.t('from'),
                    value: context.t(_from),
                    onTap: () => _pickUnit(true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: context.t('conv_swap'),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: _swap,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FormFieldButton(
                    icon: _category.icon,
                    label: context.t('to'),
                    value: context.t(_to),
                    onTap: () => _pickUnit(false),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: out == null
              ? EmptyView(
                  icon: Icons.straighten_rounded,
                  color: accent,
                  title: context.t('conv_value'),
                  message: context.t('conv_bad_value'),
                  compact: true,
                )
              : DhCard(
                  color: context.tokens.tint(accent),
                  borderColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                  child: Column(children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _fmt(out),
                        maxLines: 1,
                        style: context.tt.displaySmall?.copyWith(
                          color: accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(context.t(_to),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.bodyMedium
                            ?.copyWith(color: context.tokens.textMuted)),
                  ]),
                ),
        ),
      ],
    );
  }

  static String _fmt(double v) {
    if (!v.isFinite) return '—';
    if (v == v.roundToDouble() && v.abs() < 1e12) {
      return v.toStringAsFixed(0);
    }
    if (v.abs() >= 1e12 || (v.abs() < 0.0001 && v != 0)) {
      return v.toStringAsExponential(4);
    }
    return v
        .toStringAsFixed(6)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../services/location_service.dart';
import '../../services/weather_service.dart';
import '../../ui/kit.dart';
import '../settings/settings_screen.dart';

/// Live weather pill (Open-Meteo). Tap for today's details.
class WeatherChip extends StatefulWidget {
  const WeatherChip({super.key});

  static final ValueNotifier<int> _refreshTick = ValueNotifier(0);

  static Future<void> refresh(BuildContext context) async {
    WeatherService.instance.clear();
    _refreshTick.value++;
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  State<WeatherChip> createState() => _WeatherChipState();
}

class _WeatherChipState extends State<WeatherChip> {
  WeatherInfo? _w;
  bool _loading = true;
  bool _needsSetup = false;

  @override
  void initState() {
    super.initState();
    WeatherChip._refreshTick.addListener(_load);
    _w = WeatherService.instance.cached;
    _load();
  }

  @override
  void dispose() {
    WeatherChip._refreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<AppSettings>();
    final hasCity = s.weatherLat != null && s.weatherLng != null;
    final hasLoc = s.weatherUseLocation && await LocationService.instance.hasPermission();
    if (!hasCity && !hasLoc) {
      if (mounted) {
        setState(() {
          _needsSetup = true;
          _loading = false;
        });
      }
      return;
    }
    final w = await WeatherService.instance.current(
      useLocation: s.weatherUseLocation,
      cityLat: s.weatherLat,
      cityLng: s.weatherLng,
      cityName: s.weatherCity,
    );
    if (!mounted) return;
    setState(() {
      _w = w;
      _needsSetup = false;
      _loading = false;
    });
  }

  Future<void> _setup() async {
    final s = context.read<AppSettings>();
    final ok = await LocationService.instance.request();
    if (!mounted) return;
    if (ok) {
      s.setWeather(useLocation: true);
      _load();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WeatherCityScreen()));
  }

  void _details(WeatherInfo w) {
    showAppSheet(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(w.emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${w.temp.round()}°', style: ctx.tt.displaySmall),
                  Text(ctx.t(w.labelKey), style: ctx.tt.titleMedium),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: StatBlock(label: ctx.t('wx_feels'), value: '${w.feels.round()}°')),
              Expanded(child: StatBlock(label: ctx.t('wx_high_low'), value: '${w.max.round()}° / ${w.min.round()}°')),
              Expanded(child: StatBlock(label: ctx.t('wx_rain_chance'), value: '${w.rainChance}%')),
            ]),
            if (w.place.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(children: [
                Icon(Icons.place_outlined, size: 16, color: ctx.tokens.textMuted),
                const SizedBox(width: 4),
                Text(w.place, style: ctx.tt.bodySmall),
              ]),
            ],
            const SizedBox(height: 10),
            Text(ctx.t('wx_source'), style: ctx.tt.bodySmall?.copyWith(fontSize: 11)),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WeatherCityScreen()));
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(ctx.t('wx_settings')),
            ),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    Widget pill(Widget child, {VoidCallback? onTap}) => Material(
          color: tk.card,
          shape: StadiumBorder(side: BorderSide(color: tk.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), child: child),
          ),
        );
    if (_loading && _w == null) {
      return pill(Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: tk.textFaint)),
        const SizedBox(width: 8),
        Text(context.t('wx_loading'), style: context.tt.labelMedium?.copyWith(color: tk.textMuted)),
      ]));
    }
    if (_needsSetup) {
      return pill(
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('🌤️'),
          const SizedBox(width: 6),
          Text(context.t(kIsWeb ? 'wx_set_city' : 'wx_enable'), style: context.tt.labelMedium?.copyWith(color: context.cs.primary)),
        ]),
        onTap: _setup,
      );
    }
    final w = _w;
    if (w == null) return const SizedBox.shrink();
    return pill(
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(w.emoji),
        const SizedBox(width: 6),
        Text('${w.temp.round()}°', style: context.tt.labelLarge),
        const SizedBox(width: 6),
        Text(context.t(w.labelKey), style: context.tt.labelMedium?.copyWith(color: tk.textMuted)),
        if (w.place.isNotEmpty) ...[
          Text('  ·  ', style: context.tt.labelMedium?.copyWith(color: tk.textFaint)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(w.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.labelMedium?.copyWith(color: tk.textMuted)),
          ),
        ],
      ]),
      onTap: () => _details(w),
    );
  }
}

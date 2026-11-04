import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'location_service.dart';

/// Current weather from Open-Meteo — free, no API key, no sign-up.
/// Uses the phone's location (if allowed) or a city picked in Settings.
class WeatherInfo {
  final double temp;
  final double feels;
  final double max;
  final double min;
  final int code;
  final bool isDay;
  final int rainChance;
  final String place;
  final DateTime at;

  const WeatherInfo({
    required this.temp,
    required this.feels,
    required this.max,
    required this.min,
    required this.code,
    required this.isDay,
    required this.rainChance,
    required this.place,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'temp': temp, 'feels': feels, 'max': max, 'min': min, 'code': code,
        'isDay': isDay, 'rain': rainChance, 'place': place, 'at': at.toIso8601String(),
      };

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        temp: (j['temp'] as num).toDouble(),
        feels: (j['feels'] as num).toDouble(),
        max: (j['max'] as num).toDouble(),
        min: (j['min'] as num).toDouble(),
        code: (j['code'] as num).toInt(),
        isDay: j['isDay'] == true,
        rainChance: (j['rain'] as num?)?.toInt() ?? 0,
        place: (j['place'] ?? '').toString(),
        at: DateTime.tryParse('${j['at']}') ?? DateTime(2000),
      );

  /// WMO weather code → emoji.
  String get emoji {
    if (code == 0) return isDay ? '☀️' : '🌙';
    if (code <= 2) return isDay ? '🌤️' : '☁️';
    if (code == 3) return '☁️';
    if (code == 45 || code == 48) return '🌫️';
    if (code >= 51 && code <= 57) return '🌦️';
    if (code >= 61 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 77) return '❄️';
    if (code >= 80 && code <= 82) return '🌧️';
    if (code == 85 || code == 86) return '🌨️';
    if (code >= 95) return '⛈️';
    return '🌡️';
  }

  /// Translation key for the condition.
  String get labelKey {
    if (code == 0) return 'wx_clear';
    if (code <= 2) return 'wx_partly';
    if (code == 3) return 'wx_cloudy';
    if (code == 45 || code == 48) return 'wx_fog';
    if (code >= 51 && code <= 57) return 'wx_drizzle';
    if (code >= 61 && code <= 67) return 'wx_rain';
    if (code >= 71 && code <= 77) return 'wx_snow';
    if (code >= 80 && code <= 82) return 'wx_showers';
    if (code == 85 || code == 86) return 'wx_snow';
    if (code >= 95) return 'wx_storm';
    return 'wx_clear';
  }
}

class GeoPlace {
  final String name;
  final String region;
  final String country;
  final double lat;
  final double lng;
  const GeoPlace(this.name, this.region, this.country, this.lat, this.lng);
  String get label => [name, if (region.isNotEmpty && region != name) region, country]
      .where((e) => e.isNotEmpty)
      .join(', ');
}

class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const _cacheKey = 'dh_weather_cache';
  WeatherInfo? _cached;

  WeatherInfo? get cached => _cached;

  Future<WeatherInfo?> loadCached() async {
    if (_cached != null) return _cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) _cached = WeatherInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return _cached;
  }

  /// Fresh weather (cached for 30 minutes). Returns null when no location or
  /// city is available, or the network is down.
  Future<WeatherInfo?> current({
    required bool useLocation,
    double? cityLat,
    double? cityLng,
    String cityName = '',
    bool force = false,
  }) async {
    final c = _cached ?? await loadCached();
    if (!force && c != null && DateTime.now().difference(c.at).inMinutes < 30) return c;

    double? lat;
    double? lng;
    var place = cityName;
    if (useLocation) {
      final pos = await LocationService.instance.coarse();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
        place = await _reverse(lat, lng) ?? '';
      }
    }
    if (lat == null && cityLat != null && cityLng != null) {
      lat = cityLat;
      lng = cityLng;
      place = cityName;
    }
    if (lat == null || lng == null) return c;

    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast'
          '?latitude=${lat.toStringAsFixed(3)}&longitude=${lng.toStringAsFixed(3)}'
          '&current=temperature_2m,apparent_temperature,weather_code,is_day'
          '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
          '&timezone=auto&forecast_days=1');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return c;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final cur = j['current'] as Map<String, dynamic>;
      final daily = j['daily'] as Map<String, dynamic>?;
      double first(String k) {
        final l = daily?[k];
        if (l is List && l.isNotEmpty && l.first is num) return (l.first as num).toDouble();
        return 0;
      }

      final info = WeatherInfo(
        temp: (cur['temperature_2m'] as num).toDouble(),
        feels: (cur['apparent_temperature'] as num?)?.toDouble() ?? (cur['temperature_2m'] as num).toDouble(),
        max: first('temperature_2m_max'),
        min: first('temperature_2m_min'),
        code: (cur['weather_code'] as num?)?.toInt() ?? 0,
        isDay: (cur['is_day'] as num?)?.toInt() == 1,
        rainChance: first('precipitation_probability_max').round(),
        place: place,
        at: DateTime.now(),
      );
      _cached = info;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(info.toJson()));
      } catch (_) {}
      return info;
    } catch (e) {
      debugPrint('Weather fetch failed: $e');
      return c;
    }
  }

  Future<String?> _reverse(double lat, double lng) async {
    try {
      final uri = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client'
          '?latitude=$lat&longitude=$lng&localityLanguage=en');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final city = (j['city'] ?? '').toString();
      final loc = (j['locality'] ?? '').toString();
      return city.isNotEmpty ? city : loc;
    } catch (_) {
      return null;
    }
  }

  /// City search for the Settings picker.
  Future<List<GeoPlace>> searchCity(String q) async {
    if (q.trim().length < 2) return [];
    try {
      final uri = Uri.parse('https://geocoding-api.open-meteo.com/v1/search'
          '?name=${Uri.encodeQueryComponent(q.trim())}&count=8&language=en&format=json');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list = j['results'];
      if (list is! List) return [];
      return list.whereType<Map>().map((m) {
        return GeoPlace(
          (m['name'] ?? '').toString(),
          (m['admin1'] ?? '').toString(),
          (m['country'] ?? '').toString(),
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void clear() => _cached = null;
}

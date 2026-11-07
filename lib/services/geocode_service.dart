import 'dart:convert';

import 'package:http/http.dart' as http;

/// A human-readable name for a coordinate.
class PlaceName {
  /// The nearest thing to a street address the free tier gives us —
  /// "Andheri East, Mumbai".
  final String short;

  /// The same with region and country appended, for a subtitle.
  final String full;

  const PlaceName(this.short, this.full);

  bool get isEmpty => short.isEmpty;
}

/// Turns coordinates into a place name using BigDataCloud's client endpoint —
/// free, no API key, no sign-up, same service the weather card already uses.
///
/// Coordinates are a fine thing to store and a terrible thing to read, so
/// every screen that captures a location runs it through here before showing
/// it. If the lookup fails the caller keeps the coordinates and shows those;
/// losing the name is a cosmetic failure, not a lost location.
class GeocodeService {
  GeocodeService._();

  /// Repeat lookups of the same spot are common — reopening the editor,
  /// logging twice from a desk — so keep a few in memory. Rounded to ~100 m,
  /// which is well inside the resolution of any name we would show.
  static final Map<String, PlaceName> _cache = {};

  static String _key(double lat, double lng) =>
      '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  static Future<PlaceName?> describe(double lat, double lng) async {
    final k = _key(lat, lng);
    final hit = _cache[k];
    if (hit != null) return hit;
    try {
      final uri = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client'
          '?latitude=$lat&longitude=$lng&localityLanguage=en');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;

      String pick(String key) => (j[key] ?? '').toString().trim();
      final locality = pick('locality');
      final city = pick('city');
      final region = pick('principalSubdivision');
      final country = pick('countryName');

      // Locality is the neighbourhood, city the town. Both when they differ,
      // because "Andheri East" alone is meaningless to anyone outside Mumbai.
      final parts = <String>[];
      if (locality.isNotEmpty) parts.add(locality);
      if (city.isNotEmpty && city != locality) parts.add(city);
      final short = parts.join(', ');
      if (short.isEmpty) return null;

      final tail = <String>[short];
      if (region.isNotEmpty && region != city && region != locality) tail.add(region);
      if (country.isNotEmpty) tail.add(country);

      final out = PlaceName(short, tail.join(', '));
      _cache[k] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// What to show when there is no name: a tidy coordinate pair rather than
  /// fifteen decimal places of float noise.
  static String coords(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  /// Opens the coordinate in whatever maps app the phone has. Used instead of
  /// an embedded map so the app needs no Maps API key and no billing account.
  static Uri mapsUri(double lat, double lng, {String? label}) {
    final q = label == null || label.isEmpty
        ? '$lat,$lng'
        : '$lat,$lng(${Uri.encodeComponent(label)})';
    return Uri.parse('geo:$lat,$lng?q=$q');
  }

  static Uri mapsWebUri(double lat, double lng) =>
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
}

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// On-demand location for weather, places and the parking spot.
/// No background location — nothing runs when you aren't using the app.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  bool get supported => true;

  /// Whether location may be read without prompting.
  Future<bool> hasPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Asks for permission if needed. Returns true when granted.
  Future<bool> request() async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Fast, low-accuracy fix for weather. Never prompts.
  Future<Position?> coarse() async {
    try {
      if (!await hasPermission()) return null;
      if (!kIsWeb) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Coarse location failed: $e');
      return null;
    }
  }

  /// Returns a position, or null with a reason the caller can surface.
  Future<({Position? position, String? error})> current() async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        return (position: null, error: 'Location is switched off on this device');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return (position: null, error: 'Location permission was denied');
      }
      if (permission == LocationPermission.deniedForever) {
        return (
          position: null,
          error: 'Location permission is permanently denied — enable it in your device settings'
        );
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return (position: pos, error: null);
    } catch (e) {
      debugPrint('Location failed: $e');
      return (position: null, error: 'Could not get a location fix');
    }
  }

  static String mapsUrl(double lat, double lng) =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  static double distanceBetween(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
}

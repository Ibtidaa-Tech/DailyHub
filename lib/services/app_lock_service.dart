import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Optional fingerprint / face / device-PIN lock for the whole app.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  final LocalAuthentication _auth = LocalAuthentication();

  bool get supported => !kIsWeb;

  /// True when the device has a screen lock or biometrics set up.
  Future<bool> available() async {
    if (!supported) return false;
    try {
      return await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    if (!supported) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('App lock auth failed: $e');
      return false;
    }
  }
}

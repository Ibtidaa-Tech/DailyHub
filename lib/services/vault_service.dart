import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-only encrypted vault.
///
/// THIS DATA NEVER TOUCHES FIREBASE. That's the whole point: a synced
/// database means anyone who compromises the account sees plaintext ID
/// numbers and passwords, and — for Aadhaar specifically — storing it on a
/// server carries legal exposure under the Aadhaar Act. Everything here
/// lives in the OS keystore instead:
///
///   Android — EncryptedSharedPreferences, backed by the hardware keystore
///   iOS     — Keychain
///
/// The tradeoff you accepted: no cross-device sync, and uninstalling the app
/// destroys the vault. There is no recovery. That is the correct behaviour
/// for secrets, but it does mean users should keep their own backup of
/// anything irreplaceable.
class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  static const _documentsKey = 'vault_documents';
  static const _passwordsKey = 'vault_passwords';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final _auth = LocalAuthentication();

  /// The vault is mobile-only. Browser storage isn't a keystore, and
  /// pretending otherwise would be worse than not offering it.
  bool get supported => !kIsWeb;

  // ---------------------------------------------------------- unlocking

  Future<bool> canUseBiometrics() async {
    if (!supported) return false;
    try {
      final supportedDevice = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supportedDevice || canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Prompts for fingerprint/face, falling back to the device PIN or pattern.
  /// Returns false on cancel or failure — never throws at the caller.
  Future<bool> unlock() async {
    if (!supported) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock your DailyHub vault',
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN as a fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('Vault unlock failed: $e');
      return false;
    }
  }

  // ------------------------------------------------------------- reads

  Future<List<Map<String, dynamic>>> _read(String key) async {
    if (!supported) return [];
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Vault read failed: $e');
      return [];
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> items) async {
    if (!supported) return;
    await _storage.write(key: key, value: jsonEncode(items));
  }

  Future<List<Map<String, dynamic>>> documents() => _read(_documentsKey);
  Future<List<Map<String, dynamic>>> passwords() => _read(_passwordsKey);

  // ------------------------------------------------------------ writes

  Future<void> saveDocument(Map<String, dynamic> doc) async {
    final items = await documents();
    final id = doc['id'] as String?;
    if (id == null) {
      doc['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      items.add(doc);
    } else {
      final i = items.indexWhere((e) => e['id'] == id);
      if (i >= 0) {
        items[i] = doc;
      } else {
        items.add(doc);
      }
    }
    await _write(_documentsKey, items);
  }

  Future<void> deleteDocument(String id) async {
    final items = await documents()
      ..removeWhere((e) => e['id'] == id);
    await _write(_documentsKey, items);
  }

  Future<void> savePassword(Map<String, dynamic> entry) async {
    final items = await passwords();
    final id = entry['id'] as String?;
    if (id == null) {
      entry['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      items.add(entry);
    } else {
      final i = items.indexWhere((e) => e['id'] == id);
      if (i >= 0) {
        items[i] = entry;
      } else {
        items.add(entry);
      }
    }
    await _write(_passwordsKey, items);
  }

  Future<void> deletePassword(String id) async {
    final items = await passwords()
      ..removeWhere((e) => e['id'] == id);
    await _write(_passwordsKey, items);
  }

  // ------------------------------------------------- uninstall warning

  static const _warningKey = 'vault_warning_ack';

  /// Whether the user has seen the "this disappears on uninstall" warning.
  ///
  /// Android gives an app NO hook that runs when it is being uninstalled —
  /// the system removes it without asking. So the warning has to be shown
  /// before any data exists, not at uninstall time.
  Future<bool> warningAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_warningKey) ?? false;
  }

  Future<void> acknowledgeWarning() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_warningKey, true);
  }

  // ------------------------------------------------------------ backup

  /// Everything in the vault as JSON text, for the user to store somewhere
  /// safe before they wipe the phone or uninstall.
  ///
  /// This output is PLAINTEXT. It has to be, to be restorable — but it means
  /// the export is only as safe as wherever the user puts it. The UI says so
  /// before producing it.
  Future<String> exportJson() async {
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'documents': await documents(),
      'passwords': await passwords(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Restores from an [exportJson] string. Existing entries are kept and the
  /// imported ones are added, so a restore can't silently destroy what's
  /// already there.
  Future<int> importJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Unrecognised backup');

    var added = 0;
    final docs = decoded['documents'];
    if (docs is List) {
      for (final d in docs.whereType<Map>()) {
        final item = Map<String, dynamic>.from(d)..remove('id');
        await saveDocument(item);
        added++;
      }
    }
    final pwds = decoded['passwords'];
    if (pwds is List) {
      for (final p in pwds.whereType<Map>()) {
        final item = Map<String, dynamic>.from(p)..remove('id');
        await savePassword(item);
        added++;
      }
    }
    return added;
  }

  /// Wipes everything. Irreversible.
  Future<void> wipe() async {
    if (!supported) return;
    await _storage.delete(key: _documentsKey);
    await _storage.delete(key: _passwordsKey);
  }
}

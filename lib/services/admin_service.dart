import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/admin_config.dart';

/// Superadmin data access.
///
/// Admin status lives at /admins/{uid} = true in the database, and the
/// Realtime Database rules are what actually enforce it — this class is only
/// the client side. Rules are in `firebase_rules.json`; without them a
/// non-admin's reads here simply fail, which is the correct behaviour.
///
/// Every privileged read of another user's content is written to
/// /adminAudit. That log is what makes this defensible: it means admin
/// access is accountable rather than invisible.
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  final FirebaseDatabase _fb = FirebaseDatabase.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String? get _email => FirebaseAuth.instance.currentUser?.email;

  /// Superadmin is decided by email in the database rules, so the client
  /// just compares the signed-in email. No database read needed.
  bool get isSuperAdmin => AdminConfig.isSuperAdminEmail(_email);

  /// Whether the signed-in account has admin powers (superadmin counts).
  Future<bool> isAdmin() async {
    if (isSuperAdmin) return true;
    final uid = _uid;
    if (uid == null) return false;
    try {
      final snap = await _fb.ref('admins/$uid').get();
      return snap.value == true;
    } catch (_) {
      // Rules deny the read for non-admins — that's a "no".
      return false;
    }
  }

  Stream<bool> adminStream() {
    if (isSuperAdmin) return Stream.value(true);
    final uid = _uid;
    if (uid == null) return Stream.value(false);
    return _fb
        .ref('admins/$uid')
        .onValue
        .map((e) => e.snapshot.value == true)
        .handleError((_) => false);
  }

  /// Live list of admin uids. Only meaningful for the superadmin screen.
  Stream<Set<String>> adminUidsStream() {
    return _fb.ref('admins').onValue.map((e) {
      final out = <String>{};
      final val = e.snapshot.value;
      if (val is Map) {
        val.forEach((uid, flag) {
          if (flag == true) out.add(uid.toString());
        });
      }
      return out;
    }).handleError((_) => <String>{});
  }

  /// Promote or demote an admin. Superadmin only — the database rules reject
  /// this for everyone else, so a non-superadmin calling it simply fails.
  Future<void> setAdmin(String targetUid, bool value) async {
    if (!isSuperAdmin) {
      throw Exception('Only the superadmin can change admin roles.');
    }
    await _audit(value ? 'grantAdmin' : 'revokeAdmin', targetUid, 'admins');
    if (value) {
      await _fb.ref('admins/$targetUid').set(true);
    } else {
      await _fb.ref('admins/$targetUid').remove();
    }
  }

  /// All users with their profile, for the admin user list.
  Future<List<Map<String, dynamic>>> listUsers() async {
    final snap = await _fb.ref('users').get();
    final out = <Map<String, dynamic>>[];
    final val = snap.value;
    if (val is Map) {
      val.forEach((uid, data) {
        final m = <String, dynamic>{'uid': uid};
        if (data is Map) {
          final profile = data['profile'];
          if (profile is Map) {
            m['name'] = profile['name'];
            m['phone'] = profile['phone'];
            m['createdAt'] = profile['createdAt'];
            m['disabled'] = profile['disabled'] == true;
          }
          // Counts only — no content is pulled into the list view.
          for (final c in [
            'todos', 'trips', 'notes', 'reminders', 'txns',
            'goals', 'habits', 'journal', 'bookmarks'
          ]) {
            final coll = data[c];
            m['count_$c'] = coll is Map ? coll.length : 0;
          }
        }
        out.add(m);
      });
    }
    return out;
  }

  /// Aggregate stats across all users.
  Future<Map<String, int>> stats() async {
    final users = await listUsers();
    final totals = <String, int>{'users': users.length};
    for (final c in [
      'todos', 'trips', 'notes', 'reminders', 'txns',
      'goals', 'habits', 'journal', 'bookmarks'
    ]) {
      totals[c] = users.fold<int>(
          0, (sum, u) => sum + ((u['count_$c'] ?? 0) as int));
    }
    return totals;
  }

  /// Read one collection of one user's content. Writes an audit entry first,
  /// so the record exists even if the admin closes the app immediately after.
  Future<List<Map<String, dynamic>>> readUserCollection(
      String targetUid, String collection) async {
    await _audit('read', targetUid, collection);
    final snap = await _fb.ref('users/$targetUid/$collection').get();
    final out = <Map<String, dynamic>>[];
    final val = snap.value;
    if (val is Map) {
      val.forEach((key, value) {
        if (value is Map) {
          final m = Map<String, dynamic>.from(value);
          m['id'] = key;
          out.add(m);
        }
      });
    }
    return out;
  }

  /// Remove all of a user's data. Does not delete the Firebase Auth account —
  /// that requires the Admin SDK on a server, which this client can't do.
  Future<void> deleteUserData(String targetUid) async {
    await _audit('deleteData', targetUid, 'all');
    await _fb.ref('users/$targetUid').remove();
  }

  /// Flag an account as disabled. The app checks this at login.
  Future<void> setDisabled(String targetUid, bool disabled) async {
    await _audit(disabled ? 'disable' : 'enable', targetUid, 'account');
    await _fb.ref('users/$targetUid/profile/disabled').set(disabled);
  }

  /// Post an announcement all users see in-app.
  Future<void> broadcast(String title, String message) async {
    await _fb.ref('broadcast').set({
      'title': title,
      'message': message,
      'at': DateTime.now().toIso8601String(),
      'by': _email ?? _uid,
    });
  }

  Future<void> clearBroadcast() => _fb.ref('broadcast').remove();

  Stream<Map<String, dynamic>?> broadcastStream() {
    return _fb.ref('broadcast').onValue.map((e) {
      final val = e.snapshot.value;
      if (val is Map) return Map<String, dynamic>.from(val);
      return null;
    }).handleError((_) => null);
  }

  /// Audit trail of admin actions.
  Stream<List<Map<String, dynamic>>> auditStream() {
    return _fb.ref('adminAudit').limitToLast(200).onValue.map((e) {
      final out = <Map<String, dynamic>>[];
      final val = e.snapshot.value;
      if (val is Map) {
        val.forEach((key, value) {
          if (value is Map) {
            final m = Map<String, dynamic>.from(value);
            m['id'] = key;
            out.add(m);
          }
        });
      }
      out.sort((a, b) => (b['at'] ?? '').compareTo(a['at'] ?? ''));
      return out;
    });
  }

  Future<void> _audit(
      String action, String targetUid, String collection) async {
    try {
      await _fb.ref('adminAudit').push().set({
        'action': action,
        'adminUid': _uid,
        'adminEmail': _email,
        'targetUid': targetUid,
        'collection': collection,
        'at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Never let a failed audit write block the admin action itself,
      // but it also must not silently disappear — surfaced in debug.
    }
  }
}

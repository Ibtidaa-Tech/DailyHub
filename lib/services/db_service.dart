import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Central data layer on top of Firebase Realtime Database.
///
/// Layout: users/{uid}/{collection}/{id}. Shared collections (tasks, lists,
/// trips) live under the ACTIVE workspace uid, which may belong to someone
/// who shared their workspace with you; everything else is always yours.
///
/// Two important behaviours:
///  * Streams are cached and shared. Calling [stream] twice returns the SAME
///    Stream object, so StreamBuilders don't re-subscribe on every rebuild,
///    and a new listener instantly receives the latest value.
///  * Writes are fire-and-forget. The local cache updates immediately (the
///    UI reacts at once, even offline) and Firebase syncs in the background.
///    Failures (e.g. permission denied) are published on [errors].
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  final FirebaseDatabase _fb = FirebaseDatabase.instance;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  /// Set by WorkspaceProvider whenever the active workspace changes.
  String? activeWorkspaceUid;
  String? get wsUid => activeWorkspaceUid ?? uid;

  final Map<String, LiveList> _lists = {};
  final Map<String, LiveValue> _values = {};

  final StreamController<String> _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  DatabaseReference ref(String path) => _fb.ref(path);

  String? _path(String collection, bool workspace) {
    final u = workspace ? wsUid : uid;
    if (u == null) return null;
    return 'users/$u/$collection';
  }

  DatabaseReference? node(String collection, {bool workspace = false}) {
    final p = _path(collection, workspace);
    return p == null ? null : _fb.ref(p);
  }

  /// Signed-out placeholder. Every listener (not just the first) receives one
  /// empty list, so `.first` and LiveStore's loaded flag never hang.
  static final Stream<List<Map<String, dynamic>>> _emptyList =
      Stream<List<Map<String, dynamic>>>.multi((c) {
    c.add(const []);
    c.close();
  }, isBroadcast: true);

  /// Live list of a collection (id included on each map). Shared + cached.
  Stream<List<Map<String, dynamic>>> stream(String collection,
      {bool workspace = false}) {
    final p = _path(collection, workspace);
    if (p == null) return _emptyList;
    return _lists.putIfAbsent(p, () => LiveList(_fb.ref(p))).stream;
  }

  // ------------------------------------------------ another user's data
  //
  // Used by the mentor link, where a mentor reads (and assigns into) a
  // student's tracker. Deliberately NOT routed through the workspace uid:
  // workspace sharing covers tasks and trips, and a mentor must never get
  // that reach. The database rules allow these paths only for an accepted
  // mentor, and only for the tracker collections.

  /// Live list of a collection belonging to [otherUid]. Shares the same
  /// cache as [stream], keyed by full path, so the two never collide.
  Stream<List<Map<String, dynamic>>> streamFor(String otherUid, String collection) {
    if (otherUid.isEmpty) return _emptyList;
    final p = 'users/$otherUid/$collection';
    return _lists.putIfAbsent(p, () => LiveList(_fb.ref(p))).stream;
  }

  String addNowIn(String otherUid, String collection, Map<String, dynamic> data) {
    if (otherUid.isEmpty) return '';
    final r = _fb.ref('users/$otherUid/$collection').push();
    _fire(r.set(data));
    return r.key!;
  }

  Future<void> setIn(String otherUid, String collection, String id, Map<String, dynamic> data) async {
    if (otherUid.isEmpty || id.isEmpty) return;
    _fire(_fb.ref('users/$otherUid/$collection/$id').set(_clean(data)));
  }

  Future<void> updateIn(String otherUid, String collection, String id, Map<String, dynamic> data) async {
    if (otherUid.isEmpty || id.isEmpty) return;
    _fire(_fb.ref('users/$otherUid/$collection/$id').update(_clean(data)));
  }

  Future<void> removeIn(String otherUid, String collection, String id) async {
    if (otherUid.isEmpty || id.isEmpty) return;
    _fire(_fb.ref('users/$otherUid/$collection/$id').remove());
  }

  /// Last value seen for a collection, if it has been loaded.
  List<Map<String, dynamic>>? peek(String collection, {bool workspace = false}) {
    final p = _path(collection, workspace);
    return p == null ? null : _lists[p]?.latest;
  }

  /// Live single node (e.g. profile, prefs). Shared + cached.
  Stream<Map<String, dynamic>?> watch(String relPath) {
    final u = uid;
    if (u == null) return Stream<Map<String, dynamic>?>.value(null);
    final p = 'users/$u/$relPath';
    return _values.putIfAbsent(p, () => LiveValue(_fb.ref(p))).stream;
  }

  Map<String, dynamic>? peekNode(String relPath) {
    final u = uid;
    if (u == null) return null;
    return _values['users/$u/$relPath']?.latest;
  }

  void _fire(Future<void> f) {
    f.catchError((Object e) {
      debugPrint('DB write failed: $e');
      final s = e.toString();
      _errors.add(s.contains('permission')
          ? 'permission-denied'
          : 'write-failed');
    });
  }

  // ------------------------------------------------------------- writes

  /// Creates a record and returns its id immediately.
  Future<String> add(String collection, Map<String, dynamic> data,
      {bool workspace = false}) async {
    final n = node(collection, workspace: workspace);
    if (n == null) return '';
    final r = n.push();
    _fire(r.set(data));
    return r.key!;
  }

  /// Synchronous variant of [add] for UI code that needs the id at once.
  String addNow(String collection, Map<String, dynamic> data,
      {bool workspace = false}) {
    final n = node(collection, workspace: workspace);
    if (n == null) return '';
    final r = n.push();
    _fire(r.set(data));
    return r.key!;
  }

  /// A fresh id without writing anything.
  String newId(String collection, {bool workspace = false}) =>
      node(collection, workspace: workspace)?.push().key ??
      DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> set(String collection, String id, Map<String, dynamic> data,
      {bool workspace = false}) async {
    final n = node(collection, workspace: workspace);
    if (n == null || id.isEmpty) return;
    _fire(n.child(id).set(_clean(data)));
  }

  Future<void> update(String collection, String id, Map<String, dynamic> data,
      {bool workspace = false}) async {
    final n = node(collection, workspace: workspace);
    if (n == null || id.isEmpty) return;
    _fire(n.child(id).update(_clean(data)));
  }

  Future<void> remove(String collection, String id,
      {bool workspace = false}) async {
    final n = node(collection, workspace: workspace);
    if (n == null || id.isEmpty) return;
    _fire(n.child(id).remove());
  }

  /// Multi-path update relative to users/{uid}.
  Future<void> updateRoot(Map<String, dynamic> relPaths) async {
    final u = uid;
    if (u == null) return;
    _fire(_fb.ref('users/$u').update(relPaths));
  }

  Future<void> setNode(String relPath, Object? value) async {
    final u = uid;
    if (u == null) return;
    _fire(_fb.ref('users/$u/$relPath').set(value));
  }

  Future<void> updateNode(String relPath, Map<String, dynamic> value) async {
    final u = uid;
    if (u == null) return;
    _fire(_fb.ref('users/$u/$relPath').update(value));
  }

  static Map<String, dynamic> _clean(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m)..remove('id');
    return out;
  }

  /// Drop every cached listener (sign-out / account switch).
  void reset() {
    for (final l in _lists.values) {
      l.dispose();
    }
    for (final v in _values.values) {
      v.dispose();
    }
    _lists.clear();
    _values.clear();
    activeWorkspaceUid = null;
  }

  // ---------------------------------------------------------- profile

  Future<Map<String, dynamic>?> getProfile() async {
    final u = uid;
    if (u == null) return null;
    final cached = peekNode('profile');
    if (cached != null) return cached;
    try {
      final snap = await _fb.ref('users/$u/profile').get();
      return normalizeMap(snap.value);
    } catch (_) {
      return null;
    }
  }

  Stream<Map<String, dynamic>?> profileStream() => watch('profile');

  Future<void> saveProfile(String name, String phone) async {
    final existing = peekNode('profile');
    final data = <String, dynamic>{
      'name': name,
      'phone': phone,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (existing == null || existing['createdAt'] == null) {
      data['createdAt'] = DateTime.now().toIso8601String();
    }
    await updateNode('profile', data);
  }

  // --------------------------------------------------- workspace sharing

  String escapeEmail(String email) =>
      email.toLowerCase().trim().replaceAll('.', ',');

  Future<String?> lookupUidByEmail(String email) async {
    final snap = await _fb.ref('emailToUid/${escapeEmail(email)}').get();
    final val = snap.value;
    if (val is Map) return val['uid'] as String?;
    return null;
  }

  Future<void> shareWith(String email, String role) async {
    final targetUid = await lookupUidByEmail(email);
    if (targetUid == null) {
      throw Exception('User not found. They must create an account first.');
    }
    if (targetUid == uid) {
      throw Exception('You cannot share the workspace with yourself.');
    }
    await _fb.ref('users/$uid/collaborators/$targetUid').set({
      'email': email.trim(),
      'role': role,
    });
    final profile = await getProfile();
    final myName = profile?['name'] ?? 'Someone';
    await _fb.ref('users/$targetUid/sharedWithMe/$uid').set({
      'role': role,
      'ownerName': myName,
    });
  }

  Future<void> updateCollaboratorRole(String targetUid, String role) async {
    await _fb.ref('users/$uid/collaborators/$targetUid').update({'role': role});
    await _fb.ref('users/$targetUid/sharedWithMe/$uid').update({'role': role});
  }

  Future<void> removeCollaborator(String targetUid) async {
    await _fb.ref('users/$uid/collaborators/$targetUid').remove();
    await _fb.ref('users/$targetUid/sharedWithMe/$uid').remove();
  }

  Stream<List<Map<String, dynamic>>> collaboratorsStream() =>
      stream('collaborators').map((l) =>
          l.map((m) => {...m, 'uid': m['id']}).toList());

  Stream<List<Map<String, dynamic>>> sharedWithMeStream() =>
      stream('sharedWithMe').map((l) =>
          l.map((m) => {...m, 'uid': m['id']}).toList());

  /// Everything under users/{uid} (used by backup/export).
  Future<Map<String, dynamic>> exportAll() async {
    final snap = await _fb.ref('users/$uid').get();
    return normalizeMap(snap.value) ?? {};
  }
}

/// Converts Firebase's `Map<Object?, Object?>` trees into plain Dart maps/lists.
Object? normalize(Object? v) {
  if (v is Map) {
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      if (val != null) out['$k'] = normalize(val);
    });
    return out;
  }
  if (v is List) {
    return v.where((e) => e != null).map(normalize).toList();
  }
  return v;
}

Map<String, dynamic>? normalizeMap(Object? v) {
  final n = normalize(v);
  return n is Map<String, dynamic> ? n : null;
}

List<Map<String, dynamic>> _toList(Object? val) {
  final list = <Map<String, dynamic>>[];
  if (val is Map) {
    val.forEach((key, value) {
      if (value is Map) {
        final m = normalizeMap(value)!;
        m['id'] = '$key';
        list.add(m);
      }
    });
  } else if (val is List) {
    for (var i = 0; i < val.length; i++) {
      final value = val[i];
      if (value is Map) {
        final m = normalizeMap(value)!;
        m['id'] = '$i';
        list.add(m);
      }
    }
  }
  return list;
}

/// A shared, replaying live query. The Firebase listener stays attached while
/// anyone listens and for 45 seconds after the last one leaves, so hopping
/// between tabs never re-downloads data.
class LiveList {
  LiveList(this.query) {
    stream = Stream<List<Map<String, dynamic>>>.multi(_onListen, isBroadcast: true);
  }

  final Query query;
  late final Stream<List<Map<String, dynamic>>> stream;
  List<Map<String, dynamic>>? latest;

  final Set<MultiStreamController<List<Map<String, dynamic>>>> _listeners = {};
  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _idle;

  void _onListen(MultiStreamController<List<Map<String, dynamic>>> c) {
    _idle?.cancel();
    _listeners.add(c);
    final l = latest;
    if (l != null) c.add(List.of(l));
    _sub ??= query.onValue.listen(_onEvent, onError: _onError);
    c.onCancel = () {
      _listeners.remove(c);
      if (_listeners.isEmpty) {
        _idle = Timer(const Duration(seconds: 45), () {
          _sub?.cancel();
          _sub = null;
        });
      }
    };
  }

  void _onEvent(DatabaseEvent e) {
    final l = _toList(e.snapshot.value);
    latest = l;
    for (final c in List.of(_listeners)) {
      c.add(List.of(l));
    }
  }

  void _onError(Object e, StackTrace s) {
    debugPrint('Live query error (${query.path}): $e');
    latest ??= const [];
    for (final c in List.of(_listeners)) {
      c.add(List.of(latest!));
    }
  }

  void dispose() {
    _idle?.cancel();
    _sub?.cancel();
    _sub = null;
    for (final c in List.of(_listeners)) {
      c.closeSync();
    }
    _listeners.clear();
  }
}

class LiveValue {
  LiveValue(this.query) {
    stream = Stream<Map<String, dynamic>?>.multi(_onListen, isBroadcast: true);
  }

  final Query query;
  late final Stream<Map<String, dynamic>?> stream;
  Map<String, dynamic>? latest;
  bool _loaded = false;

  final Set<MultiStreamController<Map<String, dynamic>?>> _listeners = {};
  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _idle;

  void _onListen(MultiStreamController<Map<String, dynamic>?> c) {
    _idle?.cancel();
    _listeners.add(c);
    if (_loaded) c.add(latest);
    _sub ??= query.onValue.listen((e) {
      latest = normalizeMap(e.snapshot.value);
      _loaded = true;
      for (final l in List.of(_listeners)) {
        l.add(latest);
      }
    }, onError: (Object e) {
      debugPrint('Live value error (${query.path}): $e');
      _loaded = true;
      for (final l in List.of(_listeners)) {
        l.add(latest);
      }
    });
    c.onCancel = () {
      _listeners.remove(c);
      if (_listeners.isEmpty) {
        _idle = Timer(const Duration(seconds: 45), () {
          _sub?.cancel();
          _sub = null;
        });
      }
    };
  }

  void dispose() {
    _idle?.cancel();
    _sub?.cancel();
    _sub = null;
    for (final c in List.of(_listeners)) {
      c.closeSync();
    }
    _listeners.clear();
  }
}

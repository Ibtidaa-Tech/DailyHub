import 'dart:async';

import 'package:flutter/foundation.dart';

/// Base for the app's live stores. Each store subscribes to a handful of
/// Firebase collections once, keeps typed lists in memory, and notifies the
/// UI. Derived values are cached until the next change.
abstract class LiveStore extends ChangeNotifier {
  final List<StreamSubscription<dynamic>> _subs = [];
  final Set<String> _pending = {};
  bool _disposed = false;
  final Map<String, Object?> _memo = {};

  /// True once every collection has delivered its first value.
  bool get loaded => _pending.isEmpty && _started;
  bool _started = false;

  void watch<T>(String name, Stream<T> stream, void Function(T value) onData) {
    _started = true;
    _pending.add(name);
    _subs.add(stream.listen((v) {
      onData(v);
      _pending.remove(name);
      _memo.clear();
      if (!_disposed) notifyListeners();
    }, onError: (Object e) {
      debugPrint('$runtimeType/$name: $e');
      _pending.remove(name);
      if (!_disposed) notifyListeners();
    }));
  }

  /// Caches an expensive derived value until the data changes.
  R memo<R>(String key, R Function() build) {
    if (_memo.containsKey(key)) return _memo[key] as R;
    final v = build();
    _memo[key] = v;
    return v;
  }

  void invalidate() {
    _memo.clear();
    if (!_disposed) notifyListeners();
  }

  void cancelAll() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _pending.clear();
    _memo.clear();
    _started = false;
  }

  @override
  void dispose() {
    _disposed = true;
    cancelAll();
    super.dispose();
  }
}

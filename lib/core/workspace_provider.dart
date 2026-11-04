import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Mirrors the web app's workspace-sharing model.
///
/// Roles (identical to web):
///   owner  - your own workspace, full control
///   master - can add + edit + delete in someone else's workspace
///   add    - can add only
///   view   - read only
class WorkspaceProvider extends ChangeNotifier {
  String? _workspaceUid;
  String _role = 'owner';
  String _name = 'My Workspace';

  String get role => _role;
  String get name => _name;

  String? get ownUid => FirebaseAuth.instance.currentUser?.uid;

  /// The uid whose trips/todos we are currently viewing.
  String? get workspaceUid => _workspaceUid ?? ownUid;

  bool get isOwnWorkspace => workspaceUid == ownUid;

  /// Matches the web app's `canAdd` check.
  bool get canAdd => _role == 'owner' || _role == 'master' || _role == 'add';

  /// Edit/delete allowed for owner and master only (web hides these for 'add').
  bool get canEdit => _role == 'owner' || _role == 'master';

  void switchTo({
    required String uid,
    required String role,
    required String name,
  }) {
    _workspaceUid = uid;
    _role = role;
    _name = name;
    notifyListeners();
  }

  void resetToOwn() {
    _workspaceUid = ownUid;
    _role = 'owner';
    _name = 'My Workspace';
    notifyListeners();
  }

  /// Called when a live role change arrives from the owner.
  void updateRoleLive(String role) {
    if (_role == role) return;
    _role = role;
    notifyListeners();
  }
}

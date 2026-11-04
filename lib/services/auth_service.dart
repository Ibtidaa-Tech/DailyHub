import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Wraps Firebase Auth. Mirrors the web app's behaviour, including writing
/// the emailToUid lookup so the existing web "Share Workspace" feature keeps
/// finding users created from the mobile app.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Stream<User?> get authState => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    await _registerEmailLookup(cred.user);
    return cred.user;
  }

  Future<User?> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    await _registerEmailLookup(cred.user);
    return cred.user;
  }

  /// Google sign-in takes a different route on each platform.
  ///
  /// On WEB: `GoogleSignIn().signIn()` is not supported by google_sign_in 6.x
  /// and fails with "Null check operator used on a null value". Firebase
  /// Auth's own popup flow handles the whole exchange natively, so the
  /// plugin is bypassed entirely there.
  ///
  /// On MOBILE: the plugin flow is correct and gives the native account
  /// picker, so it stays.
  Future<User?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final cred = await _auth.signInWithPopup(provider);
      await _registerEmailLookup(cred.user);
      return cred.user;
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // cancelled
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    await _registerEmailLookup(cred.user);
    return cred.user;
  }

  /// Sends Firebase's password-reset email.
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    // Google sign-out can throw if the user never signed in with Google;
    // that's harmless, so it's swallowed here rather than blocking the
    // Firebase sign-out that actually matters.
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // ignored
      }
    }
    await _auth.signOut();
  }

  Future<void> _registerEmailLookup(User? user) async {
    if (user == null || user.email == null) return;
    final escaped = user.email!.toLowerCase().replaceAll('.', ',');
    await _db.child('emailToUid/$escaped').set({
      'uid': user.uid,
      'name': user.displayName ?? user.email,
    });
  }
}

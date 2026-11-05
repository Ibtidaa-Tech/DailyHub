import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'db_service.dart';

/// The mentor link: a guide who sets a tracker for a student and watches how
/// it goes.
///
/// Deliberately separate from workspace sharing. A collaborator can write
/// across someone's whole account; a mentor must only ever reach the
/// tracker. The database rules enforce that — this class is just the client
/// side of the same shape.
///
/// Two mirrored records per link:
///   users/{student}/mentors/{mentor}   the one that grants access
///   users/{mentor}/students/{student}  a copy so the mentor can list people
///
/// Only the student can move their own record to 'accepted' (a rule check,
/// not a client check), so a mentor cannot grant themselves access by
/// writing the invite they created.
class MentorService {
  MentorService._();
  static final MentorService instance = MentorService._();

  final DbService _db = DbService.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String? get _email => FirebaseAuth.instance.currentUser?.email;

  static const String pending = 'pending';
  static const String accepted = 'accepted';

  DatabaseReference _ref(String path) => _db.ref(path);

  /// uid + display name for an email, from the public lookup table the app
  /// already maintains on sign-in.
  Future<({String uid, String name})?> _lookup(String email) async {
    final key = _db.escapeEmail(email);
    if (key.isEmpty) return null;
    final snap = await _ref('emailToUid/$key').get();
    final val = snap.value;
    if (val is! Map) return null;
    final uid = '${val['uid'] ?? ''}';
    if (uid.isEmpty) return null;
    return (uid: uid, name: '${val['name'] ?? email}');
  }

  /// Invite a student by email. Creates a pending link both sides; nothing
  /// is readable by the mentor until the student accepts.
  Future<void> invite(String email) async {
    final me = _uid;
    if (me == null) throw Exception('You are not signed in.');
    final target = await _lookup(email);
    if (target == null) {
      throw Exception('No DailyHub account for that email. They need to sign up first.');
    }
    if (target.uid == me) {
      throw Exception('You cannot add yourself as your own student.');
    }

    final existing = await _ref('users/$me/students/${target.uid}/status').get();
    if (existing.value == accepted) {
      throw Exception('They are already your student.');
    }

    final myName = _email == null ? 'Your mentor' : (await _lookup(_email!))?.name ?? _email!;
    final now = DateTime.now().toIso8601String();

    // The student's copy first — it is the one that matters. If the mirror
    // below fails, the link still works and the mentor's list can be rebuilt.
    await _ref('users/${target.uid}/mentors/$me').set({
      'email': _email ?? '',
      'name': myName,
      'status': pending,
      'invitedAt': now,
    });
    await _ref('users/$me/students/${target.uid}').set({
      'email': email.trim(),
      'name': target.name,
      'status': pending,
      'invitedAt': now,
    });
  }

  /// Student-initiated: hand someone access to your own tracker.
  ///
  /// No acceptance step, and none is needed — you are giving away a view of
  /// your own data rather than asking for anything, so your write is the only
  /// consent involved. The rules permit it for the same reason: the student
  /// is the one account allowed to set 'accepted' on their own mentor record.
  ///
  /// They can drop you from their list at any time, and you can revoke with
  /// [removeMentor], which cuts access immediately.
  Future<void> addMentor(String email) async {
    final me = _uid;
    if (me == null) throw Exception('You are not signed in.');
    final target = await _lookup(email);
    if (target == null) {
      throw Exception('No DailyHub account for that email. They need to sign up first.');
    }
    if (target.uid == me) {
      throw Exception('You cannot be your own mentor.');
    }

    final existing = await _ref('users/$me/mentors/${target.uid}/status').get();
    if (existing.value == accepted) {
      throw Exception('They are already your mentor.');
    }

    final myName = _email == null ? 'A student' : (await _lookup(_email!))?.name ?? _email!;
    final now = DateTime.now().toIso8601String();

    await _ref('users/$me/mentors/${target.uid}').set({
      'email': email.trim(),
      'name': target.name,
      'status': accepted,
      'invitedAt': now,
      'acceptedAt': now,
    });
    await _ref('users/${target.uid}/students/$me').set({
      'email': _email ?? '',
      'name': myName,
      'status': accepted,
      'invitedAt': now,
      'acceptedAt': now,
    });
  }

  /// Student accepts. This is the moment the mentor gains read access, and
  /// only the student's own write can do it.
  Future<void> accept(String mentorUid) async {
    final me = _uid;
    if (me == null) return;
    final now = DateTime.now().toIso8601String();
    await _ref('users/$me/mentors/$mentorUid').update({'status': accepted, 'acceptedAt': now});
    await _ref('users/$mentorUid/students/$me').update({'status': accepted, 'acceptedAt': now});
  }

  /// Student declines or later removes a mentor. Removing the record is what
  /// revokes access, immediately.
  Future<void> removeMentor(String mentorUid) async {
    final me = _uid;
    if (me == null) return;
    await _ref('users/$me/mentors/$mentorUid').remove();
    await _ref('users/$mentorUid/students/$me').remove();
  }

  /// Mentor withdraws an invite or drops a student.
  Future<void> removeStudent(String studentUid) async {
    final me = _uid;
    if (me == null) return;
    await _ref('users/$me/students/$studentUid').remove();
    await _ref('users/$studentUid/mentors/$me').remove();
  }

  /// People who mentor me. Each map carries id (their uid), name, email,
  /// status.
  Stream<List<Map<String, dynamic>>> myMentors() => _db.stream('mentors');

  /// People I mentor.
  Stream<List<Map<String, dynamic>>> myStudents() => _db.stream('students');
}

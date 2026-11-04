/// Superadmin identity.
///
/// IMPORTANT: this constant only controls what the UI shows. The actual
/// enforcement lives in `database.rules.json`, which checks
/// `auth.token.email` server-side. If you change the superadmin, change it
/// in BOTH places and run `firebase deploy --only database`.
///
/// Superadmin is email-based rather than a database flag on purpose: because
/// it isn't stored as data, no one can grant it to themselves by writing to
/// the database, and a compromised admin account can't escalate to superadmin.
library;

class AdminConfig {
  static const String superAdminEmail = 'khurramrashid0786@gmail.com';

  static bool isSuperAdminEmail(String? email) =>
      email != null && email.toLowerCase().trim() == superAdminEmail;
}

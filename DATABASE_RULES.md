# Database rules & admin roles

## Deploying rules (CLI only)

Rules live in `database.rules.json` and are deployed from the command line.
Do not edit them in the Firebase Console — console edits get overwritten by
the next CLI deploy, and the file in git stops matching what's live.

```bash
firebase deploy --only database
```

Deploy everything at once:

```bash
firebase deploy --only database,hosting
```

Note this is `database` (Realtime Database), **not** `firestore` — DailyHub
uses Realtime Database, which your original web app already used.

---

## The two admin tiers

### Superadmin — `abc@gmail.com`

Identified by **email address inside the rules themselves**, not by a
database flag. This is deliberate: because superadmin status isn't stored as
data, nobody can grant it to themselves by writing to the database. Even a
compromised admin account can't escalate. The only way to change who the
superadmin is, is to edit `database.rules.json` and redeploy.

Superadmin can:
- read and write every user's data
- promote and demote admins
- send broadcasts
- read the audit log

### Admin — flagged at `/admins/{uid}: true`

Admins can:
- read and write every user's data
- send broadcasts
- read the audit log

Admins **cannot**:
- promote anyone to admin (only superadmin writes `/admins`)
- become superadmin (that's email-based in the rules, not data)

---

## Changing the superadmin email

It appears in two places and both must match:

1. `database.rules.json` — eight occurrences of `abc@gmail.com`
   (search and replace, then `firebase deploy --only database`)
2. `lib/core/admin_config.dart` — the `superAdminEmail` constant

The rules are what actually enforce access. The Dart constant only decides
whether the UI shows superadmin-only controls. If they disagree, the UI will
show buttons that then fail server-side — so change both together.

---

## First-time setup

```bash
firebase deploy --only database
```

Then sign in as `abc@gmail.com`. The Admin tile appears in More, with an
extra "Admins" tab for promoting other users.

No manual console step is needed — superadmin works from the first deploy
because it's email-based.

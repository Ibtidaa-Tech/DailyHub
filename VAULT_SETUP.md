# Vault — setup and how it works

## What changed in this build

Two native plugins were added, so this build has more setup than the last
few:

| Change | File | Why |
|---|---|---|
| `flutter_secure_storage`, `local_auth` | `pubspec.yaml` | encrypted storage + biometric unlock |
| `FlutterActivity` → `FlutterFragmentActivity` | `android/app/src/main/kotlin/com/khurram/dailyhub/MainActivity.kt` | `local_auth` crashes without a FragmentActivity |
| Permissions block added | `android/app/src/main/AndroidManifest.xml` | see below |

Both native changes are already applied in this zip. Nothing to do by hand.

---

## The manifest fix (important)

Your `AndroidManifest.xml` had **no permissions at all**. The notification
permissions from the first delivery were never merged in, which means on
Android 13+ every scheduled reminder has been dropped silently — the app
looked like it scheduled them, and nothing ever fired.

Now added:

- `POST_NOTIFICATIONS` — required on Android 13+ for any notification
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — reminders at an exact time
- `RECEIVE_BOOT_COMPLETED` — reminders survive a reboot
- `VIBRATE`, `WAKE_LOCK`
- `USE_BIOMETRIC` — vault unlock

Plus the two `flutter_local_notifications` receivers, without which
scheduled alerts are lost on reboot or app update.

The app label was also `dailyhub` (lowercase, from `flutter create`) and is
now `DailyHub`.

**Test reminders again after this build.** If they never worked for you
before, this is why.

---

## How the vault stores data

| Platform | Storage |
|---|---|
| Android | `EncryptedSharedPreferences`, keys held in the hardware keystore |
| iOS | Keychain, `first_unlock` accessibility |
| Web | **disabled** |

Web is disabled on purpose. Browser storage has no keystore equivalent, and
shipping a "vault" backed by `localStorage` would be security theatre. The
screen says so plainly instead.

### Nothing here is ever sent to Firebase

That was the point of choosing device-only. A synced database means anyone
who gets into the account reads plaintext ID numbers and passwords — and for
Aadhaar specifically, server-side storage carries legal exposure under the
Aadhaar Act. Keeping it on-device sidesteps both.

### The tradeoff you accepted

- No sync between phone and web
- **Uninstalling the app destroys the vault permanently** — there's no
  recovery path, by design
- A new phone starts with an empty vault

The lock screen tells users to keep their own backup of anything
irreplaceable. Worth leaving that message in.

---

## Unlocking

Biometric first, device PIN/pattern as fallback (`biometricOnly: false`).
If the phone has no screen lock at all, the vault stays locked and explains
why rather than opening unprotected.

Values are masked by default in the UI, with a tap to reveal and a copy
button, so nothing sensitive sits on screen in public.

Document expiry reminders are scheduled 30 days ahead. The notification text
deliberately contains only the label — never the document number — since
notifications appear on the lock screen.

---

## If the build fails

These are the first native plugins added since the toolchain issues, so if
something breaks it's most likely here:

1. **`local_auth` + AGP 9** — if it fails to compile, pin it lower:
   `local_auth: ^2.2.0`
2. **MainActivity errors** — confirm the file says `FlutterFragmentActivity`
   and the import matches
3. **minSdk** — `flutter_secure_storage` needs 23; already set

```
flutter clean
flutter pub get
flutter analyze
flutter run
```

Run `flutter run` before `build apk` this time — a runtime crash from the
biometric prompt won't show up at build time.

---

# Photo attachments (added this build)

## Plugins
`image_picker` + `firebase_storage`. Camera and gallery permissions are
already in the manifest.

## Deploy the Storage rules before testing
```
firebase deploy --only storage
```
Without them, uploads fail silently — Storage's default rules deny
everything. The rules scope each user to `attachments/{their-uid}/`, so one
user can never read another's receipts.

## Where attachments live
Firebase Storage at `attachments/{uid}/receipts/...` and
`attachments/{uid}/notes/...`. The record stores only the download URL.

Images are downscaled to 1600px and recompressed at 75% quality before
upload — a raw phone photo is 3–8MB, which is wasteful for a receipt and
slow on mobile data.

They are **not** base64'd into the Realtime Database. RTDB has a 10MB node
ceiling and embedding photos would slow every read of the whole collection.

## Attachments sync; the vault does not
Deliberate split. Vault holds secrets, so it stays device-only. A receipt is
ordinary content — it should appear on your phone and the web build alike.

---

# The uninstall warning

Android provides **no callback when an app is uninstalled**. The system
removes it without running any of its code, so a popup at that moment is
impossible — not difficult, impossible.

What the app does instead:

1. **A full warning dialog on first unlock**, before any data exists
2. **A permanent banner** above the vault tabs, tappable to re-read it
3. **Back up / Restore** in the vault menu, so the vault isn't one-way

Backup re-prompts for biometrics, then shares a JSON file. That file is
plaintext — it must be, to be restorable — and the dialog says so before
producing it. Restore adds to existing entries rather than replacing them,
so it can't silently destroy what's already there.

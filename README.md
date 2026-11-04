# DailyHub 2.1

Your whole day in one calm place — plan, money, notes and habits, on Android, the
web and tablets. English and full Hindi, light and dark, eight accent colours.

This is a **full redesign** of DailyHub. Same Firebase project (`khurram-world`),
brand-new data model and interface. Start fresh — old records from the 1.x app
are not migrated.

---

## Run it on Windows

### Extract, then clear out the old version

Extracting a zip over an existing folder overwrites files with the same name but
leaves behind any that were **deleted or renamed** between versions — and those
still get compiled, so the build fails on code that isn't part of the release
any more.

So after extracting, run the cleaner. It compares `lib` and `test` against
`tool\release_manifest.txt` (the exact file list of this release), shows you
anything left over and deletes it once you confirm:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\clean_stale.ps1
```

Add `-WhatIf` to see what it would remove without touching anything, or `-Force`
to skip the confirmation. It only ever looks at `.dart` files under `lib` and
`test`, so your Gradle, assets and Firebase config are never touched.

### Build and run

Open **PowerShell** in the project folder (the one holding `pubspec.yaml`) and
run these in order:

```powershell
flutter clean
flutter pub get
flutter analyze
```

`flutter analyze` is the one that matters — send me its output and I'll fix
whatever it reports.

Then run the app:

```powershell
:: list connected devices first
flutter devices

:: phone or emulator (use the id from the list above)
flutter run -d <device-id>

:: web browser
flutter run -d chrome

:: Windows desktop (only if Windows desktop support is enabled)
flutter run -d windows
```

Release builds:

```powershell
:: APK you can install on a phone  ->  build\app\outputs\flutter-apk\app-release.apk
flutter build apk --release

:: smaller, per-architecture APKs
flutter build apk --release --split-per-abi

:: Play Store bundle
flutter build appbundle --release

:: web  ->  build\web
flutter build web --release
```

Firebase rules (only needed if you change `database.rules.json`):

```powershell
firebase deploy --only database
firebase deploy --only storage
```

### If an Android build fails

**`checkDebugAarMetadata` ... requires compile against version 36 or later`**
`android/build.gradle.kts` already raises every Android module to compileSdk 36
to handle this. If it ever comes back, the module named in the error has pinned
something newer; bump `dailyHubCompileSdk` in that file.

**`Failed to find target with hash string 'android-36'`**
Install the SDK platform: Android Studio → Settings → Languages & Frameworks →
Android SDK → tick **Android API 36** → Apply.

**`Cannot run Project.afterEvaluate(Action) when the project is already
evaluated`**
Something was added to `android/build.gradle.kts` after the
`evaluationDependsOn(":app")` block. The compileSdk block has to come *before*
it, because that line forces `:app` to evaluate immediately.

**Last resort if a plugin simply won't build**: `flutter pub deps` shows who
pulls it in, and a `dependency_overrides:` entry in `pubspec.yaml` pins a
version that does. There's already one there for `record_linux`, with a comment
explaining why.

### While you're developing

- `r` in the terminal = hot reload, `R` = hot restart, `q` = quit.
- If a build fails oddly after pulling changes:
  `flutter clean` then `flutter pub get`, and in Android Studio
  *File → Invalidate Caches / Restart*.
- If Gradle complains about the JDK, make sure `java -version` reports **17**.

---

## What's new in 2.0

### Structure
A bottom bar with **four tabs and a centre +** — Home · Plan · (+) · Money · Hub.
Everything else lives in **Hub**, grouped and searchable, and you switch features
on and off in Settings, so the app stays as small or as big as you want it.
On tablets and desktop the bar becomes a side rail and the content is centred
with comfortable margins.

### Onboarding
Four short steps: your name, who you are (student / working / family / traveller),
your toolkit, then notifications and weather. Choosing a persona switches on a
sensible set of features; everything is changeable later. This follows the
progressive-disclosure pattern — ask for the minimum up front, reveal the rest
when it's needed — rather than a long front-loaded setup form.

### Smart add — type it the way you'd say it
One box on Home and a big **+** in the bar. It reads plain English *and* Hindi:

| You type | You get |
|---|---|
| `call mom 6pm` | task today at 6:00 PM with a reminder |
| `gym kal 7am #health !high` | task tomorrow, high priority, tagged health |
| `remind me to pay rent every month` | monthly repeating reminder |
| `spent 250 lunch` | ₹250 expense, auto-categorised as Food |
| `earned 40000 salary` | ₹40,000 income under Salary |
| `lent 500 to Raju` | entry in the lend & borrow ledger |
| `note: idea for the shop` | a note |

Paste several lines and it creates all of them at once. Every save shows an
**Undo**.

### Money — the part you asked for
Add an entry in **one tap**: the amount keypad opens straight away (it does
`+ − × ÷` too), the category is guessed from what you type, and **every total
recalculates the moment you hit save** — spent, earned, saved, per-account
balance, budget left, savings rate.

Built on what people actually track day to day:

- **Accounts & balances** — cash, bank, UPI, card, wallet; balances update
  themselves, and you can transfer between accounts.
- **Bills & subscriptions** — rent, electricity, mobile, OTT, EMI, insurance,
  SIP; reminders a few days before and on the day, one tap to mark paid (which
  files the expense and rolls the due date forward).
- **Lend & borrow (udhaar)** — per person, part payments, "send reminder" over
  WhatsApp or SMS, settle in one tap.
- **Split a bill** — your share becomes the expense, everyone else lands in the
  ledger automatically.
- **Budgets** — an overall monthly limit plus per-category limits, shown as
  "₹X left · ₹Y/day for Z days" so it means something.
- **Savings goals** — target, deadline, "save ₹X/month to get there on time".
- **Reports** — month or year, trend, category deltas vs last period, biggest
  expenses, income sources, **CSV export**.
- **Your own categories**, emoji and colours included.
- **40+ currencies**, picked automatically from your region and changeable.

### Plan
Today / Upcoming / Calendar / Priority-matrix views, lists and `#tags`, quick
times and snooze, subtasks you can reorder, repeating tasks that roll forward
when you tick them, a one-tap "move everything overdue to today", and a
**Pomodoro focus timer** that logs minutes against the task.

### Notes & habits
Notes as a masonry grid or a list, pinning, labels, colours, checklists, photos
and voice notes, archive and search. Habits can be yes/no or counted (8 glasses,
20 pages), scheduled on specific days, with streaks that don't break just
because today is still open, a heat-map and stats.

### Everything else
- **Weather on Home** from your location or a city you pick — free, no API key
  (Open-Meteo).
- **Daily briefing** at 08:00 and an evening review at 21:00, both optional.
- **App lock** with fingerprint, face or your screen lock.
- **Backup & restore** to a JSON file you keep.
- **Shared workspace** — plan together with family or your team.
- **Notifications** that fire when the app is closed, survive a reboot, and carry
  Snooze / Done buttons.

---

## Under the hood

- **Offline-first writes.** Changes land in the UI immediately and sync when the
  network returns; failures surface as a message instead of a silent loss.
- **One notification planner.** All alarms are diffed against a desired set and
  rescheduled in one place, so you never get duplicates or stale reminders.
- **Live stores** (`PlanStore`, `MoneyStore`, `NotesStore`, `HabitsStore`) share a
  single cached Firebase stream per collection.
- **No raw strings in the UI** — every label goes through `context.t('key')` and
  exists in both English and Hindi.

## Project layout

```
lib/
  core/        theme, settings, localization, currencies, date & text parsing
  data/        models and the live stores
  services/    database, notifications, planner, weather, backup, auth
  ui/          shared widgets (kit.dart) and the brand mark
  features/    home, plan, money, notes, habits, capture, hub, search,
               settings, onboarding, auth, shell
  l10n/        English + Hindi strings
  screens/     older screens, redesigned in phase 2
```

## What phase 2 added (2.1)

Every remaining module is now redesigned on the same system, and the Android
home-screen widget has landed.

**Student** — your timetable, and attendance that does the maths. Mark a class
present, absent or cancelled with one tap from today's list; cancelled classes
don't count against you. Each subject shows how many more classes you can afford
to miss, or how many in a row you must attend to climb back to the target (75%
by default, adjustable — some colleges want 80 or 85). Assignments with due
dates, and a CGPA worked out from credits and grades on the 10-point scale.

**Trips** — flights, trains, buses and cars with PNR, seat, fare and timings, a
countdown to departure, and a packing list with starter templates for
essentials, clothes and toiletries. Shared with your workspace, so a family
plans one trip together.

**Shopping** — shared lists that sort themselves into the order you actually
shop in. Type "2 kg tomato" and it files the quantity and the aisle for you.
Running total of what's still to buy and what's in the basket, one-tap re-add
for things you buy often, and when you're done, the basket total goes straight
into your expenses.

**Work** — meetings with agenda, attendees and notes that save as you type, plus
action items. Any action item becomes a real task in Plan with one tap, so what
people agreed to doesn't get lost in a notes app.

**Everything else restyled** — Goals, Journal, Countdowns, Places (including
where you parked), Deliveries, Bookmarks, Insights, Vault, Emergency, Scanner,
Sharing, Admin, and the six Tools (calculator, converter, date tools, stopwatch
and timer, finance calculators).

### Android home-screen widget

Long-press your home screen → Widgets → DailyHub, and drop "Today" on. It shows
your next few agenda items, how many tasks are left and done, what you've spent
today and your habit progress, with a **+** that opens straight into adding
something.

It carries no plugin and starts no Flutter engine: the app writes a small
summary into the same preferences file it already uses, and the widget reads it
natively. That means it draws instantly, survives a reboot, follows your system
light/dark theme, and keeps working when the app isn't running.

---

## Firebase

Project `khurram-world`, Realtime Database. Data lives under `users/{uid}/…`:
`todos`, `lists`, `trips` are shared with a workspace; `reminders`, `txns`,
`accounts`, `categories`, `budgets`, `bills`, `debts`, `goals`, `notes`,
`habits`, `prefs` and `profile` are personal.

The rules in `database.rules.json` already cover every collection. 2.0 adds two
guards: only an admin can flip a `profile/disabled` flag, and only the owner can
change their own `collaborators` list. Superadmin stays `abc@gmail.com`.

## Releasing a new version

Change all three together, or the in-app update check won't line up:

1. `appVersion` in `lib/core/app_version.dart`
2. `version:` in `pubspec.yaml`
3. the GitHub release tag (`v2.0.0`)

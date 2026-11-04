# Native plugins — what's here and how to bisect a broken build

This build adds **six plugins at once**, which is more risk than the earlier
batches carried. Each one is independently removable. If the build breaks,
the table below tells you exactly what to pull.

| Feature | Plugins | Files that use it |
|---|---|---|
| Voice notes | `record`, `audioplayers`, `path_provider` | `services/voice_service.dart`, `widgets/voice_note_recorder.dart` |
| File attachments | `file_picker` | `services/file_service.dart`, `widgets/file_picker_strip.dart` |
| QR / barcode scan | `mobile_scanner` | `screens/scanner_screen.dart` |
| Location capture | `geolocator` | `services/location_service.dart` |

---

## First run

```
flutter clean
flutter pub get
flutter analyze
flutter run
```

Use `flutter run`, not `build apk`. Permission prompts, the camera pipeline
and the microphone only fail at runtime — a green build proves nothing here.

---

## If the Gradle build fails

Work out which plugin it is from the error text, then remove that one from
`pubspec.yaml` plus the files in its row, and rebuild. Losing one feature
beats a project that won't compile.

Known-good older pins if a plugin is ahead of your AGP:

```yaml
record: ^5.0.4
mobile_scanner: ^5.1.1
geolocator: ^12.0.0
file_picker: ^8.0.0
```

`mobile_scanner` is the most likely to complain — it pulls in CameraX and is
the most AGP-sensitive thing in the list. If you hit a wall there, drop it
and keep everything else; the scanner is the least load-bearing feature.

---

## Permissions added

| Permission | For |
|---|---|
| `RECORD_AUDIO` | voice notes |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | parking / places |
| `CAMERA` | photos, QR scanning |

`ACCESS_BACKGROUND_LOCATION` is **deliberately absent** — see below.

---

## What location does and does not do

It captures your position **on demand**, when you press "save parking spot".
That's it.

It does **not** do geofenced reminders ("remind me when I get home"). That
needs background location, a persistent foreground service, and it drains
battery continuously. For a feature most people use a handful of times, the
cost is wrong — so it's not here, rather than being here and quietly eating
your battery.

The parking note you type is still the primary record. Indoor car parks are
exactly where GPS is least reliable, so "Level B2, row 14" beats a
coordinate that thinks you're on the roof.

---

## Voice notes on web

Recording is mobile-only. `record` does support web via MediaRecorder, but
the output container differs between browsers and playback isn't reliable
across all of them. Web gets **playback only** — notes recorded on your
phone play fine in the browser.

---

## Storage

Voice notes and files use the same `attachments/{uid}/...` layout as photos,
so the existing Storage rules already cover them. If you haven't deployed
those yet:

```
firebase deploy --only storage
```

Files are capped at 15MB. Firebase allows far more, but large attachments on
mobile data are a bad experience and burn the free quota fast.

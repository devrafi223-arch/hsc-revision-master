# HSC Science Revision Master — Flutter app

Soft, smooth, phone-first HSC Science revision tracker.
**7 subjects, 151 chapters, 906 milestones** (151 × 6 stages per chapter),
verified against the original repo — no chapter invented.

## Design — Cupertino (iOS-style) on pure Flutter

The whole UI is Apple-style Cupertino: `CupertinoApp`, `CupertinoPageScaffold`
with a large-title-style navigation bar, `CupertinoTabScaffold` +
`CupertinoTabBar` (Today / All chapters / Exam plan), `CupertinoButton.filled`
for primary actions, `CupertinoSearchTextField`,
`CupertinoSlidingSegmentedControl` for the paper/status filters,
`CupertinoSwitch` for night mode, `CupertinoDatePicker` in a modal sheet for
the exam target date, `CupertinoAlertDialog` / `CupertinoActionSheet` for
confirmations and the more-menu, and a hand-drawn progress ring. No Material
widgets remain in `lib/` — Cupertino's default blue never appears; the theme
uses the Jim palette below. Platforms are still **Android, Web, Windows,
Linux only — no iOS, no macOS** folders; Cupertino here is a design language,
not an Apple-platform target.

Original: https://github.com/AbidHasan101101/Revision-materials (GPL-3.0).
Enriched research notes: `../RESEARCH.md` (HSC 2026 routine, marks pattern,
subject codes, study method).

## Colours — Jim portfolio palette

From [jimsiraj.pp.ua](https://jimsiraj.pp.ua/) ("Jim, a soft sketchbook"),
softened for an airy feel: warm off-white `#F8F6F1` background (never stark
white), card `#FFFFFF`, ink `#1C1A17`, muted `#6F6A62`,
line `#E9E4DA`, soft-black `#2B2B2B` buttons, dusty rose `#A9716B` /
`#CF9A92` only for the progress ring, done states and small highlights.
Dark mode: background `#17161A`, surface `#211F22`, text `#FAF8F4`.

Spacing is deliberately roomy: 24px page padding, 24px between sections,
16px between chapter cards, 20px card padding, 28px above section headers.
Chapter cards show 3 stage chips per row (44px tall, 10px gaps) with a slim
rose progress bar; a stage's tip appears only when its chip is tapped.

## Features

- Progress ring + counts (done / 906), weakest subject, exam target date
  picker, daily target = remaining tasks ÷ days left
- Today's Focus: next 5 pending chapters
- Chapter cards with 6 tappable stage chips (Archive, Note, Recall, MCQ,
  Live, Test Paper) in 3-per-row rows, search (Bangla + English), subject chips, paper filter,
  status filter (All / Pending / In progress / Done)
- 25-minute Pomodoro timer (Start / Pause / Reset)
- Exam plan tab: HSC 2026 reference dates and marks. HSC 2027 routine was
  **not** published at research time (Nov 2026) — no 2027 date is invented.
- Share: WhatsApp-ready summary copied to clipboard; JSON backup export
  (file on Android/Windows/Linux, clipboard on web) and import by pasting JSON.
- Progress is stored on-device with SharedPreferences under the key
  `hsc-revision-master-v2` (same key as the web versions).

## Run it

```sh
flutter pub get
flutter run -d chrome    # web
flutter run              # Android device / emulator
flutter run -d windows   # Windows
flutter run -d linux     # Linux
```

Requires Flutter 3.47.6 / Dart 3.13.5, Java 17.
Platforms: **Android, Web, Windows, Linux only — no iOS, no macOS.**

## CI — GitHub Actions (public repo = unlimited minutes)

`.github/workflows/build.yml` builds on every push to `main`:
Android APK release, Web release, Windows release, Linux release.
Each build is uploaded as a workflow artifact. No iOS/macOS jobs.
`flutter analyze` and `flutter test` run in the Android job.

## Tests

```sh
flutter test   # widget tests: syllabus count, stage toggle, subject chip,
               # search, paper filter, theme toggle, bottom nav,
               # Pomodoro countdown/pause/reset
```

## Firebase setup (required for online features)

The app runs in **LOCAL-ONLY mode** until you connect a real Firebase
project. In local-only mode everything on-device works — tracker progress,
Pomodoro, per-chapter notes, milestones, badges, daily plan — but accounts,
community, groups, leaderboard, cloud sync and push notifications do not.

### What works offline vs what needs config

| Works offline (no setup) | Needs Firebase config |
|---|---|
| Tracker progress (151 chapters / 906 milestones) | Email + OTP registration, Google sign-in |
| Per-chapter notes (text + photo, on-device) | Universal community, polls, voice messages |
| Milestones + badges, streak, daily target plan | Leaderboard, follow, profiles, cover photo |
| Offline queue — work done offline auto-syncs later | Groups (6-char join codes), admin panel, FCM |

### Steps (Rafi)

1. Go to https://console.firebase.google.com and create a project
   (any name, e.g. `hsc-revision-master`).
2. **Add an Android app**: package name `com.example.hsc_revision_master`
   (or your own id — it must match `android/app/build.gradle.kts`).
   Download `google-services.json` into `android/app/`.
3. **Add a Web app** in the same project. Copy the config values it shows
   (`apiKey`, `appId`, `messagingSenderId`, `projectId`, `storageBucket`)
   into `lib/firebase_options.dart`, replacing every
   `TODO — replace with real Firebase project config` value.
   (Or run `flutterfire configure` to regenerate that file.)
4. **Authentication**: in the Firebase console → Authentication →
   Sign-in method → enable **Email/Password** and **Google**.
5. **Firestore**: console → Firestore Database → Create database
   (production mode; the app creates collections `users`, `messages`,
   `notes`, `groups`, `reports`, `email_otps` itself).
6. **Storage**: console → Storage → Get started (default bucket).
   The app uploads to `community/...` and `notes/<uid>/<chapterId>.jpg`.
7. **FCM**: console → Cloud Messaging — no extra step for Android;
   for Web, FCM needs a `firebase-messaging-sw.js` service worker
   (not included yet — push on web is a TODO).
8. Run `flutter pub get` and rebuild. When the real config is in place,
   `FirebaseInit.isOnlineMode` becomes true and the auth screen appears.

### Local-fallback admin

The first user to register on a fresh install becomes the admin on that
device (uid stored in SharedPreferences key `first-user-uid`) until a real
flag is set. To make an admin properly, set `isAdmin: true` on that user's
document in Firestore collection `users` in the console.

### Known TODOs / honest limits

- **OTP email sending is NOT implemented**: `AuthService.sendOtp` only
  stores a SHA-256 hash + 10-minute expiry in Firestore collection
  `email_otps`. Firebase Auth cannot send a custom OTP email, so a backend
  (Cloud Function / small server + SMTP) is needed to actually email the
  code. In local-only mode the plain code is stored under
  `demo-otp-<email>` in SharedPreferences so the UI can show it labelled
  "demo code (no email configured)" — in online mode the code is never
  shown anywhere.
- **Voice recording is a stub**: `VoiceService` returns null until the
  `record` + `just_audio` packages are added (kept out to keep the build
  light). The UI shows "voice recording coming soon" — nothing is faked.
- **Weekly leaderboard filter is a TODO**: `leaderboardWeekly` orders by
  all-time `totalChaptersDone`; a true weekly ranking needs a
  `chaptersDoneThisWeek` counter field in Firestore first.
- **FCM server send is a TODO**: the app can receive pushes and shows
  milestone notifications in-app, but sending a push to other devices
  needs a server / Cloud Function — the app never fakes a server send.
- Group creation while offline is kept on-device only and is not synced
  yet (only `message` and `note` queue ops replay in `SyncService`).

## Licence

GPL-3.0-only, same as the original repo. Credit the original repo if you
share or publish this.

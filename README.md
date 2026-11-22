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

From [jimsiraj.pp.ua](https://jimsiraj.pp.ua/) ("Jim, a soft sketchbook"):
paper `#FAF8F4`, card `#FFFFFF`, ink `#1C1A17`, muted `#6F6A62`,
line `#E6E1D8`, soft-black `#2B2B2B` buttons, dusty rose `#A9716B` /
`#CF9A92` only for the progress ring, done states and small highlights.
Dark mode: background `#141315`, surface `#1D1D1F`, text `#FAF8F4`.

## Features

- Progress ring + counts (done / 906), weakest subject, exam target date
  picker, daily target = remaining tasks ÷ days left
- Today's Focus: next 5 pending chapters
- Chapter cards with 6 tappable stage chips (Archive, Note, Recall, MCQ,
  Live, Test Paper), search (Bangla + English), subject chips, paper filter,
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
flutter test   # widget tests: stage toggle, subject chip, search,
               # theme toggle, bottom nav, Pomodoro countdown/pause/reset
```

## Licence

GPL-3.0-only, same as the original repo. Credit the original repo if you
share or publish this.

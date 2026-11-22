# HSC Science Revision Master — Flutter app

Soft, smooth, phone-first HSC Science revision tracker.
**7 subjects, 151 chapters, 906 milestones** (151 × 6 stages per chapter),
verified against the original repo — no chapter invented.

## Design — Cupertino (iOS-style) on pure Flutter

The whole UI is Apple-style Cupertino: `CupertinoApp`, `CupertinoPageScaffold`
with a large-title-style navigation bar, `CupertinoTabScaffold` +
`CupertinoTabBar` (Today / All chapters / Focus / Exam plan), `CupertinoButton.filled`
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
- **Focus Mode** (Focus tab): 15/25/45/60-minute sessions with a
  whitelist of apps that stay usable. **Android only**, a native
  `FocusAccessibilityService` watches the foreground app while a session
  is on and shows a calm full-screen block overlay over any app that is
  not this app or whitelisted ("Focus cholche — ei app-ta ekhon bondho",
  with remaining time and an End focus button). Needs two permissions the
  app guides you to: the Accessibility service and "Draw over other
  apps" — blocking is never claimed to work until both are on. Stale
  sessions self-clear, so blocking can never stay on forever if the app
  is killed mid-focus. On web / Windows / Linux there is no system
  blocking: focus hides the other tabs and shows only the current
  chapter + timer. Whitelist and sessions live in SharedPreferences
  (`focus-whitelist-v1`, `focus-end-v1`).
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
               # theme toggle, bottom nav, Pomodoro countdown/pause/reset,
               # focus store persistence, stale-session clearing,
               # focus start/end, tab hiding on non-Android
```

## Licence

GPL-3.0-only, same as the original repo. Credit the original repo if you
share or publish this.

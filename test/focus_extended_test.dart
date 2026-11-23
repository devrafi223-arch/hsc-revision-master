import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hsc_revision_master/focus_schedule.dart';
import 'package:hsc_revision_master/focus_store.dart';
import 'package:hsc_revision_master/main.dart';
import 'package:hsc_revision_master/screens/focus_screen.dart';
import 'package:hsc_revision_master/services/hosts_blocker.dart';

void main() {
  test('schedule toggle persists across reload', () async {
    SharedPreferences.setMockInitialValues({});
    final schedule = FocusSchedule();
    await schedule.load();
    expect(schedule.hasAny, isFalse);

    final now = DateTime.now();
    schedule.setHours(now.weekday, now.hour, now.hour + 1, true);
    expect(schedule.isBlockedAt(now), isTrue);
    await schedule.save();

    final reloaded = FocusSchedule();
    await reloaded.load();
    expect(reloaded.isBlockedAt(now), isTrue);
    expect(reloaded.isHourBlocked(now.weekday, now.hour), isTrue);

    reloaded.toggleHour(now.weekday, now.hour);
    expect(reloaded.isBlockedAt(now), isFalse);
    await reloaded.save();

    final cleared = FocusSchedule();
    await cleared.load();
    expect(cleared.hasAny, isFalse);
  });

  test('schedule activeBlockEnd covers a contiguous run', () {
    final schedule = FocusSchedule();
    // Monday 8:00–11:00 (blocks 32..43).
    schedule.setHours(1, 8, 11, true);
    final mondayTen = DateTime(2026, 11, 23, 10, 30); // a Monday
    expect(mondayTen.weekday, 1);
    expect(schedule.isBlockedAt(mondayTen), isTrue);
    expect(
      schedule.activeBlockEnd(mondayTen),
      DateTime(2026, 11, 23, 11, 0),
    );
    // Outside the run there is no block end.
    expect(
      schedule.activeBlockEnd(DateTime(2026, 11, 23, 12, 0)),
      isNull,
    );
    // Corrupt JSON loads as an empty schedule, never crashes.
    final broken = FocusSchedule.fromJsonString('{not json');
    expect(broken.hasAny, isFalse);
  });

  test('locked session cannot be ended early', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusStore();
    await store.load();
    await store.setLocked(true);
    expect(store.locked, isTrue);

    await store.start(minutes: 25);
    expect(store.isActive, isTrue);
    expect(store.canEnd, isFalse);
    expect(store.lockedLabel, contains('Locked'));

    // Early end is refused and the session stays active.
    expect(await store.tryEnd(), isFalse);
    expect(store.isActive, isTrue);

    // Unlocking allows the end.
    await store.setLocked(false);
    expect(store.canEnd, isTrue);
    expect(await store.tryEnd(), isTrue);
    expect(store.isActive, isFalse);
  });

  test('daily caps and desktop whitelist persist across reload', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusStore();
    await store.load();

    await store.setCap('com.example.video', 30);
    await store.setCap('com.example.social', 60);
    await store.toggleDesktopWhitelisted('notepad.exe');
    expect(store.caps['com.example.video'], 30);
    expect(store.isDesktopWhitelisted('Notepad.EXE'), isTrue);

    final reloaded = FocusStore();
    await reloaded.load();
    expect(reloaded.caps['com.example.video'], 30);
    expect(reloaded.caps['com.example.social'], 60);
    expect(reloaded.isDesktopWhitelisted('notepad.exe'), isTrue);

    await reloaded.removeCap('com.example.video');
    await reloaded.toggleDesktopWhitelisted('notepad.exe');
    final cleared = FocusStore();
    await cleared.load();
    expect(cleared.caps.containsKey('com.example.video'), isFalse);
    expect(cleared.isDesktopWhitelisted('notepad.exe'), isFalse);
  });

  test('hosts blocker writes and removes its section on a temp file',
      () async {
    final temp = await Directory.systemTemp.createTemp('hosts-test');
    final path = '${temp.path}/hosts';
    final file = File(path);
    await file.writeAsString('127.0.0.1 localhost\n');

    expect(await HostsBlocker.canWrite(hostsPath: path), isTrue);
    expect(await HostsBlocker.isApplied(hostsPath: path), isFalse);

    expect(
      await HostsBlocker.apply(['youtube.com', 'facebook.com'],
          hostsPath: path),
      isTrue,
    );
    var content = await file.readAsString();
    expect(content, contains('# HSC-FOCUS-BLOCK-START'));
    expect(content, contains('127.0.0.1 youtube.com'));
    expect(content, contains('127.0.0.1 localhost'));
    expect(await HostsBlocker.isApplied(hostsPath: path), isTrue);

    // Applying again does not duplicate the section.
    await HostsBlocker.apply(['youtube.com'], hostsPath: path);
    content = await file.readAsString();
    expect('# HSC-FOCUS-BLOCK-START'.allMatches(content).length, 1);

    expect(await HostsBlocker.remove(hostsPath: path), isTrue);
    content = await file.readAsString();
    expect(content, isNot(contains('# HSC-FOCUS-BLOCK-START')));
    expect(content, contains('127.0.0.1 localhost'));
    await temp.delete(recursive: true);
  });

  testWidgets('schedule auto-starts focus inside a blocked run',
      (tester) async {
    // flutter_test reports defaultTargetPlatform as Android, so override
    // it to Linux to exercise the non-Android (in-app only) focus path.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    // Schedule covering right now (this weekday, this hour).
    final now = DateTime.now();
    final hour = now.hour;
    final blocks = [hour * 4, hour * 4 + 1, hour * 4 + 2, hour * 4 + 3];
    SharedPreferences.setMockInitialValues({
      'focus-schedule-v1': jsonEncode({'${now.weekday}': blocks}),
    });

    await tester.pumpWidget(const HscRevisionApp());
    // Let the async store/schedule loads finish (no pumpAndSettle:
    // the 30s schedule ticker fires during it and the focus screen's
    // 1s ticker would keep scheduling frames afterwards).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CupertinoTabBar), findsOneWidget);

    // Fire the 30-second schedule ticker: focus auto-starts.
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // In-app focus view: the tab bar is gone, only the timer + End remain.
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(find.byKey(const Key('focus-remaining')), findsOneWidget);
    expect(find.byKey(const Key('focus-end')), findsOneWidget);

    // Reset inside the test body: the framework verifies foundation
    // debug variables are unset before tearDowns run.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('locked session disables the End button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusStore();
    await store.load();
    await store.setLocked(true);
    await store.start(minutes: 25);

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: FocusScreen(
            store: store,
            schedule: FocusSchedule(),
            focusChapter: null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('focus-remaining')), findsOneWidget);
    expect(find.textContaining('Locked'), findsOneWidget);
    final endButton =
        tester.widget<CupertinoButton>(find.byKey(const Key('focus-end')));
    expect(endButton.onPressed, isNull);
    expect(store.isActive, isTrue);
  });
}

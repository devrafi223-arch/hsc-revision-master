import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hsc_revision_master/focus_schedule.dart';
import 'package:hsc_revision_master/focus_store.dart';
import 'package:hsc_revision_master/main.dart';
import 'package:hsc_revision_master/screens/focus_screen.dart';

void main() {
  test('whitelist add/remove persists across reload', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusStore();
    await store.load();
    expect(store.whitelist, isEmpty);

    await store.toggleWhitelisted('com.example.calculator');
    expect(store.isWhitelisted('com.example.calculator'), isTrue);

    final reloaded = FocusStore();
    await reloaded.load();
    expect(reloaded.isWhitelisted('com.example.calculator'), isTrue);

    await reloaded.toggleWhitelisted('com.example.calculator');
    expect(reloaded.isWhitelisted('com.example.calculator'), isFalse);
  });

  test('start/end focus toggles active state and persists end time', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusStore();
    await store.load();
    expect(store.isActive, isFalse);

    await store.start(minutes: 25, chapterId: 'phy1_1');
    expect(store.isActive, isTrue);
    // 25 minutes minus the few seconds the test itself took.
    expect(store.remaining.inSeconds, greaterThan(1400));
    expect(store.remaining.inSeconds, lessThanOrEqualTo(1500));
    expect(store.remainingLabel.length, 5); // mm:ss

    final reloaded = FocusStore();
    await reloaded.load();
    expect(reloaded.isActive, isTrue);
    expect(reloaded.focusChapterId, 'phy1_1');

    await reloaded.end();
    expect(reloaded.isActive, isFalse);
    expect(reloaded.endTime, isNull);
  });

  test('stale session auto-clears on load', () async {
    final past = DateTime.now()
        .subtract(const Duration(minutes: 30))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'focus-end-v1': past,
      'focus-chapter-v1': 'phy1_1',
    });
    final store = FocusStore();
    await store.load();
    expect(store.isActive, isFalse);
    expect(store.endTime, isNull);
    expect(store.focusChapterId, isNull);
  });

  testWidgets('focus screen renders setup and start/end toggles state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusStore();
    await store.load();

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
    await tester.pump();

    expect(find.text('Focus mode'), findsOneWidget);
    expect(find.byKey(const Key('focus-start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-start')));
    // _startFocus awaits the SharedPreferences save: advance time so the
    // async work and the rebuild complete (not pumpAndSettle — the
    // 1-second ticker keeps scheduling frames).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.isActive, isTrue);
    expect(find.byKey(const Key('focus-end')), findsOneWidget);
    expect(find.byKey(const Key('focus-remaining')), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-end')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.isActive, isFalse);
    expect(find.byKey(const Key('focus-start')), findsOneWidget);
  });

  testWidgets('home screen Focus tab opens the focus screen',
      (tester) async {
    // The Focus screen is tall now (session + schedule + permissions +
    // whitelist cards), so give the test a tall viewport — the whole
    // screen fits without scrolling. (scrollUntilVisible can't be used:
    // the schedule card's horizontal day-chips list is a second
    // Scrollable, so the default scrollable finder is ambiguous.)
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 2600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HscRevisionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Focus'));
    // Let the Cupertino tab transition finish.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Focus mode'), findsOneWidget);
    expect(find.text('Apps that stay usable'), findsOneWidget);
  });

  testWidgets('starting focus on non-Android hides the other tabs',
      (tester) async {
    // flutter_test reports defaultTargetPlatform as Android, so override
    // it to Linux to exercise the non-Android (in-app only) focus path.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HscRevisionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Focus'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('focus-start')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // In-app focus view: the tab bar is gone, only the timer + End remain.
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(find.byKey(const Key('focus-end')), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-end')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    // Reset inside the test body: the framework verifies foundation
    // debug variables are unset before tearDowns run.
    debugDefaultTargetPlatformOverride = null;
  });
}

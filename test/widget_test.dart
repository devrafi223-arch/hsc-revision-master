import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hsc_revision_master/data/syllabus.dart';
import 'package:hsc_revision_master/main.dart';
import 'package:hsc_revision_master/widgets/pomodoro_timer.dart';

void main() {
  // Boots the app and enters the tracker through the auth gate's
  // "Continue offline" path (local-only mode: no Firebase account).
  Future<void> enterApp(WidgetTester tester) async {
    await tester.pumpWidget(const HscRevisionApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue offline'));
    await tester.pumpAndSettle();
  }

  test('syllabus has the verified 151 chapters / 906 milestones', () {
    expect(totalChapters, 151);
    expect(totalMilestones, 906);
    expect(syllabusData.length, 7);
    expect(revisionStages.length, 6);
    final ids = allChapters.map((c) => c.id).toList();
    expect(ids.toSet().length, 151, reason: 'no duplicate chapter IDs');
  });

  testWidgets('stage chip tap toggles a chapter from 0/6 to 1/6', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    await tester.tap(find.text('All chapters'));
    await tester.pumpAndSettle();

    expect(find.text('0/6', skipOffstage: false), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('stage-phy1_1-archive')));
    await tester.pumpAndSettle();
    expect(find.text('1/6'), findsOneWidget);
  });

  testWidgets('subject chip filters the chapter list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    await tester.tap(find.text('All chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subject-physics')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 21 of 151 chapters'), findsOneWidget);
  });

  testWidgets('search filters by English chapter title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    await tester.tap(find.text('All chapters'));
    await tester.pumpAndSettle();
    // The Community tab builds text fields too, so target the All-tab
    // search field by its key rather than by type.
    await tester.enterText(find.byKey(const Key('search-field')), 'Vectors');
    await tester.pumpAndSettle();
    // 'Vectors' matches two chapters: Physics Ch.2 and Higher Math Ch.2.
    expect(find.text('Showing 2 of 151 chapters'), findsOneWidget);
  });

  testWidgets('paper segmented control filters to 1st-paper chapters', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    await tester.tap(find.text('All chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1st paper'));
    await tester.pumpAndSettle();
    // 75 first-paper chapters + ICT's 6 single-paper chapters, which the
    // app shows under both paper filters (paper == 0 is never excluded).
    expect(find.text('Showing 81 of 151 chapters'), findsOneWidget);
  });

  testWidgets('theme switch toggles night mode on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    final switchFinder = find.byKey(const Key('theme-toggle'));
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);
  });

  testWidgets('Cupertino tab bar switches between Today, All, Community and Profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    expect(find.byType(CupertinoTabBar), findsOneWidget);
    // The Today tab is a long list now (target + plan cards sit above
    // Today's Focus), so scroll it into view before asserting.
    await tester.scrollUntilVisible(
      find.textContaining("Today's Focus"),
      200,
    );
    expect(find.textContaining("Today's Focus"), findsOneWidget);
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    expect(find.text('Community'), findsWidgets);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('You are not signed in.'), findsOneWidget);
    await tester.tap(find.text('All chapters'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 151 of 151 chapters'), findsOneWidget);
  });

  testWidgets('Pomodoro start counts down and pause stops it', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(child: PomodoroTimer(initialDuration: Duration(seconds: 3))),
        ),
      ),
    );
    expect(find.text('00:03'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pomodoro-start')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:01'), findsOneWidget);

    // The same button now says Pause — tapping it stops the countdown.
    await tester.tap(find.byKey(const Key('pomodoro-start')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:01'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pomodoro-reset')));
    await tester.pump();
    expect(find.text('00:03'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hsc_revision_master/data/syllabus.dart';
import 'package:hsc_revision_master/main.dart';
import 'package:hsc_revision_master/screens/home_screen.dart';
import 'package:hsc_revision_master/widgets/pomodoro_timer.dart';

/// Test harness mirroring HscRevisionApp's wiring: HomeScreen with a
/// local night-mode toggle. The auth gate has no offline bypass
/// anymore, so tests enter the tracker directly.
class _TestApp extends StatefulWidget {
  const _TestApp();

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: jimTheme(dark: _dark),
      home: HomeScreen(
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

void main() {
  Future<void> enterApp(WidgetTester tester) async {
    await tester.pumpWidget(const _TestApp());
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

  testWidgets('stage chip tap toggles a chapter from 0/6 to 1/6',
      (tester) async {
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

  testWidgets('paper segmented control filters to 1st-paper chapters',
      (tester) async {
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
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
  });

  testWidgets('Today target to-do: add, tick off, delete', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    expect(find.text('Today’s target'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('todo-input')),
      'Revise Physics Ch 3',
    );
    await tester.ensureVisible(find.byKey(const Key('todo-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('todo-add')));
    await tester.pumpAndSettle();

    expect(find.text('Revise Physics Ch 3'), findsOneWidget);
    expect(find.text('0/1 done'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pumpAndSettle();
    expect(find.text('1/1 done'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    expect(find.text('Revise Physics Ch 3'), findsNothing);
  });

  testWidgets('Reset needs Confirm typed in Settings danger zone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reset all progress'),
      200,
    );
    // scrollUntilVisible stops as soon as any part of the row is on
    // screen — the row can end up straddling the bottom edge, so bring
    // it fully into view before tapping its centre.
    await tester.ensureVisible(find.text('Reset all progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset all progress'));
    await tester.pumpAndSettle();

    expect(find.text('Reset all progress?'), findsOneWidget);
    final resetButton = find.widgetWithText(TextButton, 'Reset');
    expect(tester.widget<TextButton>(resetButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Confirm');
    await tester.pump();
    expect(tester.widget<TextButton>(resetButton).onPressed, isNotNull);
  });

  testWidgets(
      'Material navigation bar switches between Today, All, Community and Profile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await enterApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    // The Today tab is a long list now (target + plan cards sit above
    // Today's Focus), so scroll it into view before asserting.
    // NOTE: the to-do input field owns its own Scrollable, so the
    // scrollable must be named explicitly here (the page ListView's
    // Scrollable is the first one in the tree).
    await tester.scrollUntilVisible(
      find.textContaining("Today's Focus"),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining("Today's Focus"), findsOneWidget);
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    // The Community tab has no AppBar of its own (the HomeScreen AppBar
    // stays on top), so 'Community' appears exactly once — the
    // NavigationBar destination label.
    expect(find.text('Community'), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('You are not signed in.'), findsOneWidget);
    await tester.tap(find.text('All chapters'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 151 of 151 chapters'), findsOneWidget);
  });

  testWidgets('Pomodoro start counts down and pause stops it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
              child: PomodoroTimer(initialDuration: Duration(seconds: 3))),
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

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/syllabus.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/supabase_init.dart';
import 'services/messaging_service.dart';
import 'services/sync_service.dart';

/// Jim portfolio palette (jimsiraj.pp.ua, "Jim, a soft sketchbook"),
/// softened for the airy redesign: warm OFF-WHITE background #F8F6F1
/// (never stark white), cards soft white #FFFFFF, ink #1C1A17,
/// muted #6F6A62, soft line #E9E4DA, soft black #2B2B2B buttons,
/// dusty rose #A9716B / #CF9A92 only for the progress ring, done states
/// and small highlights.
/// Dark: background #17161A, surface #211F22, text #FAF8F4.
class JimColors {
  static const paper = Color(0xFFF8F6F1);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C1A17);
  static const muted = Color(0xFF6F6A62);
  static const line = Color(0xFFE9E4DA);
  static const softBlack = Color(0xFF2B2B2B);
  static const rose = Color(0xFFA9716B);
  static const roseLight = Color(0xFFCF9A92);
  static const darkBg = Color(0xFF17161A);
  static const darkSurface = Color(0xFF211F22);
  static const darkText = Color(0xFFFAF8F4);
  static const darkMuted = Color(0xFFA8A29A);
  static const darkLine = Color(0xFF333136);
}

/// Cupertino theme built on the Jim palette. Cupertino's default blue is
/// never used: primaryColor is the soft black (paper-white text on dark).
CupertinoThemeData _cupertinoTheme({required bool dark}) {
  return CupertinoThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    primaryColor: dark ? JimColors.darkText : JimColors.softBlack,
    primaryContrastingColor: dark ? JimColors.softBlack : CupertinoColors.white,
    barBackgroundColor: dark ? JimColors.darkBg : JimColors.paper,
    scaffoldBackgroundColor: dark ? JimColors.darkBg : JimColors.paper,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(
        color: dark ? JimColors.darkText : JimColors.ink,
        fontFamily: '.SF Pro Text',
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase + push setup. Both are fully guarded and never throw: while
  // lib/supabase_config.dart still holds the placeholder values the app
  // runs in LOCAL-ONLY mode (see lib/services/supabase_init.dart).
  try {
    await SupabaseInit.initialize();
  } catch (_) {
    // Local-only mode.
  }
  try {
    await MessagingService.init();
  } catch (_) {
    // Push notifications unavailable — the app keeps working.
  }
  // Starts the connectivity listener so queued offline work syncs when
  // the device comes back online, and tries one immediate sync.
  unawaited(SyncService.instance.syncNow());
  // The verified syllabus must never silently lose a chapter.
  assert(totalChapters == 151, 'Syllabus must have 151 chapters');
  assert(totalMilestones == 906, 'Syllabus must have 906 milestones');
  runApp(const HscRevisionApp());
}

class HscRevisionApp extends StatefulWidget {
  const HscRevisionApp({super.key});

  @override
  State<HscRevisionApp> createState() => _HscRevisionAppState();
}

class _HscRevisionAppState extends State<HscRevisionApp> {
  bool _dark = false;

  /// True after the user taps "Continue offline" on the auth screen.
  /// The tracker then opens with the REAL app-level theme wiring —
  /// never a pushed copy of HomeScreen (pushing one nested it inside
  /// the Profile tab and doubled the nav bar + header).
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _dark = prefs.getBool('night-mode') ?? false);
    });
  }

  Future<void> _toggleTheme() async {
    final next = !_dark;
    setState(() => _dark = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('night-mode', next);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'HSC Science Revision Master',
      debugShowCheckedModeBanner: false,
      theme: _cupertinoTheme(dark: _dark),
      // Auth gate (v3): signed-out users see the auth screen, signed-in
      // users see the tracker. In local-only mode AuthService emits null
      // (no account exists without Supabase), so the auth screen shows
      // until Supabase is configured; the auth screen itself explains
      // local-only mode.
      home: StreamBuilder<String?>(
        stream: AuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          final signedIn = snapshot.data != null;
          if (signedIn && _offline) {
            // Signed in now — the offline bypass is no longer needed.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _offline = false);
            });
          }
          if (signedIn || _offline) {
            return HomeScreen(
              dark: _dark,
              onToggleTheme: _toggleTheme,
            );
          }
          return AuthScreen(
            onContinueOffline: () => setState(() => _offline = true),
          );
        },
      ),
    );
  }
}

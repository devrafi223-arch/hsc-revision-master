import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/syllabus.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/app_log.dart';
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

/// Material 3 theme built on the Jim palette. The old iOS blue is
/// never used: primary is the soft black (paper-white text on dark),
/// rose is reserved for progress, done states and small highlights.
ThemeData jimTheme({required bool dark}) {
  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: dark ? JimColors.darkText : JimColors.softBlack,
    onPrimary: dark ? JimColors.softBlack : Colors.white,
    secondary: JimColors.rose,
    onSecondary: Colors.white,
    tertiary: JimColors.roseLight,
    surface: dark ? JimColors.darkSurface : JimColors.card,
    onSurface: dark ? JimColors.darkText : JimColors.ink,
    error: Colors.red,
    onError: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? JimColors.darkBg : JimColors.paper,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? JimColors.darkBg : JimColors.paper,
      foregroundColor: dark ? JimColors.darkText : JimColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? JimColors.darkBg : JimColors.paper,
      indicatorColor: JimColors.rose.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: dark ? JimColors.darkText : JimColors.softBlack,
          );
        }
        return IconThemeData(
          color: dark ? JimColors.darkMuted : JimColors.muted,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected
              ? (dark ? JimColors.darkText : JimColors.softBlack)
              : (dark ? JimColors.darkMuted : JimColors.muted),
        );
      }),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return JimColors.rose;
        return null;
      }),
    ),
  );
}

/// Shared rounded text-field decoration in the Jim palette, so every
/// field in the app looks the same without repeating the border code.
InputDecoration jimFieldDecoration({
  required bool dark,
  required String hint,
  double borderRadius = 16,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.all(16),
  Widget? prefixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(borderRadius),
    borderSide: BorderSide(color: dark ? JimColors.darkLine : JimColors.line),
  );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: dark ? JimColors.darkSurface : JimColors.card,
    contentPadding: contentPadding,
    prefixIcon: prefixIcon,
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: const BorderSide(color: JimColors.rose, width: 1.5),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Error capture FIRST: any uncaught error is written to the log
  // (in-memory + file next to the exe on Windows) and pops up once,
  // so Rafi can copy it to Arlo instead of a black screen with no
  // explanation. Without this a release-mode build failure is silent.
  FlutterError.onError = (details) {
    AppLog.error(
      'flutter',
      '${details.exceptionAsString()}\n${details.stack ?? ''}',
    );
    AppLog.maybeShowErrorPopup();
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('uncaught', '$error\n$stack');
    AppLog.maybeShowErrorPopup();
    return true;
  };
  await AppLog.init();
  AppLog.info('app', 'starting');
  // Supabase + push setup. Both are fully guarded and never throw: while
  // lib/supabase_config.dart still holds the placeholder values the app
  // runs in LOCAL-ONLY mode (see lib/services/supabase_init.dart).
  try {
    // NEVER let the network block the first frame: Supabase.initialize()
    // is awaited before runApp and a stalled TLS/network call has no
    // timeout of its own — on a bad connection the app used to stay a
    // black window forever (Windows, 2026-11-23). 12s is plenty on a
    // normal connection; on timeout the app starts offline and the auth
    // screen offers Try again.
    final online = await SupabaseInit.initialize().timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        AppLog.warn(
          'startup',
          'Supabase init timed out after 12s — continuing offline',
        );
        return false;
      },
    );
    AppLog.info('startup', 'Supabase init done: online=$online');
  } catch (e) {
    AppLog.warn('startup', 'Supabase init failed: $e');
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
  // Proves the UI painted: if the log has this line but the screen is
  // black, the problem is rendering, not startup.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AppLog.info('app', 'first frame painted');
  });
}

class HscRevisionApp extends StatefulWidget {
  const HscRevisionApp({super.key});

  @override
  State<HscRevisionApp> createState() => _HscRevisionAppState();
}

class _HscRevisionAppState extends State<HscRevisionApp> {
  bool _dark = false;

  StreamSubscription<bool>? _recoverySub;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _dark = prefs.getBool('night-mode') ?? false);
    });
    // Recovery state lives in AuthService.recoveryPending (set by the
    // passwordRecovery auth event for the mail-link flow, and by
    // verifyRecoveryCode for the code flow). Rebuild when it changes.
    AuthService.recoveryPending.addListener(_onRecoveryChanged);
    _recoverySub =
        AuthService.instance.passwordRecoveryChanges.listen((recovering) {
      if (recovering) AuthService.recoveryPending.value = true;
    });
  }

  void _onRecoveryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AuthService.recoveryPending.removeListener(_onRecoveryChanged);
    _recoverySub?.cancel();
    super.dispose();
  }

  Future<void> _toggleTheme() async {
    final next = !_dark;
    setState(() => _dark = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('night-mode', next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HSC Science Revision Master',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppLog.navigatorKey,
      theme: jimTheme(dark: _dark),
      // Auth gate (v3): signed-out users see the auth screen, signed-in
      // users see the tracker. In local-only mode AuthService emits null
      // (no account exists without Supabase), so the auth screen shows
      // until Supabase is configured; the auth screen itself explains
      // local-only mode.
      home: StreamBuilder<String?>(
        stream: AuthService.instance.authStateChanges,
        builder: (context, snapshot) {
          // No offline bypass (Rafi): login is mandatory. Offline is
          // only shown AFTER login, when the device loses internet
          // (the "Offline — will sync" pill on the Today tab).
          if (AuthService.recoveryPending.value) {
            return ResetPasswordScreen(
              onDone: () => AuthService.recoveryPending.value = false,
            );
          }
          if (snapshot.data != null) {
            return HomeScreen(
              dark: _dark,
              onToggleTheme: _toggleTheme,
            );
          }
          return const AuthScreen();
        },
      ),
    );
  }
}

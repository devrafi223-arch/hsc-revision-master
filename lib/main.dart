import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/syllabus.dart';
import 'screens/admin_gate_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_log.dart';
import 'services/auth_service.dart';
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
  // Restore the JWT session (custom backend). Optimistic: a stored
  // token opens the app even offline (the tracker is local-first);
  // a 401 from GET /api/auth/me clears it and the login screen
  // shows. NEVER let the network block the first frame: the restore
  // is capped at 12 s — on a bad connection the app used to stay a
  // black window forever (Windows, 2026-11-23).
  try {
    final restored = await AuthService.instance.restoreSession().timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        AppLog.warn(
          'startup',
          'Session restore timed out after 12s — continuing',
        );
        return AuthService.instance.isSignedIn;
      },
    );
    AppLog.info('startup', 'session restore done: signedIn=$restored');
  } catch (e) {
    AppLog.warn('startup', 'Session restore failed: $e');
  }
  // NOTE: no guest mode and no device-admin fallback (Rafi,
  // 2026-11-24): without a valid JWT the app shows the login screen,
  // and the admin panel is securely locked at the web /admin route
  // behind an email + 6-digit code sign-in and a strict
  // users.is_admin check. The old recordFirstUser call is deleted
  // with it.
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
    // Web only: the /admin URL opens the locked admin gate instead of
    // the tracker. There is no link to it from the app UI.
    final isAdminRoute = kIsWeb &&
        (Uri.base.path == '/admin' || Uri.base.path == '/admin/');
    return MaterialApp(
      title: 'HSC Science Revision Master',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppLog.navigatorKey,
      theme: jimTheme(dark: _dark),
      // Login gate (Rafi, 2026-11-24): no guest mode — without a valid
      // JWT the app shows the login screen. The signedIn notifier
      // flips on login / logout / a 401, and the root rebuilds.
      // The admin panel lives only at /admin (web), behind an admin
      // sign-in.
      home: isAdminRoute
          ? const AdminGateScreen()
          : ValueListenableBuilder<bool>(
              valueListenable: AuthService.instance.signedIn,
              builder: (context, signedIn, _) {
                if (!signedIn) return const AuthScreen();
                return HomeScreen(
                  dark: _dark,
                  onToggleTheme: _toggleTheme,
                );
              },
            ),
    );
  }
}

import 'package:flutter/cupertino.dart';

import 'data/syllabus.dart';
import 'screens/home_screen.dart';

/// Jim portfolio palette (jimsiraj.pp.ua, "Jim, a soft sketchbook"):
/// paper #FAF8F4, card #FFFFFF, ink #1C1A17, muted #6F6A62, line #E6E1D8,
/// soft black #2B2B2B buttons, dusty rose #A9716B / #CF9A92 only for the
/// progress ring, done states and small highlights.
/// Dark: background #141315, surface #1D1D1F, text #FAF8F4.
class JimColors {
  static const paper = Color(0xFFFAF8F4);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C1A17);
  static const muted = Color(0xFF6F6A62);
  static const line = Color(0xFFE6E1D8);
  static const softBlack = Color(0xFF2B2B2B);
  static const rose = Color(0xFFA9716B);
  static const roseLight = Color(0xFFCF9A92);
  static const darkBg = Color(0xFF141315);
  static const darkSurface = Color(0xFF1D1D1F);
  static const darkText = Color(0xFFFAF8F4);
  static const darkMuted = Color(0xFFA8A29A);
  static const darkLine = Color(0xFF2E2E30);
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

void main() {
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

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'HSC Science Revision Master',
      debugShowCheckedModeBanner: false,
      theme: _cupertinoTheme(dark: _dark),
      home: HomeScreen(
        dark: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

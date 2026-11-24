import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'log_screen.dart';

/// Notification settings, font size, language and theme.
///
/// Font size is stored in SharedPreferences key `font-size` and exposed
/// as [SettingsScreen.fontScale] for any screen that wants it. NOTE:
/// HomeScreen does NOT consume fontScale yet — applying it across the
/// tracker is a follow-up, not part of this screen.
///
/// Language is stored in `app-lang` ('en' | 'bn'). There is no existing
/// language mechanism in HomeScreen, so this screen owns the preference;
/// actually switching the app's strings is a follow-up.
///
/// Dark mode reuses the app's existing theme mechanism: pass the current
/// [dark] value and [onToggleTheme] from HomeScreen. When they are not
/// passed, the toggle is hidden and the Today tab's switch stays the
/// way to change the theme.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen(
      {super.key, this.dark, this.onToggleTheme, this.onResetAll});

  final bool? dark;
  final VoidCallback? onToggleTheme;

  /// Clears all tracker progress. Shown under Danger zone, gated
  /// behind typing "Confirm". Null hides the section.
  final Future<void> Function()? onResetAll;

  /// Font scale for the chosen size: Small 0.9, Medium 1.0, Large 1.15.
  /// Updated whenever the user picks a size here.
  static double fontScale = 1.0;

  static const Map<String, double> _fontScales = {
    'small': 0.9,
    'medium': 1.0,
    'large': 1.15,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: _SettingsBody(
          dark: dark,
          onToggleTheme: onToggleTheme,
          onResetAll: onResetAll,
        ),
      ),
    );
  }
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody(
      {required this.dark, required this.onToggleTheme, this.onResetAll});

  final bool? dark;
  final VoidCallback? onToggleTheme;
  final Future<void> Function()? onResetAll;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  bool _loaded = false;
  bool _notifMilestone = true;
  bool _notifReminder = true;
  bool _notifReplies = true;
  String _fontSize = 'medium';
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifMilestone = prefs.getBool('notif-milestone') ?? true;
      _notifReminder = prefs.getBool('notif-reminder') ?? true;
      _notifReplies = prefs.getBool('notif-replies') ?? true;
      _fontSize = prefs.getString('font-size') ?? 'medium';
      _lang = prefs.getString('app-lang') ?? 'en';
      SettingsScreen.fontScale = SettingsScreen._fontScales[_fontSize] ?? 1.0;
      _loaded = true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// Danger zone: reset needs the word "Confirm" typed in — a stray
  /// tap can never wipe progress.
  Future<void> _confirmReset() async {
    final controller = TextEditingController();
    var typed = '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reset all progress?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Every tick will be cleared. This cannot be undone.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: jimFieldDecoration(
                  dark: isDark,
                  hint: 'Type Confirm',
                ),
                onChanged: (value) => setDialogState(() => typed = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: typed == 'Confirm'
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || widget.onResetAll == null) return;
    await widget.onResetAll!();
    if (!mounted) return;
    Navigator.of(context).pop(); // back to the Today tab to see the toast
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        title,
        style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? JimColors.darkSurface : JimColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: base.copyWith(fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: base.copyWith(
                    fontSize: 13,
                    color: muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeTrackColor: JimColors.rose,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sectionTitle(context, 'Notifications'),
        _switchRow(
          label: 'Milestone alerts',
          hint: 'Celebrate when a chapter is finished (6/6).',
          value: _notifMilestone,
          onChanged: (v) {
            setState(() => _notifMilestone = v);
            _saveBool('notif-milestone', v);
          },
        ),
        const SizedBox(height: 12),
        _switchRow(
          label: 'Daily reminder',
          hint: 'A morning nudge to revise today’s plan.',
          value: _notifReminder,
          onChanged: (v) {
            setState(() => _notifReminder = v);
            _saveBool('notif-reminder', v);
          },
        ),
        const SizedBox(height: 12),
        _switchRow(
          label: 'Community replies',
          hint: 'When someone replies to your message.',
          value: _notifReplies,
          onChanged: (v) {
            setState(() => _notifReplies = v);
            _saveBool('notif-replies', v);
          },
        ),
        _sectionTitle(context, 'Font size'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'small',
                  label: Text('Small'),
                ),
                ButtonSegment<String>(
                  value: 'medium',
                  label: Text('Medium'),
                ),
                ButtonSegment<String>(
                  value: 'large',
                  label: Text('Large'),
                ),
              ],
              selected: {_fontSize},
              onSelectionChanged: (selection) {
                final value = selection.first;
                setState(() {
                  _fontSize = value;
                  SettingsScreen.fontScale =
                      SettingsScreen._fontScales[value] ?? 1.0;
                });
                _saveString('font-size', value);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
                selectedBackgroundColor:
                    isDark ? JimColors.darkSurface : JimColors.card,
                selectedForegroundColor:
                    isDark ? JimColors.darkText : JimColors.ink,
              ),
            ),
          ),
        ),
        _sectionTitle(context, 'Language'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'en',
                  label: Text('English'),
                ),
                ButtonSegment<String>(
                  value: 'bn',
                  label: Text('বাংলা'),
                ),
              ],
              selected: {_lang},
              onSelectionChanged: (selection) {
                final value = selection.first;
                setState(() => _lang = value);
                _saveString('app-lang', value);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
                selectedBackgroundColor:
                    isDark ? JimColors.darkSurface : JimColors.card,
                selectedForegroundColor:
                    isDark ? JimColors.darkText : JimColors.ink,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            'Language preference is saved. Full Bangla translations arrive in a later update.',
            style: base.copyWith(fontSize: 13, color: muted, height: 1.45),
          ),
        ),
        _sectionTitle(context, 'Appearance'),
        if (widget.dark != null && widget.onToggleTheme != null)
          _switchRow(
            label: 'Night mode',
            hint: 'Dark sketchbook theme.',
            value: widget.dark!,
            onChanged: (_) => widget.onToggleTheme!(),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Change night mode from the switch on the Today tab.',
              style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
            ),
          ),
        _sectionTitle(context, 'Account'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: isDark ? JimColors.darkSurface : JimColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? JimColors.darkLine : JimColors.line,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed in as',
                        style: base.copyWith(
                          fontSize: 13,
                          color: muted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AuthService.instance.currentUser?.email ?? '',
                        style: base.copyWith(fontSize: 15, height: 1.45),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await AuthService.instance.signOut();
                    // The app root listens to AuthService.signedIn and
                    // shows the login screen again.
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
        _sectionTitle(context, 'Diagnostics'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: isDark ? JimColors.darkSurface : JimColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? JimColors.darkLine : JimColors.line,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const LogScreen(),
                ),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App logs',
                          style: base.copyWith(
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Startup, errors and network — copy them to Arlo when something goes wrong.',
                          style: base.copyWith(
                            fontSize: 13,
                            color: muted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.onResetAll != null) ...[
          _sectionTitle(context, 'Danger zone'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? JimColors.darkSurface : JimColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.4),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _confirmReset,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reset all progress',
                            style: base.copyWith(
                              fontSize: 15,
                              color: Colors.red,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Clears every tick. Cannot be undone — type Confirm to proceed.',
                            style: base.copyWith(
                              fontSize: 13,
                              color: muted,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

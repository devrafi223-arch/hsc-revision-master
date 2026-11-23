import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../data/syllabus.dart';
import '../focus_schedule.dart';
import '../focus_store.dart';
import '../main.dart';
import '../services/focus_channel.dart';
import '../services/focus_session.dart';
import '../services/hosts_blocker.dart';

/// Focus Mode screen — Cupertino style, same airy off-white design
/// (24px page padding, 20px card padding, 16px card gaps, w600 max).
///
/// What lives here:
/// - Focus sessions, with an optional locked mode (can't end early).
/// - Weekly schedule (Cold Turkey-style 15-min blocks, edited as
///   1-hour cells): focus auto-starts inside a blocked run.
/// - Whitelist (Android) and daily caps (Android, UsageStats).
/// - PC blocking (Windows/Linux): desktop whitelist + hosts-file
///   website blocking (needs admin — the UI says so, never pretends).
/// - Honest permission + limits copy.
///
/// On Android, starting focus also arms the native AccessibilityService:
/// any foreground app that is not this app and not whitelisted gets a
/// calm full-screen block overlay. On web / Windows / Linux there is no
/// system blocking — focus is in-app only (the parent hides the other
/// tabs while a session runs) and that is stated on screen, never hidden.
class FocusScreen extends StatefulWidget {
  const FocusScreen({
    super.key,
    required this.store,
    required this.schedule,
    required this.focusChapter,
    this.onFocusChanged,
  });

  final FocusStore store;
  final FocusSchedule schedule;
  final ChapterRef? focusChapter;
  final VoidCallback? onFocusChanged;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  final FocusChannel _channel = FocusChannel();
  List<InstalledApp> _apps = [];
  bool _appsLoaded = false;
  FocusPermissions? _permissions;
  Map<String, int> _usage = {};
  Timer? _ticker;
  int _selectedMinutes = 25;
  int _scheduleDay = DateTime.now().weekday;
  final TextEditingController _exeController = TextEditingController();
  bool _hostsApplied = false;
  bool _hostsWritable = false;

  bool get _isAndroid => FocusChannel.isSupported;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.store.durationMinutes;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.store.isActive) {
        setState(() {});
      } else if (widget.store.endTime != null) {
        // Session ran out while this screen was open: end it cleanly.
        // (Timer expiry, not a user end — no schedule dismiss here.)
        _expireSession();
      }
    });
    _loadNativeState();
    _loadDesktopState();
  }

  Future<void> _loadNativeState() async {
    if (!_isAndroid) return;
    final apps = await _channel.getInstalledApps();
    final permissions = await _channel.checkPermissions();
    final usage = await _channel.getDailyUsage();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _appsLoaded = true;
      _permissions = permissions;
      _usage = usage;
    });
  }

  Future<void> _loadDesktopState() async {
    if (!_isDesktop) return;
    _hostsApplied = await HostsBlocker.isApplied();
    _hostsWritable = await HostsBlocker.canWrite();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _exeController.dispose();
    super.dispose();
  }

  Future<void> _expireSession() async {
    await widget.store.end();
    widget.onFocusChanged?.call();
    await _channel.stopFocus();
    if (mounted) setState(() {});
  }

  Future<void> _syncRules() async {
    await FocusSession.sync(
      store: widget.store,
      schedule: widget.schedule,
      channel: _channel,
    );
  }

  Future<void> _startFocus() async {
    if (_isAndroid && _permissions != null && !_permissions!.allGranted) {
      final startAnyway = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Blocking needs two permissions'),
          content: const Text(
            'Without the Accessibility service and the overlay permission, '
            'other apps cannot be blocked — focus will only work inside '
            'this app. Open Settings to turn them on, or start anyway.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Open Settings'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start anyway'),
            ),
          ],
        ),
      );
      if (startAnyway != true) {
        if (_permissions!.accessibility == false) {
          await _channel.openAccessibilitySettings();
        } else {
          await _channel.openOverlaySettings();
        }
        final permissions = await _channel.checkPermissions();
        if (mounted) setState(() => _permissions = permissions);
        return;
      }
    }
    // Update the UI synchronously: the store sets endTime before its
    // (async) save, so the active view shows at once instead of waiting
    // for the persistence round-trip. The save finishes in the background.
    final startFuture = FocusSession.start(
      store: widget.store,
      schedule: widget.schedule,
      channel: _channel,
      end: DateTime.now().add(Duration(minutes: _selectedMinutes)),
      minutes: _selectedMinutes,
      chapterId: widget.focusChapter?.chapter.id,
    );
    if (mounted) setState(() {});
    widget.onFocusChanged?.call();
    await startFuture;
    if (mounted) setState(() {});
  }

  Future<void> _endFocus() async {
    // Rebuild immediately: the store fields are already cleared by the
    // synchronous prefix of FocusSession.end (canEnd is checked and the
    // session cleared before the first await), so the setup view shows
    // at once instead of waiting for the persistence + channel
    // round-trips. The saves finish in the background.
    final endFuture = FocusSession.end(
      store: widget.store,
      schedule: widget.schedule,
      channel: _channel,
    );
    if (mounted) setState(() {});
    widget.onFocusChanged?.call();
    final ended = await endFuture;
    if (!ended) {
      // Locked: nothing was cleared (canEnd returned false before any
      // mutation), so just tell the user why End did nothing.
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('This session is locked'),
          content: Text(widget.store.lockedLabel),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleLocked(bool value) async {
    await widget.store.setLocked(value);
    await _syncRules();
    if (mounted) setState(() {});
  }

  Future<void> _toggleScheduleHour(int hour) async {
    widget.schedule.toggleHour(_scheduleDay, hour);
    await widget.schedule.save();
    await _syncRules();
    if (mounted) setState(() {});
  }

  Future<void> _applySchedulePreset() async {
    // Weekdays 8:00–13:00, the classic school-morning block.
    for (var day = 1; day <= 5; day++) {
      widget.schedule.setHours(day, 8, 13, true);
    }
    await widget.schedule.save();
    await _syncRules();
    if (mounted) setState(() {});
  }

  Future<void> _clearScheduleDay() async {
    widget.schedule.clearDay(_scheduleDay);
    await widget.schedule.save();
    await _syncRules();
    if (mounted) setState(() {});
  }

  void _showAddCapSheet() {
    if (!_appsLoaded || _apps.isEmpty) return;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 420,
        color: CupertinoTheme.of(context).barBackgroundColor,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Pick an app to limit',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            const Text(
              'Tap an app — it starts at a 30-minute daily limit. '
              'Adjust it afterwards with − / +.',
              style: TextStyle(fontSize: 14, color: CupertinoColors.systemGrey),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: _apps
                    .where((a) => !widget.store.caps.containsKey(a.packageName))
                    .map(
                      (app) => CupertinoButton(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        onPressed: () async {
                          await widget.store.setCap(app.packageName, 30);
                          await _syncRules();
                          if (mounted) setState(() {});
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Text(app.label),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHosts(bool value) async {
    if (value) {
      final ok = await HostsBlocker.apply(HostsBlocker.defaultDomains);
      if (!ok) {
        if (!mounted) return;
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Needs administrator rights'),
            content: const Text(
              'Writing the hosts file needs admin rights. On Windows, '
              'close the app and run it as administrator (right-click → '
              'Run as administrator), then turn this on again. On Linux, '
              'run the app with sudo — only if you are comfortable with '
              'that. Without it, website blocking stays off.',
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      setState(() => _hostsApplied = true);
    } else {
      await HostsBlocker.remove();
      setState(() => _hostsApplied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    if (widget.store.isActive) return _activeView(base, muted, isDark);
    return ListView(
      key: const Key('focus-screen'),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
      children: [
        _sessionCard(base, muted, isDark),
        const SizedBox(height: 24),
        _scheduleCard(base, muted, isDark),
        const SizedBox(height: 24),
        if (_isAndroid) _permissionsCard(base, muted, isDark),
        if (_isAndroid) const SizedBox(height: 24),
        if (_isAndroid && _permissions?.accessibility == false)
          _restrictedSettingsCard(base, muted, isDark),
        if (_isAndroid && _permissions?.accessibility == false)
          const SizedBox(height: 24),
        _FocusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apps that stay usable',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _isAndroid
                    ? 'This app is always allowed. Turn on only the apps you truly need while studying.'
                    : 'The app list is only available on Android. On this device, focus stays inside the app.',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
              const SizedBox(height: 12),
              if (!_isAndroid)
                Text(
                  'Whitelist: this app only.',
                  style: base.copyWith(fontSize: 15, height: 1.45),
                )
              else if (!_appsLoaded)
                const Center(child: CupertinoActivityIndicator())
              else if (_apps.isEmpty)
                Text(
                  'No apps found. Check that the app has permission to see installed apps, then come back.',
                  style: base.copyWith(fontSize: 15, height: 1.45),
                )
              else
                ..._apps.map(
                  (app) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.label,
                            style: base.copyWith(fontSize: 15, height: 1.45),
                          ),
                        ),
                        const SizedBox(width: 16),
                        CupertinoSwitch(
                          key: ValueKey('whitelist-${app.packageName}'),
                          value: widget.store.isWhitelisted(app.packageName),
                          activeTrackColor: JimColors.rose,
                          onChanged: (_) async {
                            await widget.store.toggleWhitelisted(app.packageName);
                            await _syncRules();
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_isAndroid) _dailyLimitsCard(base, muted, isDark),
        if (_isAndroid) const SizedBox(height: 24),
        if (_isDesktop) _desktopCard(base, muted, isDark),
        if (_isDesktop) const SizedBox(height: 24),
        if (_isAndroid) _honestLimitsCard(base, muted),
        if (_isAndroid) const SizedBox(height: 24),
      ],
    );
  }

  Widget _sessionCard(TextStyle base, Color muted, bool isDark) {
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Focus mode',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _isAndroid
                ? 'While focus is on, only this app and your whitelisted apps stay usable. Every other app gets a calm block screen.'
                : 'System-wide app blocking works on Android only. Here, focus hides the other tabs and shows just your chapter and the timer.',
            style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
          ),
          if (widget.focusChapter != null) ...[
            const SizedBox(height: 16),
            Text(
              'Focusing on: ${widget.focusChapter!.chapter.title} · ${widget.focusChapter!.subject.nameEn}',
              style: base.copyWith(fontSize: 15, height: 1.45),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Session length',
            style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          CupertinoSlidingSegmentedControl<int>(
            key: const Key('focus-duration'),
            groupValue: FocusStore.durationOptions.indexOf(_selectedMinutes),
            backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
            thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
            children: {
              for (var i = 0; i < FocusStore.durationOptions.length; i++)
                i: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text('${FocusStore.durationOptions[i]} min'),
                ),
            },
            onValueChanged: (index) {
              if (index != null) {
                setState(() {
                  _selectedMinutes = FocusStore.durationOptions[index];
                });
              }
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Can't end early (locked)",
                      style: base.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cold Turkey style: once a locked session starts, '
                      'the End button stays off until the timer finishes. '
                      'Killing the app does not cancel it either.',
                      style:
                          base.copyWith(fontSize: 14, color: muted, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              CupertinoSwitch(
                key: const Key('focus-locked'),
                value: widget.store.locked,
                activeTrackColor: JimColors.rose,
                onChanged: _toggleLocked,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              key: const Key('focus-start'),
              minimumSize: const Size(48, 56),
              borderRadius: BorderRadius.circular(14),
              onPressed: _startFocus,
              child: Text('Start focus · $_selectedMinutes min'),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _dayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  Widget _scheduleCard(TextStyle base, Color muted, bool isDark) {
    final dayBlocks = widget.schedule.blocks[_scheduleDay] ?? {};
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly schedule',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Focus turns on by itself inside these hours — no need to '
            'press Start. Each cell is one hour. Works on every platform; '
            'on Android the service enforces it even if the app is closed.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var day = 1; day <= 7; day++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      key: ValueKey('schedule-day-$day'),
                      onTap: () => setState(() => _scheduleDay = day),
                      child: Container(
                        height: 44,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _scheduleDay == day
                              ? (isDark
                                  ? JimColors.darkText
                                  : JimColors.softBlack)
                              : const Color(0x00000000),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _scheduleDay == day
                                ? const Color(0x00000000)
                                : (isDark
                                    ? JimColors.darkLine
                                    : JimColors.line),
                          ),
                        ),
                        child: Text(
                          _dayNames[day - 1],
                          style: base.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _scheduleDay == day
                                ? (isDark
                                    ? JimColors.softBlack
                                    : CupertinoColors.white)
                                : (isDark
                                    ? JimColors.darkText
                                    : JimColors.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.2,
            ),
            itemCount: 24,
            itemBuilder: (context, hour) {
              final full =
                  widget.schedule.isHourBlocked(_scheduleDay, hour);
              final partial = !full &&
                  widget.schedule
                      .isHourPartiallyBlocked(_scheduleDay, hour);
              return GestureDetector(
                key: ValueKey('schedule-hour-$_scheduleDay-$hour'),
                onTap: () => _toggleScheduleHour(hour),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: full
                        ? JimColors.rose
                        : partial
                            ? JimColors.rose.withValues(alpha: 0.35)
                            : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: full
                          ? JimColors.rose
                          : (isDark ? JimColors.darkLine : JimColors.line),
                    ),
                  ),
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: base.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: full
                          ? CupertinoColors.white
                          : (isDark ? JimColors.darkText : JimColors.ink),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            dayBlocks.isEmpty
                ? 'Nothing blocked on ${_dayNames[_scheduleDay - 1]} yet.'
                : '${_dayNames[_scheduleDay - 1]}: ${dayBlocks.length * 15} minutes blocked.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  key: const Key('schedule-preset'),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  minimumSize: const Size(48, 44),
                  onPressed: _applySchedulePreset,
                  child: const Text('Weekdays 8–13'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoButton(
                  key: const Key('schedule-clear-day'),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  minimumSize: const Size(48, 44),
                  onPressed: _clearScheduleDay,
                  child: const Text('Clear day'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _permissionsCard(
    TextStyle base,
    Color muted,
    bool isDark,
  ) {
    final permissions = _permissions;
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Blocking permissions',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Accessibility and overlay are needed for other apps to actually be blocked. '
            'Usage access is only needed for daily limits. '
            'Nothing is claimed to work until it shows as on.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          _permissionRow(
            base: base,
            label: 'Accessibility service',
            granted: permissions?.accessibility ?? false,
            onOpen: () async {
              await _channel.openAccessibilitySettings();
              final fresh = await _channel.checkPermissions();
              if (mounted) setState(() => _permissions = fresh);
            },
          ),
          const SizedBox(height: 12),
          _permissionRow(
            base: base,
            label: 'Draw over other apps',
            granted: permissions?.overlay ?? false,
            onOpen: () async {
              await _channel.openOverlaySettings();
              final fresh = await _channel.checkPermissions();
              if (mounted) setState(() => _permissions = fresh);
            },
          ),
          const SizedBox(height: 12),
          _permissionRow(
            base: base,
            label: 'Usage access (daily limits)',
            granted: permissions?.usage ?? false,
            onOpen: () async {
              await _channel.openUsageSettings();
              final fresh = await _channel.checkPermissions();
              if (mounted) setState(() => _permissions = fresh);
            },
          ),
        ],
      ),
    );
  }

  Widget _restrictedSettingsCard(TextStyle base, Color muted, bool isDark) {
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accessibility toggle is greyed out?',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'This app is sideloaded, so on Android 13+ the system blocks '
            'the Accessibility switch until you allow it once:\n\n'
            '1. Open App info below.\n'
            '2. Tap the three-dot menu (top right).\n'
            '3. Tap "Allow restricted settings".\n'
            '4. Come back and turn the Accessibility service on.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              key: const Key('focus-open-app-info'),
              minimumSize: const Size(48, 48),
              borderRadius: BorderRadius.circular(14),
              onPressed: () => _channel.openAppInfo(),
              child: const Text('Open App info'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionRow({
    required TextStyle base,
    required String label,
    required bool granted,
    required VoidCallback onOpen,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: base.copyWith(fontSize: 15, height: 1.45)),
        ),
        const SizedBox(width: 12),
        Text(
          granted ? 'On' : 'Off',
          style: base.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: granted ? JimColors.rose : JimColors.muted,
          ),
        ),
        if (!granted) ...[
          const SizedBox(width: 12),
          CupertinoButton(
            key: ValueKey('focus-permission-$label'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(48, 36),
            onPressed: onOpen,
            child: const Text('Open Settings'),
          ),
        ],
      ],
    );
  }

  Widget _dailyLimitsCard(TextStyle base, Color muted, bool isDark) {
    final caps = widget.store.caps;
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily limits',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'A daily limit blocks an app for the rest of the day once it '
            'is used up — even outside a focus session, and even if the '
            'app is whitelisted. Needs Usage access above.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          if (caps.isEmpty)
            Text(
              'No limits set yet.',
              style: base.copyWith(fontSize: 15, height: 1.45),
            )
          else
            ...caps.entries.map((entry) {
              final app = _apps.firstWhere(
                (a) => a.packageName == entry.key,
                orElse: () => InstalledApp(
                    label: entry.key, packageName: entry.key),
              );
              final used = _usage[entry.key] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.label,
                            style:
                                base.copyWith(fontSize: 15, height: 1.45),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Used $used min today · limit ${entry.value} min',
                            style: base.copyWith(
                                fontSize: 14, color: muted, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      key: ValueKey('cap-minus-${entry.key}'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      onPressed: () async {
                        final next = entry.value - 15;
                        if (next <= 0) {
                          await widget.store.removeCap(entry.key);
                        } else {
                          await widget.store.setCap(entry.key, next);
                        }
                        await _syncRules();
                        if (mounted) setState(() {});
                      },
                      child: const Text('−', style: TextStyle(fontSize: 20)),
                    ),
                    Text(
                      '${entry.value}m',
                      style:
                          base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    CupertinoButton(
                      key: ValueKey('cap-plus-${entry.key}'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      onPressed: () async {
                        await widget.store
                            .setCap(entry.key, entry.value + 15);
                        await _syncRules();
                        if (mounted) setState(() {});
                      },
                      child: const Text('+', style: TextStyle(fontSize: 20)),
                    ),
                    CupertinoButton(
                      key: ValueKey('cap-remove-${entry.key}'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      onPressed: () async {
                        await widget.store.removeCap(entry.key);
                        await _syncRules();
                        if (mounted) setState(() {});
                      },
                      child: const Text('✕'),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              key: const Key('cap-add'),
              minimumSize: const Size(48, 48),
              borderRadius: BorderRadius.circular(14),
              onPressed: _showAddCapSheet,
              child: const Text('Add a daily limit'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopCard(TextStyle base, Color muted, bool isDark) {
    final isWindows =
        defaultTargetPlatform == TargetPlatform.windows;
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PC blocking',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            isWindows
                ? 'While focus is on, this app watches the foreground window. A blocked app gets a polite close request and this app comes to the front.'
                : 'Best effort only on Linux — window listing is restricted on Wayland, and this needs wmctrl and xdotool installed.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          Text(
            'PC apps that stay usable',
            style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'This app is always allowed. Add exe names exactly as they appear, e.g. notepad.exe.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  key: const Key('desktop-exe-field'),
                  controller: _exeController,
                  placeholder: 'e.g. notepad.exe',
                ),
              ),
              const SizedBox(width: 12),
              CupertinoButton.filled(
                key: const Key('desktop-exe-add'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                minimumSize: const Size(48, 44),
                borderRadius: BorderRadius.circular(12),
                onPressed: () async {
                  final name = _exeController.text.trim().toLowerCase();
                  if (name.isEmpty) return;
                  if (!widget.store.isDesktopWhitelisted(name)) {
                    await widget.store.toggleDesktopWhitelisted(name);
                  }
                  _exeController.clear();
                  if (mounted) setState(() {});
                },
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.store.desktopWhitelist.isEmpty)
            Text(
              'Only this app is allowed on PC right now.',
              style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
            )
          else
            ...widget.store.desktopWhitelist.map(
              (exe) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(exe,
                          style: base.copyWith(fontSize: 15, height: 1.45)),
                    ),
                    CupertinoButton(
                      key: ValueKey('desktop-remove-$exe'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      onPressed: () async {
                        await widget.store.toggleDesktopWhitelisted(exe);
                        if (mounted) setState(() {});
                      },
                      child: const Text('✕'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Block distracting websites',
                      style: base.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Writes YouTube, Facebook, Instagram, TikTok, X, Reddit and Netflix into the hosts file. Needs administrator rights — without them it stays off.',
                      style: base.copyWith(
                          fontSize: 14, color: muted, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              CupertinoSwitch(
                key: const Key('hosts-toggle'),
                value: _hostsApplied,
                activeTrackColor: JimColors.rose,
                onChanged: _toggleHosts,
              ),
            ],
          ),
          if (!_hostsWritable) ...[
            const SizedBox(height: 8),
            Text(
              'The hosts file cannot be written from here right now — the app was not started as administrator.',
              style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'PC blocking is best effort: Task Manager can always close this app, and a block only lasts while the app is running.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _honestLimitsCard(TextStyle base, Color muted) {
    return _FocusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What blocking cannot stop',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Honestly: force-stopping this app, turning the Accessibility service off in Settings, uninstalling the app, or restarting in safe mode all stop the blocking. No normal app can prevent that — Cold Turkey needs an admin-installed helper for true lock-in, and this app does not have one.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  /// Calm full view shown while a session runs.
  Widget _activeView(TextStyle base, Color muted, bool isDark) {
    final chapter = widget.focusChapter;
    final locked = widget.store.locked;
    return ListView(
      key: const Key('focus-active'),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
      children: [
        _FocusCard(
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text(
                widget.store.remainingLabel,
                key: const Key('focus-remaining'),
                style: base.copyWith(
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Focus cholche — phone ta ekhon sudhu porashonar jonno.',
                textAlign: TextAlign.center,
                style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
              ),
              if (chapter != null) ...[
                const SizedBox(height: 20),
                Text(
                  '${chapter.chapter.title} · ${chapter.subject.nameEn}',
                  textAlign: TextAlign.center,
                  style: base.copyWith(fontSize: 17, height: 1.45),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _isAndroid
                    ? 'Other apps are blocked until the timer ends.'
                    : 'In-app focus — the other tabs are hidden until the timer ends.',
                textAlign: TextAlign.center,
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
              if (locked) ...[
                const SizedBox(height: 12),
                Text(
                  widget.store.lockedLabel,
                  textAlign: TextAlign.center,
                  style: base.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JimColors.rose,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  key: const Key('focus-end'),
                  minimumSize: const Size(48, 56),
                  borderRadius: BorderRadius.circular(14),
                  onPressed: widget.store.canEnd ? _endFocus : null,
                  child: const Text('End focus'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same airy card as the rest of the app: 24px side margin, 20px inner
/// padding, 24px radius, soft shadow, 1px soft line.
class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? JimColors.darkSurface : JimColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? JimColors.darkLine : JimColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color:
                CupertinoColors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

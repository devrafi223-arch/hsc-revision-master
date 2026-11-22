import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/syllabus.dart';
import '../focus_store.dart';
import '../main.dart';
import '../services/focus_channel.dart';

/// Focus Mode screen — Cupertino style, same airy off-white design
/// (24px page padding, 20px card padding, 16px card gaps, w600 max).
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
    required this.focusChapter,
    this.onFocusChanged,
  });

  final FocusStore store;
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
  Timer? _ticker;
  int _selectedMinutes = 25;

  bool get _isAndroid => FocusChannel.isSupported;

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
        _endFocus();
      }
    });
    _loadNativeState();
  }

  Future<void> _loadNativeState() async {
    if (!_isAndroid) return;
    final apps = await _channel.getInstalledApps();
    final permissions = await _channel.checkPermissions();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _appsLoaded = true;
      _permissions = permissions;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
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
    final startFuture = widget.store.start(
      minutes: _selectedMinutes,
      chapterId: widget.focusChapter?.chapter.id,
    );
    if (mounted) setState(() {});
    widget.onFocusChanged?.call();
    await startFuture;
    if (_isAndroid) {
      await _channel.startFocus(
        whitelist: widget.store.whitelist.toList(),
        endEpochMs: widget.store.endTime!.millisecondsSinceEpoch,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _endFocus() async {
    final endFuture = widget.store.end();
    if (mounted) setState(() {});
    widget.onFocusChanged?.call();
    await endFuture;
    await _channel.stopFocus();
    if (mounted) setState(() {});
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
        _FocusCard(
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
        ),
        const SizedBox(height: 24),
        if (_isAndroid) _permissionsCard(base, muted, isDark),
        if (_isAndroid) const SizedBox(height: 24),
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
      ],
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
            'Both are needed for other apps to actually be blocked. '
            'Nothing is claimed to work until both show as on.',
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

  /// Calm full view shown while a session runs.
  Widget _activeView(TextStyle base, Color muted, bool isDark) {
    final chapter = widget.focusChapter;
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
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  key: const Key('focus-end'),
                  minimumSize: const Size(48, 56),
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _endFocus,
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

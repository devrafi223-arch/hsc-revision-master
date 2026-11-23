import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../backup.dart';
import '../data/syllabus.dart';
import '../focus_schedule.dart';
import '../focus_store.dart';
import '../main.dart';
import '../services/desktop_blocker.dart';
import '../services/desktop_watcher.dart';
import '../services/focus_channel.dart';
import '../services/focus_session.dart';
import '../tracker_store.dart';
import '../widgets/pomodoro_timer.dart';
import 'focus_screen.dart';

// Airy spacing system (the fix for the jam-packed feel):
// page side padding 24, section gaps 24, chapter cards 16 apart,
// card inner padding 20, section headers 28 above / 12 below.
// Titles are semibold at most (w600), body is regular, secondary
// text is muted at 14-15px with line height ~1.45.
const double _pagePadding = 24;
const double _sectionGap = 24;
const double _cardGap = 16;
const double _cardPadding = 20;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TrackerStore _store = TrackerStore();
  final FocusStore _focusStore = FocusStore();
  final FocusSchedule _schedule = FocusSchedule();
  final FocusChannel _focusChannel = FocusChannel();
  final TextEditingController _searchController = TextEditingController();
  bool _loaded = false;
  Timer? _scheduleTimer;
  late final DesktopWatcher _desktopWatcher =
      DesktopWatcher(createDesktopBlocker());
  String? _desktopBlockedExe;

  /// True only on real Android — system-wide blocking exists there only.
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// On non-Android, an active focus session hides the other tabs and
  /// shows only the focus view. On Android the tabs stay (the native
  /// service blocks other apps instead).
  bool get _inAppFocusActive => _focusStore.isActive && !_isAndroid;

  ChapterRef? get _focusChapter {
    final pending = _store.pendingChapters(allChapterRefs);
    return pending.isEmpty ? null : pending.first;
  }
  String _subject = 'all';
  String _query = '';
  String _paper = 'all';
  String _status = 'all';
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _store.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
    _focusStore.load().then((_) {
      if (mounted) setState(() {});
    });
    _schedule.load().then((_) {
      if (mounted) setState(() {});
    });
    // Schedule ticker: every 30s, auto-start focus inside a scheduled
    // block (and resume it after a short manual session ends mid-block).
    // It only calls setState when something actually changed, so widget
    // tests using pumpAndSettle are not disturbed.
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSchedule();
    });
  }

  /// Auto-start a session when the weekly schedule says focus is on.
  /// Never restarts a block the user just ended early (dismissed), and
  /// never starts anything when no block is set.
  Future<void> _checkSchedule() async {
    final now = DateTime.now();
    if (!_schedule.isBlockedAt(now) ||
        _focusStore.isActive ||
        _focusStore.scheduleDismissedNow) {
      return;
    }
    final end = _schedule.activeBlockEnd(now);
    if (end == null) return;
    await FocusSession.start(
      store: _focusStore,
      schedule: _schedule,
      channel: _focusChannel,
      end: end,
      chapterId: _focusChapter?.chapter.id,
      auto: true,
    );
    _syncDesktopWatcher();
    if (mounted) setState(() {});
  }

  /// Keep the PC watcher in step with focus: watch while a session or
  /// a scheduled block is active, stop otherwise.
  void _syncDesktopWatcher() {
    final blocking = _focusStore.isActive ||
        (_schedule.isBlockedAt(DateTime.now()) &&
            !_focusStore.scheduleDismissedNow);
    if (!blocking) {
      _desktopWatcher.stop();
      if (_desktopBlockedExe != null) {
        _desktopBlockedExe = null;
        if (mounted) setState(() {});
      }
      return;
    }
    _desktopWatcher.start(
      isBlocking: () =>
          _focusStore.isActive ||
          (_schedule.isBlockedAt(DateTime.now()) &&
              !_focusStore.scheduleDismissedNow),
      allowedExeNames: _focusStore.desktopWhitelist,
      onBlocked: (exe) {
        _desktopBlockedExe = exe;
        if (mounted) setState(() {});
      },
      onReturned: () {
        if (_desktopBlockedExe != null) {
          _desktopBlockedExe = null;
          if (mounted) setState(() {});
        }
      },
    );
  }

  Future<void> _endDesktopFocus() async {
    final ended = await FocusSession.end(
      store: _focusStore,
      schedule: _schedule,
      channel: _focusChannel,
    );
    if (!ended) return; // locked session: End stays off until it ends
    _desktopWatcher.stop();
    _desktopBlockedExe = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _toastTimer?.cancel();
    _scheduleTimer?.cancel();
    _desktopWatcher.stop();
    super.dispose();
  }

  void _showMessage(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _toggleStage(String chapterId, String stageId) async {
    setState(() => _store.toggle(chapterId, stageId));
    await _store.save();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial =
        _store.targetDate ?? now.add(const Duration(days: 90));
    DateTime? picked;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => _DatePickerSheet(
        initialDate: initial,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 730)),
        onDone: (date) => picked = date,
      ),
    );
    if (picked == null) return;
    setState(() => _store.targetDate = picked);
    await _store.save();
    _showMessage('Exam target date saved.');
  }

  Future<void> _shareSummary() async {
    await Clipboard.setData(ClipboardData(text: _store.whatsAppSummary()));
    if (mounted) {
      _showMessage('WhatsApp summary copied — paste it anywhere.');
    }
  }

  Future<void> _exportBackup() async {
    final message = await saveBackupJson(_store.exportJson());
    if (mounted) _showMessage(message);
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Import JSON backup'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 120,
            child: CupertinoTextField(
              key: const Key('import-field'),
              controller: controller,
              maxLines: 6,
              placeholder: 'Paste your backup JSON here',
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            key: const Key('import-confirm'),
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = _store.importJson(controller.text);
    if (success) {
      await _store.save();
      setState(() {});
      _showMessage('Backup imported.');
    } else {
      _showMessage('That JSON is not a valid backup.');
    }
  }

  Future<void> _resetAll() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Reset all progress?'),
        content: const Text('Every tick will be cleared. This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _store.checks.clear());
    await _store.save();
    _showMessage('All progress reset.');
  }

  void _showMoreMenu() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              _exportBackup();
            },
            child: const Text('Export JSON backup'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              _showImportDialog();
            },
            child: const Text('Import JSON backup'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(context).pop();
              _resetAll();
            },
            child: const Text('Reset all progress'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  int _subjectPct(Subject subject) {
    final refs =
        allChapterRefs.where((r) => r.subject.id == subject.id).toList();
    final total = refs.length * revisionStages.length;
    if (total == 0) return 0;
    final done = refs.fold<int>(
      0,
      (n, r) => n + _store.doneForChapter(r.chapter.id),
    );
    return (done * 100 / total).round();
  }

  List<ChapterRef> get _filtered {
    final query = _query.trim().toLowerCase();
    return allChapterRefs.where((ref) {
      if (_subject != 'all' && ref.subject.id != _subject) return false;
      if (_paper != 'all' &&
          ref.section.paper != 0 &&
          ref.section.paper.toString() != _paper) {
        return false;
      }
      final done = _store.doneForChapter(ref.chapter.id);
      if (_status == 'pending' && done != 0) return false;
      if (_status == 'inprogress' &&
          (done == 0 || done == revisionStages.length)) {
        return false;
      }
      if (_status == 'done' && done != revisionStages.length) return false;
      if (query.isNotEmpty) {
        final haystack =
            '${ref.chapter.title} ${ref.chapter.displaySub} ${ref.subject.nameEn} ${ref.subject.name}'
                .toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final done = _store.doneCount;
    final pct = totalMilestones == 0 ? 0 : (done * 100 / totalMilestones).round();
    final weakest = _store.weakestSubject(allChapterRefs);
    final target = _store.targetDate;
    int? daysLeft;
    String? dailyTarget;
    if (target != null) {
      final today = DateTime.now();
      daysLeft = DateTime(target.year, target.month, target.day)
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;
      if (daysLeft < 0) daysLeft = 0;
      final remaining = totalMilestones - done;
      dailyTarget = daysLeft == 0
          ? '$remaining tasks today'
          : '~${(remaining / daysLeft).toStringAsFixed(1)} tasks/day';
    }

    // PC blocking: a blocked foreground app takes over the whole
    // screen with the block message until the user comes back.
    if (_loaded && _desktopBlockedExe != null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Focus'),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, _pagePadding),
            children: [
              _JimCard(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      _focusStore.remainingLabel,
                      key: const Key('desktop-block-remaining'),
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 64,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Blocked app: $_desktopBlockedExe',
                      textAlign: TextAlign.center,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Focus cholche — ei app-ta ekhon bondho. '
                      'The app was asked to close; come back here to study.',
                      textAlign: TextAlign.center,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(fontSize: 15, height: 1.45),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        key: const Key('desktop-block-end'),
                        minimumSize: const Size(48, 56),
                        borderRadius: BorderRadius.circular(14),
                        onPressed:
                            _focusStore.canEnd ? _endDesktopFocus : null,
                        child: const Text('End focus'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Non-Android focus: hide every other tab, show only the focus view.
    if (_loaded && _inAppFocusActive) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Focus'),
        ),
        child: SafeArea(
          child: FocusScreen(
            store: _focusStore,
            schedule: _schedule,
            focusChapter: _focusChapter,
            onFocusChanged: () {
              _syncDesktopWatcher();
              setState(() {});
            },
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('HSC Revision Master'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              key: const Key('share-button'),
              padding: EdgeInsets.zero,
              onPressed: _shareSummary,
              child: const Icon(CupertinoIcons.share),
            ),
            CupertinoButton(
              key: const Key('more-menu'),
              padding: EdgeInsets.zero,
              onPressed: _showMoreMenu,
              child: const Icon(CupertinoIcons.ellipsis),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _loaded
                      ? CupertinoTabScaffold(
                          tabBar: CupertinoTabBar(
                            key: const Key('bottom-nav'),
                            activeColor: widget.dark
                                ? JimColors.darkText
                                : JimColors.softBlack,
                            inactiveColor: widget.dark
                                ? JimColors.darkMuted
                                : JimColors.muted,
                            backgroundColor: widget.dark
                                ? JimColors.darkBg
                                : JimColors.paper,
                            items: const [
                              BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.today),
                                label: 'Today',
                              ),
                              BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.book),
                                label: 'All chapters',
                              ),
                              BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.timer),
                                label: 'Focus',
                              ),
                              BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.calendar),
                                label: 'Exam plan',
                              ),
                            ],
                          ),
                          tabBuilder: (context, index) {
                            switch (index) {
                              case 0:
                                return CupertinoTabView(
                                  builder: (context) => _TodayTab(
                                    store: _store,
                                    done: done,
                                    pct: pct,
                                    weakestName: weakest.nameEn,
                                    weakestPct: _subjectPct(weakest),
                                    daysLeft: daysLeft,
                                    dailyTarget: dailyTarget,
                                    targetDate: target,
                                    dark: widget.dark,
                                    onToggleTheme: widget.onToggleTheme,
                                    onPickDate: _pickDate,
                                    onToggleStage: _toggleStage,
                                  ),
                                );
                              case 1:
                                return CupertinoTabView(
                                  builder: (context) => _AllTab(
                                    store: _store,
                                    subject: _subject,
                                    paper: _paper,
                                    status: _status,
                                    searchController: _searchController,
                                    filtered: _filtered,
                                    onSubject: (id) =>
                                        setState(() => _subject = id),
                                    onQuery: (q) =>
                                        setState(() => _query = q),
                                    onPaper: (p) =>
                                        setState(() => _paper = p),
                                    onStatus: (s) =>
                                        setState(() => _status = s),
                                    onToggleStage: _toggleStage,
                                  ),
                                );
                              case 2:
                                return CupertinoTabView(
                                  builder: (context) => FocusScreen(
                                    store: _focusStore,
                                    schedule: _schedule,
                                    focusChapter: _focusChapter,
                                    onFocusChanged: () {
                                      _syncDesktopWatcher();
                                      setState(() {});
                                    },
                                  ),
                                );
                              default:
                                return CupertinoTabView(
                                  builder: (context) =>
                                      const _ExamPlanTab(),
                                );
                            }
                          },
                        )
                      : const Center(child: CupertinoActivityIndicator()),
                ),
              ],
            ),
            if (_toast != null)
              Positioned(
                left: _pagePadding,
                right: _pagePadding,
                bottom: 92,
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: widget.dark
                          ? JimColors.darkText
                          : JimColors.softBlack,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _toast!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.dark
                            ? JimColors.softBlack
                            : CupertinoColors.white,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cupertino date picker in a bottom sheet, with a Done button.
class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDone,
  });

  final DateTime initialDate, firstDate, lastDate;
  final ValueChanged<DateTime> onDone;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _temp;

  @override
  void initState() {
    super.initState();
    _temp = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return Container(
      height: 340,
      color: isDark ? JimColors.darkSurface : JimColors.card,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                CupertinoButton(
                  onPressed: () {
                    widget.onDone(_temp);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Expanded(
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: widget.initialDate,
              minimumDate: widget.firstDate,
              maximumDate: widget.lastDate,
              onDateTimeChanged: (date) => _temp = date,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft rounded card in the Jim palette (replaces Material Card).
/// Airy: 20px inner padding, 24px side margin, 16px between cards,
/// 24px radius, very soft shadow and a 1px soft line.
class _JimCard extends StatelessWidget {
  const _JimCard({required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: _pagePadding,
            vertical: _cardGap / 2,
          ),
      padding: const EdgeInsets.all(_cardPadding),
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

/// Progress ring drawn with a CustomPainter (no Material indicator).
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor, fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, track);
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// One calm stat row: quiet label on the left, value on the right,
/// generous vertical padding, hairline divider handled by the parent.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.done,
    required this.pct,
    required this.weakestName,
    required this.weakestPct,
    required this.daysLeft,
    required this.dailyTarget,
    required this.targetDate,
    required this.dark,
    required this.onToggleTheme,
    required this.onPickDate,
  });

  final int done, pct, weakestPct;
  final String weakestName;
  final int? daysLeft;
  final String? dailyTarget;
  final DateTime? targetDate;
  final bool dark;
  final VoidCallback onToggleTheme, onPickDate;

  @override
  Widget build(BuildContext context) {
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = dark ? JimColors.darkMuted : JimColors.muted;
    final line = dark ? JimColors.darkLine : JimColors.line;
    return _JimCard(
      margin: const EdgeInsets.fromLTRB(
        _pagePadding,
        _cardGap,
        _pagePadding,
        _cardGap / 2,
      ),
      child: Column(
        children: [
          // Big ring, centred, with generous empty space around it.
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _RingPainter(
                    progress: pct / 100,
                    trackColor: line,
                    fillColor: JimColors.rose,
                  ),
                ),
                Text(
                  '$pct%',
                  style: base.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$done / $totalMilestones done',
            style: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'One chapter at a time',
            style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          // Stats as separate airy rows — never crammed side by side.
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: line)),
            ),
            child: Column(
              children: [
                _StatRow(
                  label: 'Needs most work',
                  value: '$weakestName · $weakestPct%',
                ),
                Container(height: 1, color: line),
                GestureDetector(
                  key: const Key('target-date'),
                  onTap: onPickDate,
                  behavior: HitTestBehavior.opaque,
                  child: _StatRow(
                    label: 'Exam target',
                    value: targetDate == null
                        ? 'Set a date'
                        : '${daysLeft ?? 0} days left',
                  ),
                ),
                Container(height: 1, color: line),
                _StatRow(
                  label: 'Daily pace',
                  value: dailyTarget ?? 'Set a date to see it',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                CupertinoIcons.moon_fill,
                size: 18,
                color: muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Night mode',
                  style: base.copyWith(fontSize: 15, height: 1.45),
                ),
              ),
              CupertinoSwitch(
                key: const Key('theme-toggle'),
                value: dark,
                activeTrackColor: JimColors.rose,
                onChanged: (_) => onToggleTheme(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayTab extends StatelessWidget {
  const _TodayTab({
    required this.store,
    required this.done,
    required this.pct,
    required this.weakestName,
    required this.weakestPct,
    required this.daysLeft,
    required this.dailyTarget,
    required this.targetDate,
    required this.dark,
    required this.onToggleTheme,
    required this.onPickDate,
    required this.onToggleStage,
  });

  final TrackerStore store;
  final int done, pct, weakestPct;
  final String weakestName;
  final int? daysLeft;
  final String? dailyTarget;
  final DateTime? targetDate;
  final bool dark;
  final VoidCallback onToggleTheme, onPickDate;
  final Future<void> Function(String, String) onToggleStage;

  @override
  Widget build(BuildContext context) {
    final pending = store.pendingChapters(allChapterRefs).take(5).toList();
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted =
        CupertinoTheme.of(context).brightness == Brightness.dark
            ? JimColors.darkMuted
            : JimColors.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, _pagePadding),
      children: [
        _ProgressHeader(
          done: done,
          pct: pct,
          weakestName: weakestName,
          weakestPct: weakestPct,
          daysLeft: daysLeft,
          dailyTarget: dailyTarget,
          targetDate: targetDate,
          dark: dark,
          onToggleTheme: onToggleTheme,
          onPickDate: onPickDate,
        ),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Focus",
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Next 5 pending chapters',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (pending.isEmpty)
                Text(
                  'All 906 milestones done — re-test finished chapters after a 2–3 day gap.',
                  style: base.copyWith(fontSize: 15, height: 1.45),
                )
              else
                ...pending.map(
                  (ref) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 7),
                          decoration: const BoxDecoration(
                            color: JimColors.rose,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${ref.chapter.title} · ${ref.subject.nameEn}',
                            style: base.copyWith(fontSize: 15, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'How to finish a chapter: Archive, then Note, then Recall from memory, then a timed MCQ, then Live class, then a Test paper alone.',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: _sectionGap),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus timer',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const PomodoroTimer(),
            ],
          ),
        ),
      ],
    );
  }
}

class _AllTab extends StatelessWidget {
  const _AllTab({
    required this.store,
    required this.subject,
    required this.paper,
    required this.status,
    required this.searchController,
    required this.filtered,
    required this.onSubject,
    required this.onQuery,
    required this.onPaper,
    required this.onStatus,
    required this.onToggleStage,
  });

  final TrackerStore store;
  final String subject, paper, status;
  final TextEditingController searchController;
  final List<ChapterRef> filtered;
  final ValueChanged<String> onSubject, onQuery, onPaper, onStatus;
  final Future<void> Function(String, String) onToggleStage;

  static const _papers = ['all', '1', '2'];
  static const _statuses = ['all', 'pending', 'inprogress', 'done'];

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
          child: CupertinoSearchTextField(
            key: const Key('search-field'),
            controller: searchController,
            onChanged: onQuery,
            placeholder: 'Search — ভেক্টর, গতিবিদ্যা, Unit 1…',
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _pagePadding - 5),
            children: [
              _Chip(
                key: const ValueKey('subject-all'),
                label: 'All',
                selected: subject == 'all',
                onTap: () => onSubject('all'),
              ),
              ...syllabusData.map(
                (s) => _Chip(
                  key: ValueKey('subject-${s.id}'),
                  label: '${s.icon} ${s.nameEn}',
                  selected: subject == s.id,
                  onTap: () => onSubject(s.id),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
          child: CupertinoSlidingSegmentedControl<int>(
            key: const Key('paper-filter'),
            groupValue: _papers.indexOf(paper),
            backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
            thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
            children: const {
              0: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text('All papers'),
              ),
              1: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text('1st paper'),
              ),
              2: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text('2nd paper'),
              ),
            },
            onValueChanged: (index) {
              if (index != null) onPaper(_papers[index]);
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
          child: CupertinoSlidingSegmentedControl<int>(
            key: const Key('status-filter'),
            groupValue: _statuses.indexOf(status),
            backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
            thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
            children: const {
              0: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('All'),
              ),
              1: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('Pending'),
              ),
              2: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('In progress'),
              ),
              3: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('Done'),
              ),
            },
            onValueChanged: (index) {
              if (index != null) onStatus(_statuses[index]);
            },
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Showing ${filtered.length} of $totalChapters chapters',
              style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No chapters match those filters.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, _pagePadding),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _ChapterCard(
                    ref: filtered[index],
                    store: store,
                    onToggleStage: onToggleStage,
                  ),
                ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? JimColors.darkText : JimColors.softBlack)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0x00000000)
                  : (isDark ? JimColors.darkLine : JimColors.line),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: selected
                  ? (isDark ? JimColors.softBlack : CupertinoColors.white)
                  : (isDark ? JimColors.darkText : JimColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterCard extends StatefulWidget {
  const _ChapterCard({
    required this.ref,
    required this.store,
    required this.onToggleStage,
  });

  final ChapterRef ref;
  final TrackerStore store;
  final Future<void> Function(String, String) onToggleStage;

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  String? _tipStageId;

  @override
  Widget build(BuildContext context) {
    final ref = widget.ref;
    final store = widget.store;
    final done = store.doneForChapter(ref.chapter.id);
    final meta = subjectMeta[ref.subject.id];
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final fraction = done / revisionStages.length;
    final tip = _tipStageId == null ? null : stageTips[_tipStageId];

    return _JimCard(
      margin: const EdgeInsets.fromLTRB(
        _pagePadding,
        0,
        _pagePadding,
        _cardGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${ref.chapter.no}. ${ref.chapter.title}',
                  style: base.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '$done/6',
                style: base.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: done == revisionStages.length
                      ? JimColors.rose
                      : muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${ref.subject.nameEn} · ${ref.section.nameEn}'
            '${ref.chapter.displaySub.isNotEmpty ? ' · ${ref.chapter.displaySub}' : ''}'
            '${meta != null ? ' · Code ${meta.code}' : ''}',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          // Slim rose progress bar with space around it.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: isDark ? JimColors.darkLine : JimColors.line,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                widthFactor: fraction,
                alignment: Alignment.centerLeft,
                child: Container(height: 6, color: JimColors.rose),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Stage chips: exactly 3 per row, 10px gaps, 44px tall.
          ...List.generate(2, (row) {
            final rowStages = revisionStages.sublist(row * 3, row * 3 + 3);
            return Padding(
              padding: EdgeInsets.only(bottom: row == 0 ? 10 : 0),
              child: Row(
                children: [
                  for (var i = 0; i < rowStages.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _StageChip(
                        key: ValueKey(
                          'stage-${ref.chapter.id}-${rowStages[i].id}',
                        ),
                        stage: rowStages[i],
                        isDone: store.isDone(ref.chapter.id, rowStages[i].id),
                        isDark: isDark,
                        onTap: () {
                          setState(() {
                            _tipStageId = _tipStageId == rowStages[i].id
                                ? null
                                : rowStages[i].id;
                          });
                          widget.onToggleStage(
                            ref.chapter.id,
                            rowStages[i].id,
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          // Per-stage tip: only when a stage chip was tapped.
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: tip == null
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: JimColors.rose
                          .withValues(alpha: isDark ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      tip,
                      style: base.copyWith(fontSize: 14, height: 1.45),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    super.key,
    required this.stage,
    required this.isDone,
    required this.isDark,
    required this.onTap,
  });

  final Stage stage;
  final bool isDone, isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDone ? JimColors.rose : const Color(0x00000000),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDone
                ? JimColors.rose
                : (isDark ? JimColors.darkLine : JimColors.line),
            width: 1.5,
          ),
        ),
        child: Text(
          '${isDone ? '✓ ' : ''}${stage.short}',
          textAlign: TextAlign.center,
          style: base.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDone
                ? CupertinoColors.white
                : (isDark ? JimColors.darkText : JimColors.ink),
          ),
        ),
      ),
    );
  }
}

class _ExamPlanTab extends StatelessWidget {
  const _ExamPlanTab();

  @override
  Widget build(BuildContext context) {
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted =
        CupertinoTheme.of(context).brightness == Brightness.dark
            ? JimColors.darkMuted
            : JimColors.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, _pagePadding),
      children: [
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam plan — HSC 2026 reference',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'Written exams ran 2 Jul – 8 Aug 2026 (full syllabus, full marks). '
                'Practicals from 15 Aug 2026. Non-practical paper: MCQ 30 + CQ 70. '
                'Practical subjects: theory 75 (MCQ 25 + CQ 50) + practical 25.',
                style: base.copyWith(fontSize: 15, height: 1.45),
              ),
              const SizedBox(height: 16),
              Text(
                'HSC 2027 routine was not published at research time (Nov 2026) — '
                'no 2027 date is shown here. Set your own target date on the '
                'progress card and check dhakaeducationboard.gov.bd.',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: _sectionGap),
        ...syllabusData.map((subject) {
          final meta = subjectMeta[subject.id];
          return _JimCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.nameEn,
                  style: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  meta == null
                      ? '${subject.chapterCount} chapters'
                      : 'Code ${meta.code} · 2026 exam ${meta.exam2026}\n${meta.marks} · ${subject.chapterCount} chapters',
                  style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

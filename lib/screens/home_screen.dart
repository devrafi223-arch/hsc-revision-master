import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../backup.dart';
import '../data/syllabus.dart';
import '../main.dart';
import '../tracker_store.dart';
import '../widgets/pomodoro_timer.dart';

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
  final TextEditingController _searchController = TextEditingController();
  bool _loaded = false;
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _toastTimer?.cancel();
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
                _ProgressHeader(
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
                ),
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
                left: 16,
                right: 16,
                bottom: 92,
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: widget.dark
                          ? JimColors.darkText
                          : JimColors.softBlack,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _toast!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.dark
                            ? JimColors.softBlack
                            : CupertinoColors.white,
                        fontWeight: FontWeight.w600,
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
      height: 320,
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
class _JimCard extends StatelessWidget {
  const _JimCard({required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? JimColors.darkSurface : JimColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? JimColors.darkLine : JimColors.line,
        ),
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
    final radius = size.width / 2 - 5;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, track);
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
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
    return _JimCard(
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(88, 88),
                      painter: _RingPainter(
                        progress: pct / 100,
                        trackColor:
                            dark ? JimColors.darkLine : JimColors.line,
                        fillColor: JimColors.rose,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: base.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$done / $totalMilestones done',
                      style: base.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Weakest: $weakestName ($weakestPct%)',
                      style: base.copyWith(color: muted),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      key: const Key('target-date'),
                      onTap: onPickDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          targetDate == null
                              ? '📅 Set your exam target date'
                              : '📅 ${daysLeft ?? 0} days left • $dailyTarget',
                          style: base.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(CupertinoIcons.moon_fill, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Night mode', style: base),
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
    required this.onToggleStage,
  });

  final TrackerStore store;
  final Future<void> Function(String, String) onToggleStage;

  @override
  Widget build(BuildContext context) {
    final pending = store.pendingChapters(allChapterRefs).take(5).toList();
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      children: [
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Focus — next 5 pending chapters",
                style: base.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (pending.isEmpty)
                const Text(
                  '🎉 All 906 milestones done — re-test finished chapters after a 2–3 day gap.',
                )
              else
                ...pending.map(
                  (ref) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '📖 ${ref.chapter.title} · ${ref.subject.nameEn}',
                      style: base,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'How to finish a chapter: Archive → Note → Recall from memory → timed MCQ → Live class → Test paper alone.',
              ),
            ],
          ),
        ),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus timer',
                style: base.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: CupertinoSearchTextField(
            key: const Key('search-field'),
            controller: searchController,
            onChanged: onQuery,
            placeholder: 'Search — ভেক্টর, গতিবিদ্যা, Unit 1…',
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: CupertinoSlidingSegmentedControl<int>(
            key: const Key('paper-filter'),
            groupValue: _papers.indexOf(paper),
            backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
            thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
            children: const {
              0: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('All papers'),
              ),
              1: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('1st paper'),
              ),
              2: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('2nd paper'),
              ),
            },
            onValueChanged: (index) {
              if (index != null) onPaper(_papers[index]);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: CupertinoSlidingSegmentedControl<int>(
            key: const Key('status-filter'),
            groupValue: _statuses.indexOf(status),
            backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
            thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
            children: const {
              0: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('All'),
              ),
              1: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('Pending'),
              ),
              2: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('In progress'),
              ),
              3: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('Done'),
              ),
            },
            onValueChanged: (index) {
              if (index != null) onStatus(_statuses[index]);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Showing ${filtered.length} of $totalChapters chapters',
              style: base.copyWith(fontSize: 13, color: muted),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No chapters match those filters.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
              fontWeight: FontWeight.w700,
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

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.ref,
    required this.store,
    required this.onToggleStage,
  });

  final ChapterRef ref;
  final TrackerStore store;
  final Future<void> Function(String, String) onToggleStage;

  @override
  Widget build(BuildContext context) {
    final done = store.doneForChapter(ref.chapter.id);
    final meta = subjectMeta[ref.subject.id];
    final nextStage = revisionStages.firstWhere(
      (s) => !store.isDone(ref.chapter.id, s.id),
      orElse: () => revisionStages.last,
    );
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return _JimCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ref.chapter.no}. ${ref.chapter.title}',
                      style: base.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ref.subject.nameEn} · ${ref.section.nameEn}'
                      '${ref.chapter.displaySub.isNotEmpty ? ' · ${ref.chapter.displaySub}' : ''}'
                      '${meta != null ? ' · Code ${meta.code}' : ''}',
                      style: base.copyWith(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: done == revisionStages.length
                      ? JimColors.roseLight
                      : (isDark ? JimColors.darkLine : JimColors.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$done/6',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: revisionStages.map((stage) {
              final isDone = store.isDone(ref.chapter.id, stage.id);
              return GestureDetector(
                key: ValueKey('stage-${ref.chapter.id}-${stage.id}'),
                onTap: () => onToggleStage(ref.chapter.id, stage.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDone
                        ? JimColors.rose
                        : const Color(0x00000000),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDone
                          ? CupertinoColors.white
                          : (isDark ? JimColors.darkText : JimColors.ink),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: ${stageTips[nextStage.id] ?? ''}',
            style: base.copyWith(fontSize: 13, color: muted),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      children: [
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam plan — HSC 2026 reference',
                style: base.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Written exams ran 2 Jul – 8 Aug 2026 (full syllabus, full marks). '
                'Practicals from 15 Aug 2026. Non-practical paper: MCQ 30 + CQ 70. '
                'Practical subjects: theory 75 (MCQ 25 + CQ 50) + practical 25.',
              ),
              const SizedBox(height: 8),
              Text(
                'HSC 2027 routine was not published at research time (Nov 2026) — '
                'no 2027 date is shown here. Set your own target date on the '
                'progress card and check dhakaeducationboard.gov.bd.',
                style: base.copyWith(color: muted),
              ),
            ],
          ),
        ),
        ...syllabusData.map((subject) {
          final meta = subjectMeta[subject.id];
          return _JimCard(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.nameEn,
                  style: base.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  meta == null
                      ? '${subject.chapterCount} chapters'
                      : 'Code ${meta.code} · 2026 exam ${meta.exam2026}\n${meta.marks} · ${subject.chapterCount} chapters',
                  style: base.copyWith(fontSize: 13, color: muted),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

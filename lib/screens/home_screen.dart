import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/syllabus.dart';
import '../main.dart';
import '../milestones.dart';
import '../models/milestone.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../services/sync_service.dart';
import '../target_plan.dart';
import '../tracker_store.dart';
import '../widgets/calendar_view.dart';
import '../widgets/download_section.dart';
import '../widgets/milestone_celebration.dart';
import '../widgets/pomodoro_timer.dart';
import '../widgets/weekly_chart.dart';
import 'admin_screen.dart';
import 'chapter_note_sheet.dart';
import 'community_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

// Airy spacing system (the fix for the jam-packed feel):
// page side padding 24, section gaps 24, chapter cards 16 apart,
// card inner padding 20, section headers 28 above / 12 below.
// Titles are semibold at most (w600), body is regular, secondary
// text is muted at 14-15px with line height ~1.45.
const double _pagePadding = 24;
const double _sectionGap = 24;
const double _cardGap = 16;
const double _cardPadding = 20;

/// One motivation quote per weekday (Monday first).
const List<String> _dailyQuotes = [
  'Small steps every day lead to big results.',
  'Revision is not repeating — it is remembering better.',
  'One chapter at a time. That is enough for today.',
  'The best time to revise was yesterday. The next best time is now.',
  'You do not have to be great to start, but you have to start to be great.',
  'Progress, not perfection.',
  'Rest is part of revision too — take your break.',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.dark = false,
    this.onToggleTheme,
  });

  /// [dark] / [onToggleTheme] are optional so AuthScreen can open the
  /// home screen with plain `const HomeScreen()` for "Continue offline".
  /// main.dart always passes the real theme values.
  final bool dark;
  final VoidCallback? onToggleTheme;

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

  int _dailyTarget = 3;
  int _currentIndex = 0;
  // NOTE: _dailyTarget is still the default pace for "Today's plan"
  // when no target date is set. The target CARD itself is now a manual
  // to-do list (below) — the old +/- chapter stepper is gone.
  DateTime? _customTargetDate;

  /// Today's target as a manual to-do list (Rafi: the target is set by
  /// hand, as to-dos). Each entry: {'id', 'title', 'done'}. Stored in
  /// SharedPreferences key 'today-todos-v1'; device-local for now
  /// (online sync is a follow-up once the backend link is proven).
  List<Map<String, dynamic>> _todos = [];
  final Set<String> _milestonesShown = {};
  bool _isAdmin = false;

  /// Local theme fallback, kept only as a safety net: main.dart now
  /// always passes the real [onToggleTheme] (signed-in and offline),
  /// so this flag is normally never used.
  bool _darkOverride = false;
  bool get _effectiveDark =>
      widget.onToggleTheme != null ? widget.dark : _darkOverride;
  void _handleToggleTheme() {
    if (widget.onToggleTheme != null) {
      widget.onToggleTheme!();
    } else {
      setState(() => _darkOverride = !_darkOverride);
    }
  }

  @override
  void initState() {
    super.initState();
    _store.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
    _loadPrefs();
    _loadAdmin();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dailyTarget = prefs.getInt('daily-target') ?? 3;
      final rawDate = prefs.getString('custom-target-date');
      _customTargetDate = rawDate == null ? null : DateTime.tryParse(rawDate);
      _milestonesShown
        ..clear()
        ..addAll(prefs.getStringList('milestones-shown-v1') ?? []);
      final rawTodos = prefs.getString('today-todos-v1');
      if (rawTodos != null) {
        try {
          final decoded = jsonDecode(rawTodos) as List<dynamic>;
          _todos = decoded
              .whereType<Map<String, dynamic>>()
              .where((m) => (m['title'] as String?)?.isNotEmpty == true)
              .toList();
        } catch (_) {
          _todos = [];
        }
      }
    });
  }

  Future<void> _loadAdmin() async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return;
    try {
      final admin = await AdminService.instance.isAdmin(uid);
      if (mounted) setState(() => _isAdmin = admin);
    } catch (_) {
      // Not an admin, or offline — the admin row simply stays hidden.
    }
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
    if (_store.doneForChapter(chapterId) != revisionStages.length) return;
    if (_milestonesShown.contains(chapterId)) return;
    try {
      _milestonesShown.add(chapterId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'milestones-shown-v1',
        _milestonesShown.toList(),
      );
      final ref = allChapterRefs.firstWhere(
        (r) => r.chapter.id == chapterId,
      );
      final siblings =
          allChapterRefs.where((r) => r.subject.id == ref.subject.id).toList();
      final index = siblings.indexWhere(
        (r) => r.chapter.id == chapterId,
      );
      final name = Milestones.nameFor(
        ref.subject.nameEn,
        ref.chapter.title,
        index,
      );
      // Milestone alerts can be switched off in Settings.
      final alertsOn = prefs.getBool('notif-milestone') ?? true;
      if (!mounted || !alertsOn) return;
      MilestoneCelebration.show(context, name);
      try {
        MessagingService.notifyMilestone(name);
      } catch (_) {
        // Milestone notifications are best effort; the celebration
        // above already told the user.
      }
    } catch (_) {
      // A milestone must never break stage toggling.
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final initial = _customTargetDate ?? now.add(const Duration(days: 90));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom-target-date',
      picked.toIso8601String(),
    );
    setState(() => _customTargetDate = picked);
    _showMessage('Target date saved.');
  }

  Future<void> _saveTodos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('today-todos-v1', jsonEncode(_todos));
  }

  Future<void> _addTodo(String title) async {
    final text = title.trim();
    if (text.isEmpty) return;
    setState(() {
      _todos.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'title': text,
        'done': false,
      });
    });
    await _saveTodos();
  }

  Future<void> _toggleTodo(String id) async {
    setState(() {
      final index = _todos.indexWhere((t) => t['id'] == id);
      if (index != -1) {
        _todos[index] = {
          ..._todos[index],
          'done': !(_todos[index]['done'] as bool? ?? false),
        };
      }
    });
    await _saveTodos();
  }

  Future<void> _removeTodo(String id) async {
    setState(() => _todos.removeWhere((t) => t['id'] == id));
    await _saveTodos();
  }

  /// Clears every tick. No dialog here — the only entry point is
  /// Settings → Danger zone, which gates it behind typing "Confirm".
  Future<void> _resetAll() async {
    setState(() => _store.checks.clear());
    await _store.save();
    _showMessage('All progress reset.');
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          dark: _effectiveDark,
          onToggleTheme: widget.onToggleTheme,
          onResetAll: _resetAll,
        ),
      ),
    );
  }

  void _openGroups() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupsScreen()),
    );
  }

  void _openAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminScreen()),
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

  /// 0-based index of [ref] among its subject's chapters, as
  /// [Milestones.nameFor] expects.
  int _chapterIndexWithinSubject(ChapterRef ref) {
    final siblings =
        allChapterRefs.where((r) => r.subject.id == ref.subject.id).toList();
    return siblings.indexWhere((r) => r.chapter.id == ref.chapter.id);
  }

  List<Milestone> _earnedMilestones() {
    return allChapterRefs
        .where((r) => _store.doneForChapter(r.chapter.id) == 6)
        .map(
          (r) => Milestone(
            id: r.chapter.id,
            // earnedAt is not displayed anywhere — only the name and
            // subject are shown — so "now" is just a placeholder value
            // for the required non-null field.
            name: Milestones.nameFor(
              r.subject.nameEn,
              r.chapter.title,
              _chapterIndexWithinSubject(r),
            ),
            subject: r.subject.nameEn,
            chapterTitle: r.chapter.title,
            earnedAt: DateTime.now(),
          ),
        )
        .toList();
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
    final pct =
        totalMilestones == 0 ? 0 : (done * 100 / totalMilestones).round();
    final weakest = _store.weakestSubject(allChapterRefs);
    final today = DateTime.now();

    final remainingRefs = allChapterRefs
        .where((r) => _store.doneForChapter(r.chapter.id) < 6)
        .toList();
    final remainingIds = remainingRefs.map((r) => r.chapter.id).toList();
    final daysLeft = _customTargetDate == null
        ? null
        : DailyPlan.daysLeft(
            targetDate: _customTargetDate!,
            today: today,
          );
    final perDay = _customTargetDate == null
        ? _dailyTarget
        : DailyPlan.chaptersPerDay(
            remainingChapters: remainingRefs.length,
            targetDate: _customTargetDate!,
            today: today,
          );
    final planIds = DailyPlan.planForToday(
      remainingChapterIds: remainingIds,
      perDay: perDay,
    );
    final planTitles = planIds.map((id) {
      final ref = allChapterRefs.where((r) => r.chapter.id == id);
      return ref.isEmpty
          ? id
          : '${ref.first.chapter.title} · ${ref.first.subject.nameEn}';
    }).toList();

    // Spaced revision: the 5 chapters with the lowest stage completion.
    final reviseRefs = [...allChapterRefs]..sort(
        (a, b) => _store
            .doneForChapter(a.chapter.id)
            .compareTo(_store.doneForChapter(b.chapter.id)),
      );
    final reviseTop5 = reviseRefs
        .where((r) => _store.doneForChapter(r.chapter.id) < 6)
        .take(5)
        .toList();

    final quote = _dailyQuotes[(today.weekday - 1) % _dailyQuotes.length];

    return Scaffold(
      appBar: AppBar(
        title: const Text('HSC Revision Master'),
        actions: [
          IconButton(
            key: const Key('settings-button'),
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                StreamBuilder<bool>(
                  stream: SyncService.instance.isOfflineStream,
                  initialData: false,
                  builder: (context, snapshot) {
                    if (snapshot.data != true) {
                      return const SizedBox.shrink();
                    }
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Container(
                      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: JimColors.rose.withValues(
                          alpha: isDark ? 0.18 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.wifi_off,
                            size: 16,
                            color: JimColors.rose,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Offline — will sync',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: _loaded
                      ? IndexedStack(
                          index: _currentIndex,
                          children: [
                            _TodayTab(
                              store: _store,
                              done: done,
                              pct: pct,
                              weakestName: weakest.nameEn,
                              weakestPct: _subjectPct(weakest),
                              dark: _effectiveDark,
                              onToggleTheme: _handleToggleTheme,
                              todos: _todos,
                              onAddTodo: _addTodo,
                              onToggleTodo: _toggleTodo,
                              onRemoveTodo: _removeTodo,
                              customTargetDate: _customTargetDate,
                              daysLeft: daysLeft,
                              perDay: perDay,
                              planTitles: planTitles,
                              reviseRefs: reviseTop5,
                              milestones: _earnedMilestones(),
                              quote: quote,
                              isAdmin: _isAdmin,
                              onPickCustomDate: _pickCustomDate,
                              onToggleStage: _toggleStage,
                              onOpenSettings: _openSettings,
                              onOpenGroups: _openGroups,
                              onOpenAdmin: _openAdmin,
                            ),
                            _AllTab(
                              store: _store,
                              subject: _subject,
                              paper: _paper,
                              status: _status,
                              searchController: _searchController,
                              filtered: _filtered,
                              onSubject: (id) => setState(() => _subject = id),
                              onQuery: (q) => setState(() => _query = q),
                              onPaper: (p) => setState(() => _paper = p),
                              onStatus: (s) => setState(() => _status = s),
                              onToggleStage: _toggleStage,
                            ),
                            const CommunityScreen(),
                            const ProfileScreen(showAppBar: false),
                          ],
                        )
                      : const Center(child: CircularProgressIndicator()),
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
                      color: _effectiveDark
                          ? JimColors.darkText
                          : JimColors.softBlack,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _toast!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            _effectiveDark ? JimColors.softBlack : Colors.white,
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
      bottomNavigationBar: _loaded
          ? NavigationBar(
              key: const Key('bottom-nav'),
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) =>
                  setState(() => _currentIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.today),
                  label: 'Today',
                ),
                NavigationDestination(
                  icon: Icon(Icons.book),
                  label: 'All chapters',
                ),
                NavigationDestination(
                  icon: Icon(Icons.group),
                  label: 'Community',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            )
          : null,
    );
  }
}

/// Soft rounded card in the Jim palette (custom — keeps the
/// sketchbook radius and shadow instead of a Material Card).
/// Airy: 20px inner padding, 24px side margin, 16px between cards,
/// 24px radius, very soft shadow and a 1px soft line.
class _JimCard extends StatelessWidget {
  const _JimCard({required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
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
    required this.dark,
    required this.onToggleTheme,
  });

  final int done, pct, weakestPct;
  final String weakestName;
  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
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
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.dark_mode,
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
              Switch(
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

/// Today's target as a manual to-do list: the user types their own
/// targets and ticks them off. Shows "x/y done".
class _TodayTargetCard extends StatefulWidget {
  const _TodayTargetCard({
    required this.todos,
    required this.onAddTodo,
    required this.onToggleTodo,
    required this.onRemoveTodo,
  });

  final List<Map<String, dynamic>> todos;
  final ValueChanged<String> onAddTodo;
  final ValueChanged<String> onToggleTodo;
  final ValueChanged<String> onRemoveTodo;

  @override
  State<_TodayTargetCard> createState() => _TodayTargetCardState();
}

class _TodayTargetCardState extends State<_TodayTargetCard> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAddTodo(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final doneCount =
        widget.todos.where((t) => t['done'] as bool? ?? false).length;
    return _JimCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today’s target',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            widget.todos.isEmpty
                ? 'Add what you want to finish today, then tick it off.'
                : '$doneCount/${widget.todos.length} done',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          ...widget.todos.map((todo) {
            final id = todo['id'] as String? ?? '';
            final title = todo['title'] as String? ?? '';
            final done = todo['done'] as bool? ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => widget.onToggleTodo(id),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: ValueKey(done),
                        color: done ? JimColors.rose : muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: base.copyWith(
                        fontSize: 15,
                        height: 1.45,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? muted : null,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.onRemoveTodo(id),
                    icon: const Icon(
                      Icons.delete,
                      size: 18,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('todo-input'),
                  controller: _controller,
                  decoration: jimFieldDecoration(
                    dark: isDark,
                    hint: 'Add a target for today…',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('todo-add'),
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Add'),
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
    required this.dark,
    required this.onToggleTheme,
    required this.todos,
    required this.onAddTodo,
    required this.onToggleTodo,
    required this.onRemoveTodo,
    required this.customTargetDate,
    required this.daysLeft,
    required this.perDay,
    required this.planTitles,
    required this.reviseRefs,
    required this.milestones,
    required this.quote,
    required this.isAdmin,
    required this.onPickCustomDate,
    required this.onToggleStage,
    required this.onOpenSettings,
    required this.onOpenGroups,
    required this.onOpenAdmin,
  });

  final TrackerStore store;
  final int done, pct, weakestPct;
  final String weakestName;
  final bool dark;
  final VoidCallback onToggleTheme;
  final List<Map<String, dynamic>> todos;
  final ValueChanged<String> onAddTodo;
  final ValueChanged<String> onToggleTodo;
  final ValueChanged<String> onRemoveTodo;
  final DateTime? customTargetDate;
  final int? daysLeft;
  final int perDay;
  final List<String> planTitles;
  final List<ChapterRef> reviseRefs;
  final List<Milestone> milestones;
  final String quote;
  final bool isAdmin;
  final VoidCallback onPickCustomDate;
  final Future<void> Function(String, String) onToggleStage;
  final VoidCallback onOpenSettings, onOpenGroups, onOpenAdmin;

  @override
  Widget build(BuildContext context) {
    final pending = store.pendingChapters(allChapterRefs).take(5).toList();
    final base = Theme.of(context).textTheme.bodyMedium!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, _pagePadding),
      children: [
        _ProgressHeader(
          done: done,
          pct: pct,
          weakestName: weakestName,
          weakestPct: weakestPct,
          dark: dark,
          onToggleTheme: onToggleTheme,
        ),
        _TodayTargetCard(
          todos: todos,
          onAddTodo: onAddTodo,
          onToggleTodo: onToggleTodo,
          onRemoveTodo: onRemoveTodo,
        ),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today’s plan',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                customTargetDate == null
                    ? 'Set a target date and the remaining chapters spread evenly over the days left.'
                    : '${daysLeft ?? 0} days left · $perDay chapter${perDay == 1 ? '' : 's'} a day',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (planTitles.isEmpty)
                Text(
                  'All 151 chapters are finished — re-test finished chapters after a 2–3 day gap.',
                  style: base.copyWith(fontSize: 15, height: 1.45),
                )
              else
                ...planTitles.map(
                  (title) => Padding(
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
                            title,
                            style: base.copyWith(fontSize: 15, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('pick-target-date'),
                onPressed: onPickCustomDate,
                child: Text(
                  customTargetDate == null
                      ? 'Set target date'
                      : 'Change target date',
                ),
              ),
            ],
          ),
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
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revise again',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Your weakest chapters — spaced revision, lowest stage completion first.',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (reviseRefs.isEmpty)
                Text(
                  'Nothing to revise — every chapter is finished.',
                  style: base.copyWith(fontSize: 15, height: 1.45),
                )
              else
                ...reviseRefs.map(
                  (ref) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${ref.chapter.title} · ${ref.subject.nameEn}',
                            style: base.copyWith(fontSize: 15, height: 1.45),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${store.doneForChapter(ref.chapter.id)}/6',
                          style: base.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your week',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              // TrackerStore records no completion dates, so the calendar
              // has no marked days and the chart starts at zero — both
              // fill in from today as chapters are finished.
              const CalendarView(completedDays: {}),
              const SizedBox(height: 20),
              const WeeklyChart(chaptersPerDay: [0, 0, 0, 0, 0, 0, 0]),
              const SizedBox(height: 8),
              Text(
                'Track from today — finished chapters will mark the calendar and grow the bars.',
                style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
              ),
            ],
          ),
        ),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Milestones',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              MilestoneList(milestones: milestones),
            ],
          ),
        ),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For today',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                quote,
                style: base.copyWith(
                  fontSize: 15,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                ),
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
                'Pomodoro timer',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const PomodoroTimer(),
            ],
          ),
        ),
        const SizedBox(height: _sectionGap),
        _JimCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More',
                style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _MoreRow(
                icon: Icons.settings,
                label: 'Settings',
                onTap: onOpenSettings,
              ),
              Container(height: 1, color: line),
              _MoreRow(
                icon: Icons.group,
                label: 'Groups',
                onTap: onOpenGroups,
              ),
              if (isAdmin) ...[
                Container(height: 1, color: line),
                _MoreRow(
                  icon: Icons.shield,
                  label: 'Admin panel',
                  onTap: onOpenAdmin,
                ),
              ],
            ],
          ),
        ),
        // Web only (DownloadSection renders nothing on app builds).
        const DownloadSection(),
      ],
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: base.copyWith(fontSize: 15, height: 1.45),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
          child: TextField(
            key: const Key('search-field'),
            controller: searchController,
            onChanged: onQuery,
            decoration: jimFieldDecoration(
              dark: isDark,
              hint: 'Search — ভেক্টর, গতিবিদ্যা, Unit 1…',
              borderRadius: 999,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.search),
            ),
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
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              key: const Key('paper-filter'),
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('All papers'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('1st paper'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('2nd paper'),
                ),
              ],
              selected: {_papers.indexOf(paper)},
              onSelectionChanged: (selection) {
                onPaper(_papers[selection.first]);
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
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              key: const Key('status-filter'),
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('All'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Pending'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('In progress'),
                ),
                ButtonSegment<int>(
                  value: 3,
                  label: Text('Done'),
                ),
              ],
              selected: {_statuses.indexOf(status)},
              onSelectionChanged: (selection) {
                onStatus(_statuses[selection.first]);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  ? (isDark ? JimColors.softBlack : Colors.white)
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
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
              ChapterNoteBadge(chapterId: ref.chapter.id),
              const SizedBox(width: 8),
              Text(
                '$done/6',
                style: base.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: done == revisionStages.length ? JimColors.rose : muted,
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: ValueKey('note-${ref.chapter.id}'),
              onPressed: () => ChapterNoteSheet.show(
                context,
                chapterId: ref.chapter.id,
                chapterTitle: ref.chapter.title,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? JimColors.darkBg : JimColors.paper,
                foregroundColor: isDark ? JimColors.darkText : JimColors.ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.edit, size: 16),
                  SizedBox(width: 6),
                  Text('Note', style: TextStyle(fontSize: 14)),
                ],
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
    final base = Theme.of(context).textTheme.bodyMedium!;
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
                ? Colors.white
                : (isDark ? JimColors.darkText : JimColors.ink),
          ),
        ),
      ),
    );
  }
}

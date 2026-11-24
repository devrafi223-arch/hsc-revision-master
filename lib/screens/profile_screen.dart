import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/syllabus.dart';
import '../main.dart';
import '../milestones.dart';
import '../models/app_user.dart';
import '../models/milestone.dart';
import '../services/auth_service.dart';
import '../services/user_repository.dart';
import '../tracker_store.dart';
import '../widgets/milestone_celebration.dart';
import 'auth_screen.dart';

/// Your own account screen — photo, name, progress, milestones,
/// badges. There is no community left in the app, so there is no
/// viewing other people, no follow button and no profile privacy
/// here; this is just your account.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.showAppBar = true});

  /// False when embedded as a tab (the HomeScreen AppBar + NavigationBar
  /// already wrap it); true when pushed on its own, where it needs its
  /// own AppBar + back button.
  final bool showAppBar;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TrackerStore _store = TrackerStore();
  bool _storeLoaded = false;

  String? get _uid => AuthService.instance.currentUid;

  bool _photoBusy = false;

  /// Picks a photo, uploads it via POST /api/upload?kind=profile and
  /// sets it as this profile's photo.
  Future<void> _changePhoto() async {
    final uid = _uid;
    if (uid == null || _photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final url =
          await UserRepository.instance.uploadProfilePhoto(uid, bytes);
      await UserRepository.instance.updatePhoto(uid, url);
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update photo. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _store.load().then((_) {
      if (mounted) setState(() => _storeLoaded = true);
    });
  }

  /// 0-based index of [ref] among its subject's chapters, as
  /// [Milestones.nameFor] expects.
  int _chapterIndexWithinSubject(ChapterRef ref) {
    final siblings =
        allChapterRefs.where((r) => r.subject.id == ref.subject.id).toList();
    return siblings.indexWhere((r) => r.chapter.id == ref.chapter.id);
  }

  List<Milestone> _earnedMilestones() {
    final done = allChapterRefs
        .where((r) => _store.doneForChapter(r.chapter.id) == 6)
        .toList();
    return done
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

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      // No guest mode: without a signed-in user this screen routes
      // straight to the login screen (the app root normally gates
      // here first, so this is only a safety net).
      if (!widget.showAppBar) return const AuthScreen();
      return const Scaffold(
        body: SafeArea(child: AuthScreen()),
      );
    }
    final content = StreamBuilder<AppUser?>(
      stream: UserRepository.instance.userStream(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = snapshot.data ??
            AppUser(
              id: uid,
              name: AuthService.instance.currentUser?.name ?? 'Student',
              email: AuthService.instance.currentUser?.email ?? '',
              photoUrl: AuthService.instance.currentUser?.photoUrl,
            );
        return _ProfileBody(
          user: user,
          storeLoaded: _storeLoaded,
          store: _store,
          subjectPct: _subjectPct,
          earnedMilestones: _earnedMilestones(),
          onChangePhoto: _changePhoto,
          photoBusy: _photoBusy,
        );
      },
    );
    if (!widget.showAppBar) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(child: content),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.user,
    required this.storeLoaded,
    required this.store,
    required this.subjectPct,
    required this.earnedMilestones,
    this.onChangePhoto,
    this.photoBusy = false,
  });

  final AppUser user;
  final bool storeLoaded;
  final TrackerStore store;
  final int Function(Subject) subjectPct;
  final List<Milestone> earnedMilestones;

  /// Opens the gallery to change the photo.
  final VoidCallback? onChangePhoto;

  /// True while a photo upload is in flight.
  final bool photoBusy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    final overallPct = (user.totalChaptersDone * 100 / 151).round();
    final badges = Milestones.badgeNamesFor(
      streak: user.streak,
      totalChapters: user.totalChaptersDone,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        // Cover photo area (coverUrl, or a rose gradient).
        Container(
          height: 160,
          decoration: BoxDecoration(
            gradient: user.coverUrl != null && user.coverUrl!.isNotEmpty
                ? null
                : const LinearGradient(
                    colors: [JimColors.rose, JimColors.roseLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            image: user.coverUrl != null && user.coverUrl!.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(user.coverUrl!),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  )
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(0, -32),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: JimColors.rose,
                        border: Border.all(
                          color: isDark ? JimColors.darkBg : JimColors.paper,
                          width: 4,
                        ),
                        image: user.photoUrl != null &&
                                user.photoUrl!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(user.photoUrl!),
                                fit: BoxFit.cover,
                                onError: (_, __) {},
                              )
                            : null,
                      ),
                      child: (user.photoUrl == null ||
                              user.photoUrl!.isEmpty)
                          ? Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    if (onChangePhoto != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: photoBusy ? null : onChangePhoto,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: JimColors.rose,
                              border: Border.all(
                                color: isDark
                                    ? JimColors.darkBg
                                    : JimColors.paper,
                                width: 2,
                              ),
                            ),
                            child: photoBusy
                                ? const Padding(
                                    padding: EdgeInsets.all(7),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: base.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${user.totalChaptersDone} chapters done · $overallPct% of 151',
                      style: base.copyWith(
                        fontSize: 15,
                        color: muted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          size: 18,
                          color: JimColors.rose,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${user.streak}-day streak',
                          style: base.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Progress by subject',
                style: base.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (!storeLoaded)
                const CircularProgressIndicator()
              else
                ...syllabusData.map(
                  (subject) => _SubjectBar(
                    label: subject.nameEn,
                    pct: subjectPct(subject),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Milestones',
                style: base.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              MilestoneList(milestones: earnedMilestones),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Badges',
                  style: base.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: badges
                      .map(
                        (badge) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? JimColors.darkSurface
                                : JimColors.card,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: line),
                          ),
                          child: Text(
                            badge,
                            style: base.copyWith(
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectBar extends StatelessWidget {
  const _SubjectBar({required this.label, required this.pct});

  final String label;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: base.copyWith(fontSize: 15, height: 1.45),
                ),
              ),
              Text(
                '$pct%',
                style: base.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: isDark ? JimColors.darkLine : JimColors.line,
              child: FractionallySizedBox(
                widthFactor: (pct / 100).clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: Container(height: 6, color: JimColors.rose),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

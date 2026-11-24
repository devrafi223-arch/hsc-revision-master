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

/// Own profile + viewing others. `userId == null` means "my profile".
///
/// Visibility rules (enforced here, in the UI):
/// - locked + not yours + you don't follow them -> "This profile is locked"
/// - restricted + not yours -> name + overall progress % only
/// - public (or yours) -> full details.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId, this.showAppBar = true});

  final String? userId;

  /// False when embedded as a tab (the HomeScreen AppBar + NavigationBar
  /// already wrap it); true when pushed on its own (e.g. from the
  /// community leaderboard), where it needs its own AppBar + back button.
  final bool showAppBar;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TrackerStore _store = TrackerStore();
  bool _storeLoaded = false;
  AppUser? _ownUser;
  String _privacy = 'public';
  String _photoVisibility = 'all';

  String? get _uid => AuthService.instance.currentUid;
  bool get _isOwn => widget.userId == null || widget.userId == _uid;
  String? get _targetUid => widget.userId ?? _uid;

  bool _photoBusy = false;

  /// Picks a photo, uploads it via POST /api/upload?kind=profile and
  /// sets it as this profile's photo (own profile only).
  Future<void> _changePhoto() async {
    final uid = _targetUid;
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
    if (!_isOwn && _uid != null) {
      UserRepository.instance.getUser(_uid!).then((user) {
        if (mounted) setState(() => _ownUser = user);
      });
    }
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

  Future<void> _follow(AppUser target) async {
    final uid = _uid;
    if (uid == null) {
      // No guest mode: go to the login screen.
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    try {
      await UserRepository.instance.follow(uid, target.id);
      final refreshed = await UserRepository.instance.getUser(uid);
      if (mounted) setState(() => _ownUser = refreshed);
    } catch (e) {
      await _showInfo(e.toString());
    }
  }

  Future<void> _showInfo(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePrivacy({
    String? profileVisibility,
    String? photoVisibility,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      if (profileVisibility != null) _privacy = profileVisibility;
      if (photoVisibility != null) _photoVisibility = photoVisibility;
    });
    try {
      await UserRepository.instance.updatePrivacy(
        uid,
        profileVisibility: profileVisibility,
        photoVisibility: photoVisibility,
      );
    } catch (e) {
      await _showInfo(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetUid = _targetUid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    if (targetUid == null) {
      // No guest mode: without a signed-in user this screen routes
      // straight to the login screen (the app root normally gates
      // here first, so this is only a safety net).
      if (!widget.showAppBar) return const AuthScreen();
      return const Scaffold(
        body: SafeArea(child: AuthScreen()),
      );
    }
    final content = StreamBuilder<AppUser?>(
      stream: UserRepository.instance.userStream(targetUid),
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = snapshot.data;
        if (user == null) {
          // No profile doc yet (e.g. signed in but never saved):
          // fall back to the local tracker for your own profile.
          if (!_isOwn) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Profile not found.',
                  style: base.copyWith(
                    fontSize: 15,
                    color: muted,
                    height: 1.45,
                  ),
                ),
              ),
            );
          }
          return _ProfileBody(
            user: AppUser(
              id: targetUid,
              name: AuthService.instance.currentUser?.name ?? 'Student',
              email: AuthService.instance.currentUser?.email ?? '',
              photoUrl: AuthService.instance.currentUser?.photoUrl,
            ),
            isOwn: true,
            storeLoaded: _storeLoaded,
            store: _store,
            subjectPct: _subjectPct,
            earnedMilestones: _earnedMilestones(),
            privacy: _privacy,
            photoVisibility: _photoVisibility,
            following: false,
            onFollow: () {},
            onPrivacy: _updatePrivacy,
            onChangePhoto: _changePhoto,
            photoBusy: _photoBusy,
          );
        }
        if (_isOwn &&
            _privacy == 'public' &&
            user.profileVisibility != _privacy) {
          // First load: reflect the stored privacy in the controls.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _privacy = user.profileVisibility;
                _photoVisibility = user.photoVisibility;
              });
            }
          });
        }
        final following = _ownUser?.followingIds.contains(user.id) ?? false;
        if (!_isOwn && user.profileVisibility == 'locked' && !following) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock,
                    size: 36,
                    color: JimColors.rose,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This profile is locked',
                    style: base.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${user.name} keeps this profile private. Follow them to see more.',
                    textAlign: TextAlign.center,
                    style: base.copyWith(
                      fontSize: 15,
                      color: muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => _follow(user),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Follow'),
                  ),
                ],
              ),
            ),
          );
        }
        return _ProfileBody(
          user: user,
          isOwn: _isOwn,
          storeLoaded: _storeLoaded,
          store: _store,
          subjectPct: _subjectPct,
          earnedMilestones: _earnedMilestones(),
          privacy: _privacy,
          photoVisibility: _photoVisibility,
          following: following,
          onFollow: () => _follow(user),
          onPrivacy: _updatePrivacy,
          onChangePhoto: _changePhoto,
          photoBusy: _photoBusy,
          restrictedView: !_isOwn && user.profileVisibility == 'restricted',
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
    required this.isOwn,
    required this.storeLoaded,
    required this.store,
    required this.subjectPct,
    required this.earnedMilestones,
    required this.privacy,
    required this.photoVisibility,
    required this.following,
    required this.onFollow,
    required this.onPrivacy,
    this.onChangePhoto,
    this.photoBusy = false,
    this.restrictedView = false,
  });

  final AppUser user;
  final bool isOwn;
  final bool storeLoaded;
  final TrackerStore store;
  final int Function(Subject) subjectPct;
  final List<Milestone> earnedMilestones;
  final String privacy;
  final String photoVisibility;
  final bool following;
  final VoidCallback onFollow;
  final Future<void> Function({
    String? profileVisibility,
    String? photoVisibility,
  }) onPrivacy;

  /// Own profile only: opens the gallery to change the photo.
  /// Null on other people's profiles (no button shown).
  final VoidCallback? onChangePhoto;

  /// True while a photo upload is in flight.
  final bool photoBusy;

  final bool restrictedView;

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
    final showPhoto = isOwn || user.photoVisibility == 'all';
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
                    image: showPhoto &&
                            user.photoUrl != null &&
                            user.photoUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(user.photoUrl!),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  child: showPhoto &&
                          (user.photoUrl == null || user.photoUrl!.isEmpty)
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
                    if (isOwn && onChangePhoto != null)
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
                        const Spacer(),
                        if (!isOwn)
                          FilledButton(
                            onPressed: following ? null : onFollow,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              following ? 'Following' : 'Follow',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (restrictedView)
                Text(
                  'This profile is restricted — only the name and overall progress are visible.',
                  style: base.copyWith(
                    fontSize: 14,
                    color: muted,
                    height: 1.45,
                  ),
                )
              else ...[
                Text(
                  'Progress by subject',
                  style: base.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (!storeLoaded && isOwn)
                  const CircularProgressIndicator()
                else if (isOwn)
                  ...syllabusData.map(
                    (subject) => _SubjectBar(
                      label: subject.nameEn,
                      pct: subjectPct(subject),
                    ),
                  )
                else
                  _SubjectBar(
                    label: 'Overall',
                    pct: overallPct,
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
                if (isOwn)
                  MilestoneList(milestones: earnedMilestones)
                else if (user.milestoneIds.isEmpty)
                  Text(
                    'No milestones shared yet.',
                    style: base.copyWith(
                      fontSize: 14,
                      color: muted,
                      height: 1.45,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: user.milestoneIds
                        .map(
                          (id) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: JimColors.rose.withValues(
                                alpha: isDark ? 0.18 : 0.08,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: JimColors.rose.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              id,
                              style: base.copyWith(
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
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
              if (isOwn) ...[
                const SizedBox(height: 24),
                Text(
                  'Privacy',
                  style: base.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Who can see your profile',
                  style: base.copyWith(fontSize: 14, color: muted),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'public',
                        label: Text('Public'),
                      ),
                      ButtonSegment<String>(
                        value: 'restricted',
                        label: Text('Restricted'),
                      ),
                      ButtonSegment<String>(
                        value: 'locked',
                        label: Text('Locked'),
                      ),
                    ],
                    selected: {privacy},
                    onSelectionChanged: (selection) {
                      onPrivacy(profileVisibility: selection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      backgroundColor:
                          isDark ? JimColors.darkLine : JimColors.line,
                      selectedBackgroundColor:
                          isDark ? JimColors.darkSurface : JimColors.card,
                      selectedForegroundColor:
                          isDark ? JimColors.darkText : JimColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Who can see your photo',
                  style: base.copyWith(fontSize: 14, color: muted),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'all',
                        label: Text('All'),
                      ),
                      ButtonSegment<String>(
                        value: 'onlyMe',
                        label: Text('Only me'),
                      ),
                    ],
                    selected: {photoVisibility},
                    onSelectionChanged: (selection) {
                      onPrivacy(photoVisibility: selection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      backgroundColor:
                          isDark ? JimColors.darkLine : JimColors.line,
                      selectedBackgroundColor:
                          isDark ? JimColors.darkSurface : JimColors.card,
                      selectedForegroundColor:
                          isDark ? JimColors.darkText : JimColors.ink,
                    ),
                  ),
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

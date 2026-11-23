import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/app_user.dart';
import '../models/community_message.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../services/moderation.dart';
import '../services/sync_service.dart';
import '../services/user_repository.dart';
import '../services/voice_service.dart';
import 'profile_screen.dart';

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatTimestamp(DateTime t) {
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm, ${t.day} ${_monthNames[t.month - 1]}';
}

/// What the UI shows as a message's author. Anonymous messages never
/// reveal the real name or photo, but the stored authorId is still used
/// for moderation, reporting and blocking.
String _displayName(CommunityMessage message) =>
    message.isAnonymous ? 'Anonymous' : message.authorName;

/// The universal community feed: everyone's progress on a rail at the
/// top, realtime messages below, polls, voice, reactions, reply,
/// bookmark, report, block, pin, search and an offline banner.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final TextEditingController _composerController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _bookmarkedOnly = false;
  CommunityMessage? _replyTo;
  bool _recording = false;
  int _lastMessageCount = 0;
  String? _playingVoiceId;

  /// Anonymous posting: [_anonymousSession] is the header switch — on
  /// for the whole session until turned off. [_anonymousOnce] is the
  /// per-message composer chip — reset after every send. Either one on
  /// means the message goes out anonymous.
  bool _anonymousSession = false;
  bool _anonymousOnce = false;
  bool get _anonymousEffective => _anonymousSession || _anonymousOnce;

  /// The composer chip flips the effective state: when the session
  /// switch is on, tapping the chip turns the session off (so this
  /// message is not anonymous); otherwise it toggles the per-message
  /// choice.
  void _toggleAnonymousComposer() {
    setState(() {
      if (_anonymousSession) {
        _anonymousSession = false;
        _anonymousOnce = false;
      } else {
        _anonymousOnce = !_anonymousOnce;
      }
    });
  }

  String? get _uid => AuthService.instance.effectiveUid;

  @override
  void dispose() {
    _composerController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(int count) {
    if (count > _lastMessageCount && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
    _lastMessageCount = count;
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Could not send'),
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

  Future<void> _sendText() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    if (Moderation.isFlagged(text)) {
      await _showError(
        'This message was blocked by moderation. Please keep it friendly.',
      );
      return;
    }
    final replyTo = _replyTo;
    final anonymous = _anonymousEffective;
    _composerController.clear();
    setState(() {
      _replyTo = null;
      _anonymousOnce = false;
    });
    try {
      if (replyTo != null) {
        await CommunityService.instance.reply(
          replyTo.id,
          text,
          replyTo.text ?? '',
          anonymous: anonymous,
        );
      } else {
        await CommunityService.instance.sendText(
          text,
          anonymous: anonymous,
        );
      }
    } catch (e) {
      await _showError(e.toString());
    }
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (picked == null) return;
    try {
      await CommunityService.instance.sendPhoto(
        picked.path,
        anonymous: _anonymousEffective,
      );
      if (mounted) setState(() => _anonymousOnce = false);
    } catch (e) {
      await _showError(e.toString());
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recording) {
      final result = await VoiceService.instance.stopRecording();
      setState(() => _recording = false);
      if (result == null) return;
      final path = result['path'] as String?;
      final seconds = (result['seconds'] as num?)?.toInt() ?? 0;
      if (path == null || path.isEmpty) return;
      try {
        await CommunityService.instance.sendVoice(
          path,
          seconds,
          anonymous: _anonymousEffective,
        );
        if (mounted) setState(() => _anonymousOnce = false);
      } catch (e) {
        await _showError(e.toString());
      }
      return;
    }
    final started = await VoiceService.instance.startRecording();
    if (started == null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Voice messages'),
          content: const Text('Voice recording coming soon on this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _recording = true);
  }

  Future<void> _createPoll() async {
    final questionController = TextEditingController();
    final optionControllers = List.generate(4, (_) => TextEditingController());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('Create a poll'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              TextField(
                controller: questionController,
                decoration: jimFieldDecoration(
                  dark: isDark,
                  hint: 'Question',
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 8),
              ...optionControllers.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: entry.value,
                        decoration: jimFieldDecoration(
                          dark: isDark,
                          hint: entry.key < 2
                              ? 'Option ${entry.key + 1}'
                              : 'Option ${entry.key + 1} (optional)',
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Post poll'),
            ),
          ],
        );
      },
    );
    final question = questionController.text.trim();
    final options = optionControllers
        .map((c) => c.text.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    for (final c in [questionController, ...optionControllers]) {
      c.dispose();
    }
    if (ok != true) return;
    if (question.isEmpty || options.length < 2) {
      await _showError('A poll needs a question and at least 2 options.');
      return;
    }
    try {
      await CommunityService.instance.sendPoll(
        question,
        options,
        anonymous: _anonymousEffective,
      );
      if (mounted) setState(() => _anonymousOnce = false);
    } catch (e) {
      await _showError(e.toString());
    }
  }

  Future<void> _showMessageActions(CommunityMessage message) async {
    final uid = _uid;
    var isAdmin = false;
    if (uid != null) {
      try {
        isAdmin = await AdminService.instance.isAdmin(uid);
      } catch (_) {
        isAdmin = false;
      }
    }
    if (!mounted) return;
    final bookmarked = uid != null && message.bookmarkedBy.contains(uid);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _replyTo = message);
              },
            ),
            ListTile(
              title: Text(bookmarked ? 'Remove bookmark' : 'Bookmark'),
              onTap: () {
                Navigator.of(context).pop();
                CommunityService.instance.toggleBookmark(message.id);
              },
            ),
            ListTile(
              title: const Text('Report'),
              onTap: () {
                Navigator.of(context).pop();
                _reportMessage(message);
              },
            ),
            ListTile(
              title: const Text(
                'Block user',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _blockUser(message);
              },
            ),
            if (isAdmin)
              ListTile(
                title: Text(message.pinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.of(context).pop();
                  CommunityService.instance.togglePin(
                    message.id,
                    !message.pinned,
                  );
                },
              ),
            ListTile(
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportMessage(CommunityMessage message) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('Report this message'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: controller,
              maxLines: 3,
              decoration: jimFieldDecoration(
                dark: isDark,
                hint: 'Why is this a problem?',
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Report'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await CommunityService.instance.report(message.id, reason);
    } catch (e) {
      await _showError(e.toString());
    }
  }

  Future<void> _blockUser(CommunityMessage message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block ${_displayName(message)}?'),
        content: const Text(
          'You will no longer see their messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CommunityService.instance.blockUser(message.authorId);
    } catch (e) {
      await _showError(e.toString());
    }
  }

  Future<void> _togglePlayVoice(CommunityMessage message) async {
    final url = message.voiceUrl;
    if (url == null || url.isEmpty) return;
    if (_playingVoiceId == message.id) {
      await VoiceService.instance.stopPlaying();
      setState(() => _playingVoiceId = null);
      return;
    }
    setState(() => _playingVoiceId = message.id);
    try {
      await VoiceService.instance.playVoice(url);
    } catch (_) {
      // Playback errors are best effort; clear the playing state.
    }
    if (mounted) setState(() => _playingVoiceId = null);
  }

  List<CommunityMessage> _visibleMessages(List<CommunityMessage> all) {
    final query = _searchQuery.trim().toLowerCase();
    var list = all;
    if (_bookmarkedOnly) {
      final uid = _uid;
      list = list
          .where((m) => uid != null && m.bookmarkedBy.contains(uid))
          .toList();
    }
    if (query.isNotEmpty) {
      list = list
          .where((m) => (m.text ?? '').toLowerCase().contains(query))
          .toList();
    }
    // Oldest first so the newest message sits at the bottom.
    list = [...list]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    // Pinned messages sit at the top of the list, with a tag.
    final pinned = list.where((m) => m.pinned).toList();
    final rest = list.where((m) => !m.pinned).toList();
    return [...pinned, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    // Tab-only screen: the HomeScreen scaffold (AppBar + NavigationBar)
    // wraps this Column, so there is no scaffold of its own here.
    return Column(
      children: [
        StreamBuilder<bool>(
          stream: SyncService.instance.isOfflineStream,
          initialData: false,
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: JimColors.rose.withValues(
                  alpha: isDark ? 0.18 : 0.08,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Offline — messages will sync when back online.',
                textAlign: TextAlign.center,
                style: base.copyWith(fontSize: 14, height: 1.45),
              ),
            );
          },
        ),
        _ProgressRail(
          onOpenProfile: (user) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: user.id),
              ),
            );
          },
        ),
        // Session-wide anonymous posting: stays on until turned off.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Row(
            children: [
              const Icon(
                Icons.person,
                size: 18,
                color: JimColors.rose,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Post as Anonymous',
                  style: base.copyWith(fontSize: 14, height: 1.45),
                ),
              ),
              Switch(
                key: const Key('anonymous-session-switch'),
                value: _anonymousSession,
                activeTrackColor: JimColors.rose,
                onChanged: (value) {
                  setState(() {
                    _anonymousSession = value;
                    if (!value) _anonymousOnce = false;
                  });
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (q) => setState(() => _searchQuery = q),
            decoration: jimFieldDecoration(
              dark: isDark,
              hint: 'Search messages',
              borderRadius: 999,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Row(
            children: [
              _FilterChip(
                label: 'Bookmarked',
                selected: _bookmarkedOnly,
                onTap: () => setState(
                  () => _bookmarkedOnly = !_bookmarkedOnly,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Realtime • messages appear instantly when online',
                  style: base.copyWith(
                    fontSize: 13,
                    color: muted,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<List<CommunityMessage>>(
            stream: CommunityService.instance.messagesStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load messages. Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: base.copyWith(
                        fontSize: 15,
                        color: muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              final messages = _visibleMessages(snapshot.data!);
              _maybeAutoScroll(messages.length);
              if (messages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _searchQuery.isNotEmpty || _bookmarkedOnly
                          ? 'No messages match.'
                          : 'No messages yet — say hello!',
                      textAlign: TextAlign.center,
                      style: base.copyWith(
                        fontSize: 15,
                        color: muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return _MessageBubble(
                    message: message,
                    currentUid: _uid,
                    isPlayingVoice: _playingVoiceId == message.id,
                    onLongPress: () => _showMessageActions(message),
                    onReact: (emoji) =>
                        CommunityService.instance.react(message.id, emoji),
                    onVote: (optionIndex) =>
                        CommunityService.instance.vote(message.id, optionIndex),
                    onPlayVoice: () => _togglePlayVoice(message),
                  );
                },
              );
            },
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? JimColors.darkSurface : JimColors.card,
            border: Border(top: BorderSide(color: line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyTo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to ${_displayName(_replyTo!)}: '
                          '${(_replyTo!.text ?? '').length > 40 ? '${(_replyTo!.text ?? '').substring(0, 40)}…' : (_replyTo!.text ?? '')}',
                          style: base.copyWith(
                            fontSize: 13,
                            color: muted,
                            height: 1.45,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _replyTo = null),
                        icon: const Icon(
                          Icons.cancel,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    onPressed: _sendPhoto,
                    icon: const Icon(Icons.photo),
                  ),
                  IconButton(
                    onPressed: _createPoll,
                    icon: const Icon(Icons.bar_chart),
                  ),
                  IconButton(
                    onPressed: _toggleVoiceRecording,
                    icon: Icon(
                      _recording ? Icons.stop_circle : Icons.mic,
                      color: _recording ? Colors.red : null,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composerController,
                      decoration: jimFieldDecoration(
                        dark: isDark,
                        hint: _recording
                            ? 'Recording… tap the mic to stop'
                            : 'Write a message…',
                        borderRadius: 999,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Per-message anonymous toggle, next to the send
                  // field. Shows the effective state (session switch
                  // or this message); tapping flips it.
                  GestureDetector(
                    key: const Key('anonymous-composer-chip'),
                    onTap: _toggleAnonymousComposer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _anonymousEffective
                            ? JimColors.rose
                            : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _anonymousEffective ? JimColors.rose : line,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 13,
                            color: _anonymousEffective ? Colors.white : muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Anonymous',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _anonymousEffective
                                  ? Colors.white
                                  : (isDark
                                      ? JimColors.darkText
                                      : JimColors.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _sendText,
                    icon: const Icon(Icons.arrow_circle_up),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected
                ? (isDark ? JimColors.softBlack : Colors.white)
                : (isDark ? JimColors.darkText : JimColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Horizontal progress rail: weekly top 10, each with avatar, name and
/// a progress ring (% = totalChaptersDone / 151).
class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.onOpenProfile});

  final ValueChanged<AppUser> onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return FutureBuilder<List<AppUser>>(
      future: UserRepository.instance.leaderboardWeekly(limit: 10),
      builder: (context, snapshot) {
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Text(
              'Leaderboard — finish chapters to appear here.',
              style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
            ),
          );
        }
        return SizedBox(
          height: 108,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final pct = (user.totalChaptersDone * 100 / 151).round();
              return GestureDetector(
                onTap: () => onOpenProfile(user),
                child: Container(
                  width: 76,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      _ProgressRing(
                        progress: user.totalChaptersDone / 151,
                        size: 56,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: JimColors.rose,
                            image: user.photoUrl != null &&
                                    user.photoUrl!.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(user.photoUrl!),
                                    fit: BoxFit.cover,
                                    onError: (_, __) {},
                                  )
                                : null,
                          ),
                          child: user.photoUrl == null || user.photoUrl!.isEmpty
                              ? Text(
                                  user.name.isNotEmpty
                                      ? user.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: base.copyWith(fontSize: 12, height: 1.45),
                      ),
                      Text(
                        '$pct%',
                        style: base.copyWith(
                          fontSize: 12,
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// A thin progress ring drawn with CustomPaint, with [child] centred.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.progress,
    required this.size,
    required this.child,
  });

  final double progress;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: progress.clamp(0.0, 1.0),
              trackColor: isDark ? JimColors.darkLine : JimColors.line,
              fillColor: JimColors.rose,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

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
    final radius = size.width / 2 - 3;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, track);
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.currentUid,
    required this.isPlayingVoice,
    required this.onLongPress,
    required this.onReact,
    required this.onVote,
    required this.onPlayVoice,
  });

  final CommunityMessage message;
  final String? currentUid;
  final bool isPlayingVoice;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReact;
  final ValueChanged<int> onVote;
  final VoidCallback onPlayVoice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    if (message.flagged) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? JimColors.darkBg : const Color(0xFFF0EEE9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: line),
        ),
        child: Text(
          'Removed by moderation',
          style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
        ),
      );
    }
    final isMine = currentUid != null && message.authorId == currentUid;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isMine
              ? JimColors.rose.withValues(alpha: isDark ? 0.22 : 0.10)
              : (isDark ? JimColors.darkSurface : JimColors.card),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar circle: generic grey person for anonymous
                // messages (no photo, no name); initial / photo otherwise.
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: message.isAnonymous
                        ? (isDark ? JimColors.darkLine : JimColors.line)
                        : JimColors.rose,
                    image: !message.isAnonymous &&
                            message.authorPhoto != null &&
                            message.authorPhoto!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(message.authorPhoto!),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  child: message.isAnonymous
                      ? const Icon(
                          Icons.person,
                          size: 15,
                          color: Colors.white,
                        )
                      : message.authorPhoto == null ||
                              message.authorPhoto!.isEmpty
                          ? Text(
                              message.authorName.isNotEmpty
                                  ? message.authorName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            )
                          : null,
                ),
                const SizedBox(width: 8),
                if (message.pinned)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: JimColors.rose,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Pinned',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _displayName(message),
                    style: base.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatTimestamp(message.timestamp),
                  style: base.copyWith(fontSize: 12, color: muted),
                ),
              ],
            ),
            if (message.replyToText != null &&
                message.replyToText!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? JimColors.darkBg : JimColors.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(color: JimColors.rose, width: 3),
                  ),
                ),
                child: Text(
                  message.replyToText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: base.copyWith(
                    fontSize: 13,
                    color: muted,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (message.text != null && message.text!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                message.text!,
                style: base.copyWith(fontSize: 15, height: 1.45),
              ),
            ],
            if (message.photoUrl != null && message.photoUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: message.photoUrl!.startsWith('http')
                    ? Image.network(
                        message.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      )
                    : Image.file(
                        File(message.photoUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
              ),
            ],
            if (message.type == MessageType.poll && message.poll != null) ...[
              const SizedBox(height: 10),
              _PollCard(
                poll: message.poll!,
                currentUid: currentUid,
                onVote: onVote,
              ),
            ],
            if (message.type == MessageType.voice &&
                message.voiceUrl != null) ...[
              const SizedBox(height: 10),
              _VoiceRow(
                isPlaying: isPlayingVoice,
                onPlay: onPlayVoice,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                for (final emoji in ['❤️', '👍', '🎉'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => onReact(emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? JimColors.darkBg : JimColors.paper,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: line),
                        ),
                        child: Text(
                          '$emoji ${message.reactions[emoji] ?? 0}',
                          style: base.copyWith(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                if (currentUid != null &&
                    message.bookmarkedBy.contains(currentUid))
                  const Icon(
                    Icons.bookmark,
                    size: 16,
                    color: JimColors.rose,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.poll,
    required this.currentUid,
    required this.onVote,
  });

  final PollData poll;
  final String? currentUid;
  final ValueChanged<int> onVote;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    final myVote = currentUid == null ? null : poll.votes[currentUid];
    final counts = poll.counts;
    final percentages = poll.percentages;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? JimColors.darkBg : JimColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.question,
            style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < poll.options.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == poll.options.length - 1 ? 0 : 8,
              ),
              child: GestureDetector(
                onTap: myVote == null ? () => onVote(i) : null,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: myVote == i ? JimColors.rose : line,
                      width: myVote == i ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${myVote == i ? '✓ ' : ''}${poll.options[i]}',
                              style: base.copyWith(
                                fontSize: 14,
                                fontWeight: myVote == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.45,
                              ),
                            ),
                          ),
                          Text(
                            '${percentages[i].round()}% · ${counts[i]}',
                            style: base.copyWith(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 6,
                          color: line,
                          child: FractionallySizedBox(
                            widthFactor: (percentages[i] / 100).clamp(0.0, 1.0),
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: 6,
                              color: JimColors.rose,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (myVote != null) ...[
            const SizedBox(height: 8),
            Text(
              'You voted — one vote per person.',
              style: base.copyWith(fontSize: 12, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.isPlaying, required this.onPlay});

  final bool isPlaying;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Row(
      children: [
        IconButton(
          onPressed: onPlay,
          icon: Icon(
            isPlaying ? Icons.stop_circle : Icons.play_circle,
            size: 32,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isPlaying ? 'Playing…' : 'Voice message',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
        ),
      ],
    );
  }
}

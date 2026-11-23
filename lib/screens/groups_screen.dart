import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/community_message.dart';
import '../services/groups_service.dart';
import '../services/community_service.dart';

/// Study groups: your groups, create one (you get a 6-char code to
/// share), or join one with a code. Tapping a group opens its detail
/// screen with Members and Notes.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Create a group'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Group name',
            padding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      final code = await GroupsService.instance.createGroup(name);
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Group created'),
          content: Text(
            '"$name" is ready. Share this code so friends can join:\n$code',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Could not create the group'),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _joinGroup(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Join a group'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '6-character code',
            textCapitalization: TextCapitalization.characters,
            padding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !context.mounted) return;
    final joined = await GroupsService.instance.joinGroup(code);
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(joined ? 'Joined!' : 'Could not join'),
        content: Text(
          joined
              ? 'Welcome to the group.'
              : 'No group uses that code. Check it and try again.',
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Groups'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton.filled(
                      borderRadius: BorderRadius.circular(14),
                      onPressed: () => _createGroup(context),
                      child: const Text('Create group'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      color: isDark ? JimColors.darkSurface : JimColors.card,
                      borderRadius: BorderRadius.circular(14),
                      onPressed: () => _joinGroup(context),
                      child: const Text('Join group'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: GroupsService.instance.myGroups(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not load your groups.',
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
                      child: CupertinoActivityIndicator(),
                    );
                  }
                  final groups = snapshot.data!;
                  if (groups.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No groups yet. Create one, or join with a code from a friend.',
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
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final name = (group['name'] as String?) ?? 'Group';
                      final code = (group['code'] as String?) ?? '';
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => GroupDetailScreen(
                                groupName: name,
                                code: code,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? JimColors.darkSurface
                                : JimColors.card,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: line),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: base.copyWith(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Code: $code',
                                      style: base.copyWith(
                                        fontSize: 14,
                                        color: muted,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(CupertinoIcons.chevron_right),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One group: Members and Notes segments. Notes are just community
/// messages inside the group (same service methods, filtered by group).
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    required this.groupName,
    required this.code,
    super.key,
  });

  final String groupName;
  final String code;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  int _segment = 0;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _sendNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    _noteController.clear();
    try {
      await CommunityService.instance.sendText(text);
    } catch (_) {
      // Sending a group note is best effort; the offline queue
      // (SyncService) retries it when the connection returns.
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Note not sent'),
            content: const Text(
              'Check your connection — it will sync when back online.',
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
      }
    }
  }

  Future<void> _sendNotePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (picked == null) return;
    try {
      await CommunityService.instance.sendPhoto(picked.path);
    } catch (_) {
      // Best effort; see _sendNote.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.groupName),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _segment,
                backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
                thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
                children: const {
                  0: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('Members'),
                  ),
                  1: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('Notes'),
                  ),
                },
                onValueChanged: (index) {
                  if (index != null) setState(() => _segment = index);
                },
              ),
            ),
            if (_segment == 0)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Members appear here when online.',
                      textAlign: TextAlign.center,
                      style: base.copyWith(
                        fontSize: 15,
                        color: muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<CommunityMessage>>(
                        stream: CommunityService.instance.messagesStream(
                          groupId: widget.code,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Could not load group notes.',
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
                              child: CupertinoActivityIndicator(),
                            );
                          }
                          final messages = [...snapshot.data!]
                            ..sort(
                              (a, b) =>
                                  a.timestamp.compareTo(b.timestamp),
                            );
                          if (messages.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No notes yet — share the first one.',
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
                            padding:
                                const EdgeInsets.fromLTRB(24, 8, 24, 16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              if (message.flagged) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? JimColors.darkBg
                                        : const Color(0xFFF0EEE9),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: line),
                                  ),
                                  child: Text(
                                    'Removed by moderation',
                                    style: base.copyWith(
                                      fontSize: 14,
                                      color: muted,
                                      height: 1.45,
                                    ),
                                  ),
                                );
                              }
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? JimColors.darkSurface
                                      : JimColors.card,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: line),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.authorName,
                                      style: base.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (message.text != null &&
                                        message.text!.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        message.text!,
                                        style: base.copyWith(
                                          fontSize: 15,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color:
                            isDark ? JimColors.darkSurface : JimColors.card,
                        border: Border(top: BorderSide(color: line)),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Row(
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: _sendNotePhoto,
                            child: const Icon(CupertinoIcons.photo),
                          ),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _noteController,
                              placeholder: 'Write a group note…',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? JimColors.darkBg
                                    : JimColors.paper,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: line),
                              ),
                              onSubmitted: (_) => _sendNote(),
                            ),
                          ),
                          const SizedBox(width: 4),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: _sendNote,
                            child: const Icon(
                              CupertinoIcons.arrow_up_circle_fill,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

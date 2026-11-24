import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/groups_service.dart';

/// Study groups: your groups, create one (you get a 6-char code to
/// share), or join one with a code. Tapping a group opens its detail
/// screen (name + code). There is no group chat: the backend has no
/// group_id on messages, so groups are create/join/list only — the
/// community tab is where everyone talks.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context) async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a group'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: controller,
            decoration: jimFieldDecoration(
              dark: isDark,
              hint: 'Group name',
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Group created'),
          content: Text(
            '"$name" is ready. Share this code so friends can join:\n$code',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Could not create the group'),
          content: Text(e.toString()),
          actions: [
            TextButton(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a group'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: jimFieldDecoration(
              dark: isDark,
              hint: '6-character code',
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !context.mounted) return;
    bool joined = false;
    String? error;
    try {
      joined = await GroupsService.instance.joinGroup(code);
    } catch (e) {
      error = AuthService.friendlyError(e);
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          error != null
              ? 'Could not join'
              : joined
                  ? 'Joined!'
                  : 'Could not join',
        ),
        content: Text(
          error ??
              (joined
                  ? 'Welcome to the group.'
                  : 'No group uses that code. Check it and try again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _createGroup(context),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Create group'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _joinGroup(context),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isDark ? JimColors.darkSurface : JimColors.card,
                        foregroundColor:
                            isDark ? JimColors.darkText : JimColors.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
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
                      child: CircularProgressIndicator(),
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
                            MaterialPageRoute(
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
                            color:
                                isDark ? JimColors.darkSurface : JimColors.card,
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
                              const Icon(Icons.chevron_right),
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

/// One group: name + invite code. There is no group chat or group
/// notes tab: the backend has no group_id on messages, so groups are
/// create/join/list only — the community tab is where everyone talks.
class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({
    required this.groupName,
    required this.code,
    super.key,
  });

  final String groupName;
  final String code;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return Scaffold(
      appBar: AppBar(
        title: Text(groupName),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? JimColors.darkSurface : JimColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupName,
                    style: base.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Invite code: $code',
                    style: base.copyWith(
                      fontSize: 14,
                      color: muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Share this code so friends can join. Group chat lives in the community tab.',
                    style: base.copyWith(
                      fontSize: 14,
                      color: muted,
                      height: 1.45,
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


import 'package:flutter/material.dart';

import '../main.dart';
import '../models/app_user.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';

/// Admin panel (web `/admin` only). Guarded by the gate: only admins
/// (per [AdminService.isAdmin], from GET /api/auth/me) reach here.
///
/// Overview shows Total users + Active today (computed from the users
/// list). Message/report counts, mute, ban and delete-message do not
/// exist on the backend — the panel does not pretend they do.
///
/// Users: newest first, 50 per page with a Load more button. Deleting
/// a user removes them (and their messages/milestones) server-side;
/// the admin can never delete themselves (the server answers 400).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.onSignOut});

  /// Shown as a logout button in the AppBar. Set by the /admin gate
  /// (web); null when the panel is opened any other way.
  final VoidCallback? onSignOut;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const _pageSize = 50;

  final List<AppUser> _users = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Map<String, int>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AdminService.instance.listUsers(limit: _pageSize);
      final stats = await AdminService.instance.stats();
      if (!mounted) return;
      setState(() {
        _users
          ..clear()
          ..addAll(page['users'] as List<AppUser>);
        _total = (page['total'] as int?) ?? _users.length;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthService.friendlyError(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _users.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final page = await AdminService.instance.listUsers(
        limit: _pageSize,
        offset: _users.length,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(page['users'] as List<AppUser>);
        _total = (page['total'] as int?) ?? _total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = AuthService.friendlyError(e);
      });
    }
  }

  Future<void> _showInfo(BuildContext context, String message) async {
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

  Future<void> _confirmDelete(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this user?'),
        content: Text(
          '${user.name} (${user.email}) will be removed, along with their messages and milestones. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminService.instance.deleteUser(user.id);
      if (!mounted) return;
      setState(() {
        _users.removeWhere((u) => u.id == user.id);
        _total = _total > 0 ? _total - 1 : 0;
      });
    } catch (e) {
      if (!mounted) return;
      await _showInfo(context, AuthService.friendlyError(e));
    }
  }

  Widget _statCard(
    BuildContext context,
    String label,
    int value,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? JimColors.darkSurface : JimColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: base.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: base.copyWith(fontSize: 13, color: muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    final myId = AuthService.instance.currentUid;
    if (!AdminService.instance.isAdmin()) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin panel')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Admin only.',
              style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [
          if (widget.onSignOut != null)
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _users.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: base.copyWith(
                              fontSize: 15,
                              color: muted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    children: [
                      Text(
                        'Overview',
                        style: base.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _statCard(
                            context,
                            'Total users',
                            _stats?['totalUsers'] ?? _total,
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            context,
                            'Active today',
                            _stats?['activeToday'] ?? 0,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Users ($_total)',
                        style: base.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_users.isEmpty)
                        Text(
                          'No users yet.',
                          style: base.copyWith(
                            fontSize: 15,
                            color: muted,
                            height: 1.45,
                          ),
                        )
                      else
                        ..._users.map((user) {
                          final isMe = user.id == myId;
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
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: isDark
                                      ? JimColors.darkLine
                                      : JimColors.line,
                                  backgroundImage: user.photoUrl != null
                                      ? NetworkImage(user.photoUrl!)
                                      : null,
                                  child: user.photoUrl == null
                                      ? Text(
                                          user.name.isNotEmpty
                                              ? user.name[0].toUpperCase()
                                              : '?',
                                          style: base.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.name.isNotEmpty
                                            ? user.name
                                            : 'Student',
                                        style: base.copyWith(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (user.email.isNotEmpty)
                                        Text(
                                          user.email,
                                          style: base.copyWith(
                                            fontSize: 13,
                                            color: muted,
                                          ),
                                        ),
                                      Text(
                                        [
                                          '${user.totalChaptersDone} chapters',
                                          if (user.isAdmin) 'admin',
                                          if (isMe) 'you',
                                        ].join(' · '),
                                        style: base.copyWith(
                                          fontSize: 13,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isMe)
                                  IconButton(
                                    onPressed: () => _confirmDelete(user),
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red,
                                    tooltip: 'Delete user',
                                  ),
                              ],
                            ),
                          );
                        }),
                      if (_users.length < _total)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Center(
                            child: FilledButton.tonal(
                              onPressed: _loadingMore ? null : _loadMore,
                              child: Text(
                                _loadingMore
                                    ? 'Loading…'
                                    : 'Load more',
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

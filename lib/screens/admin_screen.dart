import 'package:flutter/material.dart';

import '../main.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';

/// Admin panel. Guarded: only admins (per [AdminService.isAdmin]) see
/// the stats and reports; everyone else sees "Admin only".
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

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

  Future<void> _confirm(
    BuildContext context,
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await action();
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
    final uid = AuthService.instance.effectiveUid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
      ),
      body: SafeArea(
        child: uid == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Admin only — sign in with an admin account.',
                    textAlign: TextAlign.center,
                    style: base.copyWith(
                      fontSize: 15,
                      color: muted,
                      height: 1.45,
                    ),
                  ),
                ),
              )
            : FutureBuilder<bool>(
                future: AdminService.instance.isAdmin(uid),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (snapshot.data != true) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Admin only.',
                          style: base.copyWith(
                            fontSize: 15,
                            color: muted,
                            height: 1.45,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView(
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
                      FutureBuilder<Map<String, int>>(
                        future: AdminService.instance.stats(),
                        builder: (context, statsSnapshot) {
                          final stats = statsSnapshot.data ??
                              {
                                'totalUsers': 0,
                                'totalMessages': 0,
                                'totalReports': 0,
                                'activeToday': 0,
                              };
                          return Column(
                            children: [
                              Row(
                                children: [
                                  _statCard(
                                    context,
                                    'Total users',
                                    stats['totalUsers'] ?? 0,
                                  ),
                                  const SizedBox(width: 12),
                                  _statCard(
                                    context,
                                    'Total messages',
                                    stats['totalMessages'] ?? 0,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _statCard(
                                    context,
                                    'Reports',
                                    stats['totalReports'] ?? 0,
                                  ),
                                  const SizedBox(width: 12),
                                  _statCard(
                                    context,
                                    'Active today',
                                    stats['activeToday'] ?? 0,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Reports',
                        style: base.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: AdminService.instance.reportsStream(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final reports = snapshot.data!;
                          if (reports.isEmpty) {
                            return Text(
                              'No reports — nothing needs review.',
                              style: base.copyWith(
                                fontSize: 15,
                                color: muted,
                                height: 1.45,
                              ),
                            );
                          }
                          return Column(
                            children: reports.map((report) {
                              final reportId = (report['id'] as String?) ?? '';
                              final messageId =
                                  (report['messageId'] as String?) ?? '';
                              final reason =
                                  (report['reason'] as String?) ?? '';
                              final reporter =
                                  (report['reporterName'] as String?) ??
                                      'Someone';
                              // The report may also carry the author's uid
                              // (key name depends on the backend); mute/ban
                              // need it, so the buttons fall back to an
                              // explanation when it is missing.
                              final userUid = (report['authorId'] as String?) ??
                                  (report['userId'] as String?) ??
                                  (report['reporterUid'] as String?);
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reason,
                                      style: base.copyWith(
                                        fontSize: 15,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Reported by $reporter · $reportId',
                                      style: base.copyWith(
                                        fontSize: 13,
                                        color: muted,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton(
                                          onPressed: () => _confirm(
                                            context,
                                            'Delete this message?',
                                            'The message will be removed from the community.',
                                            () => AdminService.instance
                                                .deleteMessage(messageId),
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isDark
                                                ? JimColors.darkBg
                                                : JimColors.paper,
                                            foregroundColor: isDark
                                                ? JimColors.darkText
                                                : JimColors.ink,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            shape: const StadiumBorder(),
                                          ),
                                          child: const Text(
                                            'Delete message',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () {
                                            if (userUid == null ||
                                                userUid.isEmpty) {
                                              _showInfo(
                                                context,
                                                'This report does not include the author — open the message in the community to act on them.',
                                              );
                                              return;
                                            }
                                            _confirm(
                                              context,
                                              'Mute this user?',
                                              'They will not be able to post for a while.',
                                              () => AdminService.instance
                                                  .muteUser(userUid),
                                            );
                                          },
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isDark
                                                ? JimColors.darkBg
                                                : JimColors.paper,
                                            foregroundColor: isDark
                                                ? JimColors.darkText
                                                : JimColors.ink,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            shape: const StadiumBorder(),
                                          ),
                                          child: const Text(
                                            'Mute user',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () {
                                            if (userUid == null ||
                                                userUid.isEmpty) {
                                              _showInfo(
                                                context,
                                                'This report does not include the author — open the message in the community to act on them.',
                                              );
                                              return;
                                            }
                                            _confirm(
                                              context,
                                              'Ban this user?',
                                              'They will lose access to the community.',
                                              () => AdminService.instance
                                                  .banUser(userUid),
                                            );
                                          },
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isDark
                                                ? JimColors.darkBg
                                                : JimColors.paper,
                                            foregroundColor: isDark
                                                ? JimColors.darkText
                                                : JimColors.ink,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            shape: const StadiumBorder(),
                                          ),
                                          child: const Text(
                                            'Ban user',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Analytics',
                        style: base.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<Map<String, int>>(
                        future: AdminService.instance.stats(),
                        builder: (context, statsSnapshot) {
                          final stats = statsSnapshot.data ?? {};
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? JimColors.darkSurface
                                  : JimColors.card,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: line),
                            ),
                            child: Column(
                              children: [
                                _AnalyticsRow(
                                  label: 'Registered users',
                                  value: '${stats['totalUsers'] ?? 0}',
                                ),
                                _AnalyticsRow(
                                  label: 'Messages sent',
                                  value: '${stats['totalMessages'] ?? 0}',
                                ),
                                _AnalyticsRow(
                                  label: 'Reports filed',
                                  value: '${stats['totalReports'] ?? 0}',
                                ),
                                _AnalyticsRow(
                                  label: 'Active today',
                                  value: '${stats['activeToday'] ?? 0}',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _AnalyticsRow extends StatelessWidget {
  const _AnalyticsRow({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
            ),
          ),
          Text(
            value,
            style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

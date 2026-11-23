import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../main.dart';

// TODO — replace with real CI artifact URLs.
const String androidApkUrl =
    'https://github.com/devrafi223-arch/hsc-revision-master/releases';
const String pcBuildUrl =
    'https://github.com/devrafi223-arch/hsc-revision-master/releases';

/// "Download app" card: Android APK and Windows / Linux (PC) links.
///
/// Web only — on Android / desktop builds this renders nothing
/// ([kIsWeb] guard). No url_launcher dependency: tapping a button shows
/// the link in a dialog (copying/sharing links is closed).
class DownloadSection extends StatelessWidget {
  const DownloadSection({super.key});

  Future<void> _showLink(BuildContext context, String title, String url) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            url,
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Shown only on web.
    if (!kIsWeb) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? JimColors.darkSurface : JimColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Download app',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Take the tracker with you — same progress, everywhere.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _showLink(
                context,
                'Android APK',
                androidApkUrl,
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Android APK'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => _showLink(
                context,
                'Windows / Linux (PC)',
                pcBuildUrl,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? JimColors.darkBg : JimColors.paper,
                foregroundColor: isDark ? JimColors.darkText : JimColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Windows / Linux (PC)'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Download links point to the releases page until the next build publishes direct links.',
            style: base.copyWith(fontSize: 13, color: muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

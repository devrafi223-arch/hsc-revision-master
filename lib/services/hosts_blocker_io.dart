import 'dart:io';

/// Website blocking via the hosts file — Windows / Linux only.
///
/// Blocked domains are redirected to 127.0.0.1 inside a marked section
/// (`# HSC-FOCUS-BLOCK-START` … `# HSC-FOCUS-BLOCK-END`), so removing
/// the block restores the file exactly. Writing the hosts file needs
/// admin / root: on Windows the app must be run as administrator, on
/// Linux with sudo. When the write fails (the normal case for a
/// normally-launched app) [apply] returns false and the UI explains
/// this instead of pretending the block works.
///
/// [hostsPath] exists only so tests can point at a temp file; in the
/// app it is always left null (the real system hosts file). In a
/// flutter_test run (FLUTTER_TEST=true) the real system file is never
/// touched unless an explicit override path is given.
class HostsBlocker {
  static const List<String> defaultDomains = [
    'youtube.com',
    'www.youtube.com',
    'facebook.com',
    'www.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'tiktok.com',
    'www.tiktok.com',
    'x.com',
    'www.x.com',
    'reddit.com',
    'www.reddit.com',
    'netflix.com',
    'www.netflix.com',
  ];

  static const String _startMarker = '# HSC-FOCUS-BLOCK-START';
  static const String _endMarker = '# HSC-FOCUS-BLOCK-END';

  static String get systemHostsPath => Platform.isWindows
      ? r'C:\Windows\System32\drivers\etc\hosts'
      : '/etc/hosts';

  static bool get _isTestRun =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  static String _resolvePath(String? hostsPath) =>
      hostsPath ?? systemHostsPath;

  static bool _guard(String? hostsPath) =>
      hostsPath != null || !_isTestRun;

  static Future<bool> canWrite({String? hostsPath}) async {
    if (!_guard(hostsPath)) return false;
    try {
      final file = File(_resolvePath(hostsPath));
      final raf = await file.open(mode: FileMode.append);
      await raf.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isApplied({String? hostsPath}) async {
    if (!_guard(hostsPath)) return false;
    try {
      final content = await File(_resolvePath(hostsPath)).readAsString();
      return content.contains(_startMarker);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> apply(List<String> domains,
      {String? hostsPath}) async {
    if (!_guard(hostsPath)) return false;
    try {
      final file = File(_resolvePath(hostsPath));
      var content = await file.readAsString();
      content = _withoutSection(content);
      final section = StringBuffer('\n$_startMarker\n');
      for (final domain in domains) {
        section.writeln('127.0.0.1 $domain');
      }
      section.writeln(_endMarker);
      await file.writeAsString('$content$section');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> remove({String? hostsPath}) async {
    if (!_guard(hostsPath)) return false;
    try {
      final file = File(_resolvePath(hostsPath));
      final content = await file.readAsString();
      if (!content.contains(_startMarker)) return true;
      await file.writeAsString(_withoutSection(content));
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _withoutSection(String content) {
    final start = content.indexOf(_startMarker);
    if (start < 0) return content;
    final end = content.indexOf(_endMarker, start);
    if (end < 0) return content.substring(0, start);
    return content.substring(0, start) +
        content.substring(end + _endMarker.length);
  }
}

// No-op hosts blocker for web builds (no hosts file there).

/// Website blocking via the hosts file — desktop only.
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

  static Future<bool> canWrite({String? hostsPath}) async => false;

  static Future<bool> isApplied({String? hostsPath}) async => false;

  static Future<bool> apply(List<String> domains, {String? hostsPath}) async =>
      false;

  static Future<bool> remove({String? hostsPath}) async => false;
}

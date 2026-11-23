import 'dart:convert';

/// In-memory queue of operations made while offline, persisted as JSON in
/// SharedPreferences under key 'offline-queue-v1' (see CommunityService /
/// SyncService). Each op is a plain JSON-safe map, e.g.
/// `{'type': 'message', 'text': '...', ...}` or `{'type': 'note', ...}`.
/// Pure Dart — no Firebase.
class OfflineQueue {
  OfflineQueue();

  final List<Map<String, dynamic>> _pending = [];

  void enqueue(Map<String, dynamic> op) {
    _pending.add(Map<String, dynamic>.from(op));
  }

  List<Map<String, dynamic>> get pending => List.unmodifiable(_pending);

  int get length => _pending.length;

  bool get isEmpty => _pending.isEmpty;

  void removeAt(int i) {
    _pending.removeAt(i);
  }

  void clear() {
    _pending.clear();
  }

  /// JSON string of the pending ops (for SharedPreferences storage).
  String toJson() => jsonEncode(_pending);

  factory OfflineQueue.fromJson(List<dynamic> j) {
    final queue = OfflineQueue();
    for (final item in j) {
      if (item is Map) {
        queue._pending.add(item.cast<String, dynamic>());
      }
    }
    return queue;
  }

  /// Parses a JSON string produced by [toJson]; returns an empty queue
  /// when the string is empty or invalid.
  factory OfflineQueue.fromJsonString(String raw) {
    if (raw.isEmpty) return OfflineQueue();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return OfflineQueue.fromJson(decoded);
    } catch (_) {
      // Corrupt queue data must never crash the app — start fresh.
    }
    return OfflineQueue();
  }
}

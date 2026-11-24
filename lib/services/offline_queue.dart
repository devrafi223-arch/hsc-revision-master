import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// In-memory queue of operations made while offline, persisted as JSON in
/// SharedPreferences under key 'offline-queue-v1' (see SyncService).
/// Each op is a plain JSON-safe map, e.g. `{'type': 'note', ...}`.
/// Pure Dart — no Firebase.
class OfflineQueue {
  OfflineQueue();

  /// SharedPreferences key holding the offline queue JSON.
  static const String queueKey = 'offline-queue-v1';

  /// Loads the persisted queue (empty when nothing was stored).
  static Future<OfflineQueue> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    return OfflineQueue.fromJsonString(prefs.getString(queueKey) ?? '');
  }

  static Future<void> persistQueue(OfflineQueue queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(queueKey, queue.toJson());
  }

  /// Enqueues one op into the persisted offline queue, for replay by
  /// SyncService when the device is back online.
  static Future<void> enqueueOp(Map<String, dynamic> op) async {
    final queue = await loadQueue();
    queue.enqueue(op);
    await persistQueue(queue);
  }

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

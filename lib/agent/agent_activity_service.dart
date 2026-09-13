import 'package:flutter/foundation.dart';

class AgentActivityItem {
  final String id;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final bool isSuccess;
  final bool isReversible;
  final Future<bool> Function()? undoCallback;
  bool isUndone;

  AgentActivityItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.isSuccess = true,
    this.isReversible = false,
    this.undoCallback,
    this.isUndone = false,
  });
}

/// Lightweight activity history for Pal Agent actions.
/// Separate from conversational chat history.
class AgentActivityService extends ChangeNotifier {
  static final AgentActivityService instance = AgentActivityService._();
  AgentActivityService._();

  @visibleForTesting
  static AgentActivityService createTestInstance() => AgentActivityService._();

  final List<AgentActivityItem> _activities = [];
  List<AgentActivityItem> get activities => List.unmodifiable(_activities);

  void recordActivity({
    required String title,
    required String subtitle,
    bool isSuccess = true,
    bool isReversible = false,
    Future<bool> Function()? undoCallback,
  }) {
    final item = AgentActivityItem(
      id: 'act_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      subtitle: subtitle,
      timestamp: DateTime.now(),
      isSuccess: isSuccess,
      isReversible: isReversible,
      undoCallback: undoCallback,
    );
    _activities.insert(0, item);
    // Keep lightweight (max 30 items)
    if (_activities.length > 30) {
      _activities.removeLast();
    }
    notifyListeners();
  }

  Future<bool> undoActivity(String id) async {
    final index = _activities.indexWhere((a) => a.id == id);
    if (index == -1) return false;

    final item = _activities[index];
    if (!item.isReversible || item.isUndone || item.undoCallback == null) {
      return false;
    }

    try {
      final success = await item.undoCallback!();
      if (success) {
        item.isUndone = true;
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('[AgentActivityService] Undo failed: $e');
      return false;
    }
  }

  void clear() {
    _activities.clear();
    notifyListeners();
  }
}


import 'package:shared_preferences/shared_preferences.dart';
import '../models/pid_run_history.dart';

/// Service for persisting PID run history to local storage.
class HistoryService {
  static const String _storageKey = 'pid_run_history';
  static const int _maxHistoryItems = 50;

  SharedPreferences? _prefs;

  /// Initialize the service and load SharedPreferences.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get all saved run histories, sorted by timestamp (newest first).
  Future<List<PidRunHistory>> getHistory() async {
    await init();
    final String? jsonString = _prefs?.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    final histories = PidRunHistory.decodeList(jsonString);
    // Sort by timestamp, newest first
    histories.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return histories;
  }

  /// Add a new run to history.
  Future<void> addRun(PidRunHistory run) async {
    await init();
    final histories = await getHistory();
    histories.insert(0, run);
    
    // Limit history size
    while (histories.length > _maxHistoryItems) {
      histories.removeLast();
    }
    
    await _saveHistories(histories);
  }

  /// Remove a run from history by ID.
  Future<void> removeRun(String id) async {
    await init();
    final histories = await getHistory();
    histories.removeWhere((h) => h.id == id);
    await _saveHistories(histories);
  }

  /// Clear all history.
  Future<void> clearHistory() async {
    await init();
    await _prefs?.remove(_storageKey);
  }

  /// Save histories to storage.
  Future<void> _saveHistories(List<PidRunHistory> histories) async {
    final jsonString = PidRunHistory.encodeList(histories);
    await _prefs?.setString(_storageKey, jsonString);
  }
}

// debug_logger.dart

class DebugLogger {
  static final Map<String, List<String>> _logs = {};
  static bool _enabled = true;

  static void enable() => _enabled = true;
  static void disable() => _enabled = false;

  static void log(String message, {String type = 'INFO', String? tag}) {
    if (!_enabled) return;
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp][$type] ${tag != null ? '[$tag] ' : ''}$message';
    print(logEntry);
    if (!_logs.containsKey(type)) _logs[type] = [];
    _logs[type]!.insert(0, logEntry);
    if (_logs[type]!.length > 1000) _logs[type]!.removeLast();
  }

  static List<String> getLogs({String? type}) {
    if (type != null) return _logs[type] ?? [];
    return _logs.values.expand((list) => list).toList();
  }
}
/// A switch whose change is applied by an async call. While one change is in
/// flight further taps are ignored, and the value only flips once the call
/// succeeded, so the UI never claims a state the device did not reach.
class AsyncToggle {
  AsyncToggle({bool value = false}) : _value = value;

  bool _value;
  bool _busy = false;

  bool get value => _value;
  bool get busy => _busy;

  void reset(bool value) {
    _value = value;
  }

  /// Returns true when the value changed.
  Future<bool> toggle(Future<void> Function(bool next) apply) async {
    if (_busy) return false;
    _busy = true;
    final next = !_value;
    try {
      await apply(next);
      _value = next;
      return true;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }
}

/// Stops the same sheet, dialog or page from opening twice when a button is
/// tapped repeatedly before the first one has finished appearing.
///
/// A repeat open of the same [key] within [window] is ignored. Different
/// screens, or the same screen after the window, open normally.
class OpenGuard {
  OpenGuard._();

  static final Map<String, DateTime> _last = {};
  static const Duration window = Duration(milliseconds: 800);

  /// True when [key] may open now (and records it); false for a repeat tap.
  static bool allow(String key) {
    final now = DateTime.now();
    final prev = _last[key];
    if (prev != null && now.difference(prev) < window) return false;
    _last[key] = now;
    return true;
  }
}

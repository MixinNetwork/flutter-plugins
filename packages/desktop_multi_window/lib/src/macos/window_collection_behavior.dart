/// Window collection behavior options for macOS.
///
/// These values correspond to NSWindowCollectionBehavior in macOS.
class MacOsWindowCollectionBehavior {
  /// Default window collection behavior.
  static const int default_ = 0;

  /// Window can be shown/hidden with Mission Control.
  static const int managed = 1 << 0;

  /// Window is transient and won't be shown in Mission Control.
  static const int transient = 1 << 1;

  /// Window can be shown in different spaces.
  static const int stationary = 1 << 2;

  /// Window participates in Mission Control window selection.
  static const int participatesInCycle = 1 << 3;

  /// Window ignores Mission Control window selection.
  static const int ignoresCycle = 1 << 4;

  /// Window can be shown in full screen mode.
  static const int fullScreenPrimary = 1 << 7;

  /// Window is an auxiliary window in full screen mode.
  static const int fullScreenAuxiliary = 1 << 8;

  /// Window can move between spaces.
  static const int moveToActiveSpace = 1 << 9;

  /// Window follows active space.
  static const int followsActiveSpace = 1 << 10;

  /// Window can be shown on all spaces.
  static const int canJoinAllSpaces = 1 << 11;

  /// Window can be shown on all spaces in full screen mode.
  static const int fullScreenAllowsTiling = 1 << 12;

  /// Window disallows tiling in full screen mode.
  static const int fullScreenDisallowsTiling = 1 << 13;

  /// Combine multiple behaviors using bitwise OR operator.
  ///
  /// Example:
  /// ```dart
  /// final behavior = MacOsWindowCollectionBehavior.managed |
  ///                 MacOsWindowCollectionBehavior.participatesInCycle;
  /// ```
  static int combine(List<int> behaviors) {
    return behaviors.fold(MacOsWindowCollectionBehavior.default_, (a, b) => a | b);
  }
}

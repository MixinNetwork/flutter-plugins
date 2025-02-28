/// The backing store type for a macOS window.
enum MacOSWindowBacking {
  /// NSBackingStoreBuffered – the common choice.
  buffered('buffered'),

  /// NSBackingStoreRetained – rarely used in modern Cocoa.
  retained('retained'),

  /// NSBackingStoreNonretained.
  nonretained('nonretained');

  final String value;
  const MacOSWindowBacking(this.value);
}

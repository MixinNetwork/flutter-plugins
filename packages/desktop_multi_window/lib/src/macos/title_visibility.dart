/// The title visibility options for a macOS window.
enum MacOSTitleVisibility {
  /// The window title is visible.
  visible('visible'),

  /// The window title is hidden.
  hidden('hidden');

  final String value;
  const MacOSTitleVisibility(this.value);
}

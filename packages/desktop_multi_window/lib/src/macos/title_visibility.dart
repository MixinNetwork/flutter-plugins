/// The title visibility options for a macOS window.
enum MacOsTitleVisibility {
  /// The window title is visible.
  visible('visible'),

  /// The window title is hidden.
  hidden('hidden');

  final String value;
  const MacOsTitleVisibility(this.value);
}

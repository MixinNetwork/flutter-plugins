/// The animation behavior options for a macOS window.
enum MacOsAnimationBehavior {
  /// Use the default animation behavior.
  defaultBehavior('default'),

  /// No animations.
  none('none'),

  /// Document window animation.
  documentWindow('documentWindow'),

  /// Alert panel animation.
  alertPanel('alertPanel');

  final String value;
  const MacOsAnimationBehavior(this.value);
}

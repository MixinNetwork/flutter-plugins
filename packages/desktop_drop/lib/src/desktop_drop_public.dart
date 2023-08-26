typedef DesktopDropUnsupportedUriCallback = Future<String?> Function(
  String uri,
);

abstract class DesktopDropPlugin {
  DesktopDropPlugin._();

  /// set the [onUnsupportedUriHandler] in order to handle custom URI schemes
  /// that are not `file:`, e.g. useful for handling `http:`, `https:` or any
  /// other custom URI scheme.
  ///
  /// This callback is only relevant on io platforms.
  static DesktopDropUnsupportedUriCallback? onUnsupportedUriHandler;
}

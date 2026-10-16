import 'dart:typed_data';

import 'native_transport_stub.dart'
    if (dart.library.io) 'native_transport.dart';

/// Platform operations that are independent of a particular drop target.
class DesktopDrop {
  DesktopDrop._();
  static final instance = DesktopDrop._();

  /// Start sandbox access to a macOS bookmark delivered with a dropped item.
  Future<bool> startAccessingSecurityScopedResource({
    required Uint8List bookmark,
  }) async {
    if (bookmark.isEmpty) return false;
    return await NativeTransport.instance.invoke<bool>(
          'startAccessingSecurityScopedResource',
          {'apple-bookmark': bookmark},
        ) ??
        false;
  }

  /// Balance a successful start with a stop after the file operation finishes.
  Future<bool> stopAccessingSecurityScopedResource({
    required Uint8List bookmark,
  }) async {
    if (bookmark.isEmpty) return true;
    return await NativeTransport.instance.invoke<bool>(
          'stopAccessingSecurityScopedResource',
          {'apple-bookmark': bookmark},
        ) ??
        false;
  }
}

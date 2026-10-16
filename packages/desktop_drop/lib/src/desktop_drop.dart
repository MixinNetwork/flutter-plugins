import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'drop_item.dart';
import 'source_reader.dart';

import 'native_transport_stub.dart'
    if (dart.library.io) 'native_transport.dart';

/// Platform operations that are independent of a particular drop target.
class DesktopDrop {
  DesktopDrop._();
  static final instance = DesktopDrop._();

  /// Explicitly open Android's system folder picker for a dropped directory.
  /// Call only in response to a user action, and await this and subsequent
  /// reads inside onDrop. Cancelling throws PlatformException with code
  /// `directory_access_denied`. Other platforms are unsupported.
  Future<void> requestDirectoryAccess({required DropDirectoryItem directory}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Directory access requests are supported only on Android',
      );
    }
    return requestSourceDirectoryAccess(directory.directory);
  }

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

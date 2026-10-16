import 'package:cross_file/cross_file.dart';
import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';

// Browser entries and captured virtual files have no filesystem path. Expose
// their children through the same XDirectory API used by local directories.
XDirectory virtualDirectory(String name, Stream<XEntity> Function() list) =>
    // This package supplies the platform implementation for drag data.
    // ignore: invalid_use_of_internal_member
    ScopedStorageXDirectory.fromPlatform(_VirtualDirectory(name, list));

final class _VirtualDirectory extends PlatformScopedStorageXDirectory {
  _VirtualDirectory(String name, this.children)
    : super.implementation(
        PlatformScopedStorageXDirectoryCreationParams(
          uri:
              'desktop-drop:directory/${_nextId++}/${Uri.encodeComponent(name)}',
        ),
      );

  static int _nextId = 0;
  final Stream<XEntity> Function() children;
  bool _disposed = false;

  @override
  Future<bool> exists() async => !_disposed;
  @override
  Future<bool> canRead() async => !_disposed;
  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  @override
  Stream<PlatformXEntity> list(PlatformListParams params) async* {
    if (_disposed) throw StateError('Dropped directory has been released');
    await for (final entity in children()) {
      // Unwrap only at the platform boundary; XDirectory wraps listed entities.
      // ignore: invalid_use_of_internal_member
      yield entity.platform;
    }
  }
}

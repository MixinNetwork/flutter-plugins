import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:cross_file_web/cross_file_web.dart';
import 'package:web/web.dart' as web;

XFile fromPath(String path) => ScopedStorageXFile.fromCreationParams(
  WebScopedStorageXFileCreationParams.fromObjectUrl(objectUrl: path),
);

ScopedStorageXFile fromBlob(web.Blob blob) =>
    ScopedStorageXFile.fromCreationParams(
      WebScopedStorageXFileCreationParams.fromBlob(blob),
    );

Future<void> saveTo(XFile? source, String destination, Uint8List? bytes) async {
  final blob = bytes == null
      ? await source!.getExtension<WebScopedStorageXFileExtension>()!.getBlob()
      : web.Blob([bytes.toJS].toJS);
  // Use a fresh URL so saving also works after the preview URL was revoked.
  final download = fromBlob(blob);
  try {
    await download.getExtension<WebScopedStorageXFileExtension>()!.download(
      destination,
    );
  } finally {
    // Let the browser consume the download URL before releasing it.
    Future<void>.delayed(const Duration(seconds: 1), download.dispose);
  }
}

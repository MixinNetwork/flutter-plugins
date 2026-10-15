import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<web.Blob> _blob(String path) async {
  final response = await web.window.fetch(path.toJS).toDart;
  if (!response.ok) {
    throw StateError('Cannot read dropped file: HTTP ${response.status}');
  }
  return response.blob().toDart;
}

Future<int> length(String path) async => (await _blob(path)).size;
Future<DateTime> lastModified(String path) async =>
    DateTime.fromMillisecondsSinceEpoch(0);
Stream<Uint8List> openRead(String path, int start, int? end) async* {
  yield* readBlob(await _blob(path), start, end);
}

/// Retain the original Blob and read bounded slices, without fetching its URL.
Stream<Uint8List> readBlob(web.Blob blob, int? start, int? end) async* {
  final from = start ?? 0;
  final until = RangeError.checkValidRange(from, end, blob.size);
  for (var offset = from; offset < until; offset += 1024 * 1024) {
    final next = (offset + 1024 * 1024).clamp(0, until);
    final buffer = await blob.slice(offset, next).arrayBuffer().toDart;
    yield buffer.toDart.asUint8List();
  }
}

Future<void> downloadBlob(web.Blob blob, String name) async {
  final url = web.URL.createObjectURL(blob);
  try {
    (web.document.createElement('a') as web.HTMLAnchorElement)
      ..href = url
      ..download = name
      ..click();
  } finally {
    // Let the browser consume the download URL before releasing it.
    Future<void>.delayed(
      const Duration(seconds: 1),
      () => web.URL.revokeObjectURL(url),
    );
  }
}

Future<void> saveTo(String path, String destination, Uint8List? bytes) async {
  final blob = bytes == null ? await _blob(path) : web.Blob([bytes.toJS].toJS);
  await downloadBlob(blob, destination);
}

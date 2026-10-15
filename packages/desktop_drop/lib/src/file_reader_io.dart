import 'dart:io';
import 'dart:typed_data';

Future<int> length(String path) => File(path).length();
Future<DateTime> lastModified(String path) => File(path).lastModified();
Stream<Uint8List> openRead(String path, int start, int? end) =>
    File(path)
        .openRead(start, end)
        .map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
Future<void> saveTo(String path, String destination, Uint8List? bytes) async {
  if (bytes != null) {
    await File(destination).writeAsBytes(bytes);
  } else {
    await File(path).copy(destination);
  }
}

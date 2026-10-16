import 'package:mime/mime.dart';

String? fileMimeType(String? provided, String? name, [String? path]) {
  if (provided != null && provided.isNotEmpty) return provided;
  final filename = name != null && name.isNotEmpty ? name : path ?? '';
  return filename.contains('.') ? lookupMimeType(filename) : null;
}

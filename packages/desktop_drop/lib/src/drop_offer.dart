import 'package:flutter/foundation.dart';

/// Representations advertised by a drag source.
enum DropType { file, text, url }

/// File metadata available before a drop. Reading contents is reserved for the
/// files delivered by onDragDone. A promised file has no path yet.
@immutable
class DropFilePreview {
  const DropFilePreview({
    required this.name,
    this.path,
    this.mimeType,
    this.isDirectory,
    this.isPromised = false,
  });

  final String name;
  final String? path;
  final String? mimeType;
  final bool? isDirectory;
  final bool isPromised;

  factory DropFilePreview.fromMap(Map<Object?, Object?> map) => DropFilePreview(
    name: map['name'] as String? ?? '',
    path: map['path'] as String?,
    mimeType: map['mimeType'] as String?,
    isDirectory: map['isDirectory'] as bool?,
    isPromised: map['isPromised'] as bool? ?? false,
  );
}

/// The data a target can inspect synchronously when deciding whether to accept.
///
/// [types] can advertise a representation whose value is not available yet.
/// Browsers protect text/URL values during hover, and macOS file promises and
/// Linux portals may not expose paths until a drop. In these cases [isComplete]
/// is false. The predicate is called again when the user releases the drag.
@immutable
class DropOffer {
  DropOffer({
    required Set<DropType> types,
    List<DropFilePreview> files = const [],
    this.text,
    List<Uri> urls = const [],
    this.isComplete = true,
  }) : types = Set.unmodifiable(types),
       files = List.unmodifiable(files),
       urls = List.unmodifiable(urls);

  final Set<DropType> types;
  final List<DropFilePreview> files;
  final String? text;
  final List<Uri> urls;
  final bool isComplete;

  factory DropOffer.fromMap(Map<Object?, Object?> map) => DropOffer(
    types: (map['types'] as List? ?? const [])
        .whereType<String>()
        .map((name) => DropType.values.byName(name))
        .toSet(),
    files: (map['files'] as List? ?? const [])
        .cast<Map>()
        .map((file) => DropFilePreview.fromMap(file))
        .toList(),
    text: map['text'] as String?,
    urls: (map['urls'] as List? ?? const [])
        .cast<String>()
        .map(Uri.parse)
        .toList(),
    isComplete: map['isComplete'] as bool? ?? true,
  );
}

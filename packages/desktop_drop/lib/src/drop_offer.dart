import 'package:flutter/foundation.dart';

import 'file_mime_type.dart';
import 'file_tree.dart';

/// Broad kinds available to a synchronous drag decision.
enum DropItemKind { file, string, directory }

/// The operation requested by a target. Unsupported operations reject the drag.
/// Native ABI values are index + 1; zero is reserved for rejection.
enum DropOperation { copy, move, link }

/// Metadata visible during a drag. A string's [value] can remain unavailable
/// until drop. A virtual file can advertise a name without a local path.
@immutable
class DropItemPreview {
  const DropItemPreview({
    required this.kind,
    String? mimeType,
    this.name,
    this.localPath,
    this.value,
    this.isPromised = false,
  }) : // Preserve the public constructor parameter name.
       // ignore: prefer_initializing_formals
       _mimeType = mimeType;
  final DropItemKind kind;
  final String? _mimeType;

  /// File types fall back to the filename when the source omits a MIME type.
  String? get mimeType => kind == DropItemKind.file
      ? fileMimeType(_mimeType, name, localPath)
      : _mimeType;
  final String? name;
  final String? localPath;
  final String? value;
  final bool isPromised;
}

/// The data a target can inspect synchronously when deciding whether to accept.
///
/// [items] can advertise a representation whose value is not available yet.
/// Browsers and iOS protect string values during hover, and macOS promises and
/// Linux portals may not expose paths until a drop. In these cases [isComplete]
/// is false. The predicate is called again when the user releases the drag.
@immutable
class DropOffer {
  DropOffer({
    required List<DropItemPreview> items,
    this.isComplete = true,
    Set<DropOperation> allowedOperations = const {DropOperation.copy},
  }) : items = List.unmodifiable(items),
       allowedOperations = Set.unmodifiable(allowedOperations);

  final List<DropItemPreview> items;
  final bool isComplete;

  /// Operations supported by both the source and adapter. iOS currently
  /// advertises copy only to preserve sources through asynchronous onDrop.
  final Set<DropOperation> allowedOperations;

  factory DropOffer.fromMap(Map<Object?, Object?> map) => DropOffer(
    items: [
      for (final file in fileTree(
        (map['files'] as List? ?? const []).cast<Map>(),
      ))
        DropItemPreview(
          kind: file['isDirectory'] == true
              ? DropItemKind.directory
              : DropItemKind.file,
          name: file['name'] as String?,
          localPath: file['path'] as String?,
          mimeType: file['mimeType'] as String?,
          isPromised: file['isPromised'] as bool? ?? false,
        ),
      for (final string in (map['strings'] as List? ?? const []).cast<Map>())
        DropItemPreview(
          kind: DropItemKind.string,
          mimeType: string['mimeType'] as String,
          value: string['value'] as String?,
        ),
    ],
    isComplete: map['isComplete'] as bool? ?? true,
    allowedOperations: DropOperation.values
        .where(
          (operation) => (map['allowedOperations'] as List? ?? const [])
              .contains(operation.name),
        )
        .toSet(),
  );
}

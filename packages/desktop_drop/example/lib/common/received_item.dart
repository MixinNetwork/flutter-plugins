import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Content owned by the example after reading during onDrop.
class ReceivedItem {
  const ReceivedItem({this.bytes, this.children, this.error});
  final Uint8List? bytes;
  final List<DropItem>? children;
  final Object? error;
}

Future<Map<DropItem, ReceivedItem>> readDrop(
  DropDetails event, {
  Future<bool> Function(DropDirectoryItem directory)? onDirectoryAccessRequired,
}) async {
  final content = <DropItem, ReceivedItem>{};
  final accessRequested = <DropDirectoryItem>{};

  Future<void> read(DropItem item) async {
    try {
      if (item is DropFileItem) {
        content[item] = ReceivedItem(bytes: await item.file.readAsBytes());
      } else if (item is DropDirectoryItem) {
        final children = <DropItem>[];
        // Keep the discovered entries even if one later entry fails.
        content[item] = ReceivedItem(children: children);
        await for (final entity in item.directory.list()) {
          final segments = Uri.parse(entity.uri).pathSegments
              .where((part) => part.isNotEmpty);
          final name = entity is XFile ? await entity.name() : null;
          final label =
              name ?? (segments.isEmpty ? 'Unnamed item' : segments.last);
          final child = switch (entity) {
            XFile() => DropFileItem(file: entity, name: label),
            XDirectory() => DropDirectoryItem(directory: entity, name: label),
            _ => throw StateError('Unsupported directory entry'),
          };
          children.add(child);
          await read(child);
        }
      } else {
        content[item] = const ReceivedItem();
      }
    } catch (error) {
      if (error is PlatformException &&
          error.code == 'directory_access_required' &&
          item is DropDirectoryItem &&
          onDirectoryAccessRequired != null &&
          accessRequested.add(item)) {
        try {
          if (await onDirectoryAccessRequired(item)) {
            // The application chose to authorize; retry the same source while
            // onDrop still owns its lifetime.
            await read(item);
            return;
          }
        } catch (accessError) {
          content[item] = ReceivedItem(error: accessError);
          return;
        }
      }
      content[item] = ReceivedItem(
        children: content[item]?.children,
        error: error,
      );
    }
  }

  for (final item in event.items) {
    final bookmark = switch (item) {
      DropFileItem(:final appleBookmark) ||
      DropDirectoryItem(:final appleBookmark) => appleBookmark,
      _ => null,
    };
    var accessed = false;
    try {
      if (bookmark != null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.macOS) {
        accessed = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
        if (!accessed) throw StateError('macOS denied security-scoped access');
      }
      await read(item);
    } catch (error) {
      content[item] = ReceivedItem(error: error);
    } finally {
      if (accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark!,
          );
        } catch (error) {
          content[item] = ReceivedItem(
            bytes: content[item]?.bytes,
            children: content[item]?.children,
            error: error,
          );
        }
      }
    }
  }
  return content;
}

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Logs a [DropDoneEvent] with full recursive details of directories and files.
void logDropEvent(DropDoneEvent event, {String source = 'Unknown'}) {
  _logDropGeneric(event.location, event.files, source);
}

/// Logs a [DropDoneDetails] with full recursive details of directories and files.
void logDropDetails(DropDoneDetails details, {String source = 'Unknown'}) {
  _logDropGeneric(details.globalPosition, details.files, source);
}

void _logDropGeneric(Offset location, List<DropItem> files, String source) {
  debugPrint(
    '==================================================================',
  );
  debugPrint('🛠️ DEBUG [$source]: Drop received');
  debugPrint('📍 Location: $location');
  debugPrint('📦 Items count: ${files.length}');

  for (var i = 0; i < files.length; i++) {
    _logDropItem(files[i], 0, index: i);
  }
  debugPrint(
    '==================================================================',
  );
}

void _logDropItem(DropItem item, int depth, {int? index}) {
  final indent = '   ' * depth;
  final prefix = index != null ? '$index. ' : '- ';
  final typeIcon = item is DropItemDirectory ? '📁' : '📄';
  final typeName = item is DropItemDirectory ? 'Directory' : 'File';

  debugPrint('$indent$prefix$typeIcon $typeName: "${item.name}"');
  debugPrint('$indent    Path: ${item.path}');
  debugPrint('$indent    MIME: ${item.mimeType}');

  if (item is DropItemDirectory) {
    if (item.children.isEmpty) {
      debugPrint('$indent    (Empty Directory)');
    } else {
      for (var i = 0; i < item.children.length; i++) {
        _logDropItem(item.children[i], depth + 1, index: i);
      }
    }
  }
}

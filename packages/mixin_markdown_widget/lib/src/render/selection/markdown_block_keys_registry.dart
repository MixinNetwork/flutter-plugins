import 'package:flutter/widgets.dart';

/// Per-block state of a rendered document that outlives a single build: the
/// keys of top-level selectable blocks, the scroll controllers and viewports
/// of horizontally scrolling code blocks and tables, and image error
/// notifiers. Entries are keyed by block id.
class MarkdownBlockKeysRegistry {
  final Map<String, GlobalKey<State<StatefulWidget>>> blockKeys = {};
  final Map<String, ScrollController> tableScrollControllers = {};
  final Map<String, GlobalKey> tableViewportKeys = {};
  final Map<String, ScrollController> codeBlockScrollControllers = {};
  final Map<String, GlobalKey> codeBlockViewportKeys = {};
  final Map<String, ValueNotifier<bool>> imageErrorNotifiers = {};

  void cleanupKeys(Set<String> validIds) {
    blockKeys.removeWhere((key, _) => !validIds.contains(key));
    final staleCodeBlockIds = codeBlockScrollControllers.keys
        .where((key) => !validIds.contains(key))
        .toList(growable: false);
    for (final blockId in staleCodeBlockIds) {
      codeBlockScrollControllers.remove(blockId)?.dispose();
    }
    codeBlockViewportKeys.removeWhere((key, _) => !validIds.contains(key));
    final staleTableIds = tableScrollControllers.keys
        .where((key) => !validIds.contains(key))
        .toList(growable: false);
    for (final blockId in staleTableIds) {
      tableScrollControllers.remove(blockId)?.dispose();
    }
    tableViewportKeys.removeWhere((key, _) => !validIds.contains(key));
    final staleImageNotifierIds = imageErrorNotifiers.keys
        .where((key) => !validIds.contains(key))
        .toList(growable: false);
    for (final blockId in staleImageNotifierIds) {
      imageErrorNotifiers.remove(blockId)?.dispose();
    }
  }
}

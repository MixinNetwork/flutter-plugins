import 'package:flutter/foundation.dart';

import '../core/document.dart';

@immutable
class StreamingMarkdownState {
  const StreamingMarkdownState({
    required this.committedBlocks,
    required this.draftBlock,
    required this.buffer,
    required this.version,
  });

  const StreamingMarkdownState.empty()
      : committedBlocks = const <BlockNode>[],
        draftBlock = null,
        buffer = '',
        version = 0;

  final List<BlockNode> committedBlocks;
  final BlockNode? draftBlock;
  final String buffer;
  final int version;

  bool get hasDraft => draftBlock != null;

  List<BlockNode> get allBlocks {
    if (draftBlock == null) {
      return committedBlocks;
    }
    return <BlockNode>[...committedBlocks, draftBlock!];
  }
}

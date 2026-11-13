import 'package:flutter/foundation.dart';

import '../core/document.dart';

@immutable
class StreamingMarkdownState {
  const StreamingMarkdownState({
    required this.committedBlocks,
    required this.draftBlock,
    required this._buffer,
    required this.version,
  }) : _bufferProvider = null;

  const StreamingMarkdownState.lazyBuffer({
    required this.committedBlocks,
    required this.draftBlock,
    required String Function() this._bufferProvider,
    required this.version,
  }) : _buffer = '';

  const StreamingMarkdownState.empty()
    : committedBlocks = const <BlockNode>[],
      draftBlock = null,
      _buffer = '',
      _bufferProvider = null,
      version = 0;

  final List<BlockNode> committedBlocks;
  final BlockNode? draftBlock;
  final String _buffer;
  final String Function()? _bufferProvider;
  final int version;

  String get buffer => _bufferProvider == null ? _buffer : _bufferProvider();

  bool get hasDraft => draftBlock != null;

  List<BlockNode> get allBlocks {
    if (draftBlock == null) {
      return committedBlocks;
    }
    return <BlockNode>[...committedBlocks, draftBlock!];
  }
}

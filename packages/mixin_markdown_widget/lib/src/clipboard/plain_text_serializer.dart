import 'copy_serializer.dart';
import '../core/document.dart';
import '../selection/structured_block_selection.dart';

class MarkdownPlainTextSerializer extends MarkdownCopySerializer {
  const MarkdownPlainTextSerializer();

  String serializeBlockText(BlockNode block) {
    return StructuredBlockSelection.serializeBlockText(block);
  }

  @override
  String serialize(MarkdownDocument document) {
    final sections = <String>[];
    for (final indexedBlock in _indexBlocks(document)) {
      final section = indexedBlock.text.trimRight();
      if (section.isNotEmpty) {
        sections.add(section);
      }
    }
    return sections.join('\n\n');
  }

  DocumentSelection? createFullDocumentSelection(MarkdownDocument document) {
    final indexedBlocks = _indexBlocks(document);
    if (indexedBlocks.isEmpty) {
      return null;
    }
    final first = indexedBlocks.first;
    final last = indexedBlocks.last;
    return DocumentSelection(
      base: DocumentPosition(
        blockIndex: first.blockIndex,
        path: first.structure == null
            ? const PathInBlock(<int>[0])
            : first.structure!.startPosition(blockIndex: first.blockIndex).path,
        textOffset: 0,
      ),
      extent: DocumentPosition(
        blockIndex: last.blockIndex,
        path: last.structure == null
            ? const PathInBlock(<int>[0])
            : last.structure!.endPosition(blockIndex: last.blockIndex).path,
        textOffset: last.structure?.plainText.length ?? last.text.length,
      ),
    );
  }

  DocumentSelection? clampSelection(
    MarkdownDocument document,
    DocumentSelection selection,
  ) {
    final indexedBlocks = _indexBlocks(document);
    if (indexedBlocks.isEmpty) {
      return null;
    }
    return DocumentSelection(
      base: _clampPosition(indexedBlocks, selection.base),
      extent: _clampPosition(indexedBlocks, selection.extent),
    );
  }

  String serializeSelection(
    MarkdownDocument document,
    DocumentSelection selection,
  ) {
    return serializeRange(document, selection.normalizedRange);
  }

  String serializeRange(MarkdownDocument document, DocumentRange range) {
    final indexedBlocks = _indexBlocks(document);
    if (indexedBlocks.isEmpty) {
      return '';
    }
    final start = _clampPosition(indexedBlocks, range.start);
    final end = _clampPosition(indexedBlocks, range.end);
    final normalizedRange = start.compareTo(end) <= 0
        ? DocumentRange(start: start, end: end)
        : DocumentRange(start: end, end: start);

    final sections = <String>[];
    for (final indexedBlock in indexedBlocks) {
      if (indexedBlock.blockIndex < normalizedRange.start.blockIndex ||
          indexedBlock.blockIndex > normalizedRange.end.blockIndex) {
        continue;
      }
      final blockStart =
          indexedBlock.blockIndex == normalizedRange.start.blockIndex
              ? normalizedRange.start.textOffset
              : 0;
      final structure = indexedBlock.structure;
      final blockEnd = indexedBlock.blockIndex == normalizedRange.end.blockIndex
          ? normalizedRange.end.textOffset
          : indexedBlock.visibleTextLength;
      final section = structure != null
          ? structure.serializeDisplayedRange(
              start: blockStart,
              end: blockEnd,
            )
          : _sliceBlock(
              indexedBlock,
              start: blockStart,
              end: blockEnd,
            );
      if (section.isNotEmpty) {
        sections.add(section);
      }
    }
    return sections.join('\n\n');
  }

  List<_IndexedPlainTextBlock> _indexBlocks(MarkdownDocument document) {
    return <_IndexedPlainTextBlock>[
      for (var index = 0; index < document.blocks.length; index++)
        _indexedBlockFor(document.blocks[index], index),
    ].where((block) => block.text.isNotEmpty).toList(growable: false);
  }

  _IndexedPlainTextBlock _indexedBlockFor(BlockNode block, int blockIndex) {
    final structure = StructuredBlockSelection.forBlock(block);
    if (!structure.isEmpty) {
      return _IndexedPlainTextBlock(
        blockIndex: blockIndex,
        text: structure.serializedText,
        structure: structure,
      );
    }
    return _IndexedPlainTextBlock(
      blockIndex: blockIndex,
      text: StructuredBlockSelection.serializeBlockText(block),
      structure: null,
    );
  }

  DocumentPosition _clampPosition(
    List<_IndexedPlainTextBlock> indexedBlocks,
    DocumentPosition position,
  ) {
    final minBlockIndex = indexedBlocks.first.blockIndex;
    final maxBlockIndex = indexedBlocks.last.blockIndex;
    final targetBlockIndex = position.blockIndex < minBlockIndex
        ? minBlockIndex
        : position.blockIndex > maxBlockIndex
            ? maxBlockIndex
            : position.blockIndex;
    final block = indexedBlocks.firstWhere(
      (item) => item.blockIndex == targetBlockIndex,
      orElse: () => indexedBlocks.last,
    );
    final targetOffset = position.textOffset < 0
        ? 0
        : position.textOffset > block.visibleTextLength
            ? block.visibleTextLength
            : position.textOffset;
    final structure = block.structure;
    if (structure != null) {
      return structure.normalizePosition(
        blockIndex: block.blockIndex,
        position: DocumentPosition(
          blockIndex: block.blockIndex,
          path: position.path,
          textOffset: targetOffset,
        ),
        affinity: targetOffset == structure.plainText.length
            ? StructuredSelectionAffinity.upstream
            : StructuredSelectionAffinity.downstream,
      );
    }
    return DocumentPosition(
      blockIndex: block.blockIndex,
      path: const PathInBlock(<int>[0]),
      textOffset: targetOffset,
    );
  }

  String _sliceBlock(
    _IndexedPlainTextBlock block, {
    required int start,
    required int end,
  }) {
    final lower = start < 0
        ? 0
        : start > block.text.length
            ? block.text.length
            : start;
    final upper = end < 0
        ? 0
        : end > block.text.length
            ? block.text.length
            : end;
    if (lower >= upper) {
      return '';
    }
    return block.text.substring(lower, upper);
  }
}

class _IndexedPlainTextBlock {
  const _IndexedPlainTextBlock({
    required this.blockIndex,
    required this.text,
    required this.structure,
  });

  final int blockIndex;
  final String text;
  final StructuredBlockSelection? structure;

  int get visibleTextLength => structure?.plainText.length ?? text.length;
}

import 'copy_serializer.dart';
import '../core/document.dart';
import '../selection/structured_block_selection.dart';

/// Serializes markdown documents and selections as plain text.
///
/// This is also the single source for selection bounds: the selection
/// controller clamps and selects all through [clampSelection] and
/// [createFullDocumentSelection], so a subclass changes both copy output and
/// selection bounds consistently. Block text comes from the cached
/// [StructuredBlockSelection] of each block.
class MarkdownPlainTextSerializer extends MarkdownCopySerializer {
  const MarkdownPlainTextSerializer();

  String serializeBlockText(BlockNode block) {
    return StructuredBlockSelection.serializeBlockText(block);
  }

  @override
  String serialize(MarkdownDocument document) {
    final sections = <String>[];
    for (var index = 0; index < document.blocks.length; index++) {
      final section = _indexedBlockAt(document, index).text.trimRight();
      if (section.isNotEmpty) {
        sections.add(section);
      }
    }
    return sections.join('\n\n');
  }

  DocumentSelection? createFullDocumentSelection(MarkdownDocument document) {
    final bounds = _boundsOf(document);
    if (bounds == null) {
      return null;
    }
    final (first, last) = bounds;
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
        textOffset: last.visibleTextLength,
      ),
    );
  }

  DocumentSelection? clampSelection(
    MarkdownDocument document,
    DocumentSelection selection,
  ) {
    final bounds = _boundsOf(document);
    if (bounds == null) {
      return null;
    }
    return DocumentSelection(
      base: _clampPosition(document, bounds, selection.base),
      extent: _clampPosition(document, bounds, selection.extent),
    );
  }

  String serializeSelection(
    MarkdownDocument document,
    DocumentSelection selection,
  ) {
    return serializeRange(document, selection.normalizedRange);
  }

  String serializeRange(MarkdownDocument document, DocumentRange range) {
    final bounds = _boundsOf(document);
    if (bounds == null) {
      return '';
    }
    final start = _clampPosition(document, bounds, range.start);
    final end = _clampPosition(document, bounds, range.end);
    final normalizedRange = start.compareTo(end) <= 0
        ? DocumentRange(start: start, end: end)
        : DocumentRange(start: end, end: start);

    final sections = <String>[];
    for (var blockIndex = normalizedRange.start.blockIndex;
        blockIndex <= normalizedRange.end.blockIndex;
        blockIndex++) {
      final indexedBlock = _indexedBlockAt(document, blockIndex);
      if (indexedBlock.text.isEmpty) {
        continue;
      }
      final blockStart = blockIndex == normalizedRange.start.blockIndex
          ? normalizedRange.start.textOffset
          : 0;
      final blockEnd = blockIndex == normalizedRange.end.blockIndex
          ? normalizedRange.end.textOffset
          : indexedBlock.visibleTextLength;
      final structure = indexedBlock.structure;
      final section = structure != null
          ? structure.serializeDisplayedRange(start: blockStart, end: blockEnd)
          : _sliceBlock(indexedBlock, start: blockStart, end: blockEnd);
      if (section.isNotEmpty) {
        sections.add(section);
      }
    }
    return sections.join('\n\n');
  }

  _IndexedPlainTextBlock _indexedBlockAt(
    MarkdownDocument document,
    int blockIndex,
  ) {
    final block = document.blocks[blockIndex];
    final structure = StructuredBlockSelection.forBlock(block);
    return _IndexedPlainTextBlock(
      blockIndex: blockIndex,
      text: StructuredBlockSelection.serializeBlockText(block),
      structure: structure.isEmpty ? null : structure,
    );
  }

  /// The first and last blocks that have text, or null when none has.
  (_IndexedPlainTextBlock, _IndexedPlainTextBlock)? _boundsOf(
    MarkdownDocument document,
  ) {
    _IndexedPlainTextBlock? first;
    for (var index = 0; index < document.blocks.length; index++) {
      final block = _indexedBlockAt(document, index);
      if (block.text.isNotEmpty) {
        first = block;
        break;
      }
    }
    if (first == null) {
      return null;
    }
    for (var index = document.blocks.length - 1;
        index > first.blockIndex;
        index--) {
      final block = _indexedBlockAt(document, index);
      if (block.text.isNotEmpty) {
        return (first, block);
      }
    }
    return (first, first);
  }

  DocumentPosition _clampPosition(
    MarkdownDocument document,
    (_IndexedPlainTextBlock, _IndexedPlainTextBlock) bounds,
    DocumentPosition position,
  ) {
    final (first, last) = bounds;
    final targetBlockIndex = position.blockIndex < first.blockIndex
        ? first.blockIndex
        : position.blockIndex > last.blockIndex
            ? last.blockIndex
            : position.blockIndex;
    final candidate = _indexedBlockAt(document, targetBlockIndex);
    final block = candidate.text.isEmpty ? last : candidate;
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

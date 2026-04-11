import 'copy_serializer.dart';
import '../core/document.dart';

class MarkdownPlainTextSerializer extends MarkdownCopySerializer {
  const MarkdownPlainTextSerializer();

  String serializeBlockText(BlockNode block) {
    return _serializeBlock(block, indentLevel: 0);
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
        path: const PathInBlock(<int>[0]),
        textOffset: 0,
      ),
      extent: DocumentPosition(
        blockIndex: last.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: last.text.length,
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

  TableCellSelection? clampTableCellSelection(
    MarkdownDocument document,
    TableCellSelection selection,
  ) {
    if (selection.blockIndex < 0 ||
        selection.blockIndex >= document.blocks.length) {
      return null;
    }
    final block = document.blocks[selection.blockIndex];
    if (block is! TableBlock || block.rows.isEmpty) {
      return null;
    }
    final maxRow = block.rows.length - 1;
    final maxColumn = block.rows.fold<int>(
          0,
          (current, row) =>
              row.cells.length > current ? row.cells.length : current,
        ) -
        1;
    if (maxColumn < 0) {
      return null;
    }

    TableCellPosition clamp(TableCellPosition position) {
      final row = position.rowIndex < 0
          ? 0
          : position.rowIndex > maxRow
              ? maxRow
              : position.rowIndex;
      final column = position.columnIndex < 0
          ? 0
          : position.columnIndex > maxColumn
              ? maxColumn
              : position.columnIndex;
      return TableCellPosition(rowIndex: row, columnIndex: column);
    }

    return TableCellSelection(
      blockIndex: selection.blockIndex,
      base: clamp(selection.base),
      extent: clamp(selection.extent),
    );
  }

  String serializeTableCellSelection(
    MarkdownDocument document,
    TableCellSelection selection,
  ) {
    final clamped = clampTableCellSelection(document, selection);
    if (clamped == null) {
      return '';
    }
    final block = document.blocks[clamped.blockIndex] as TableBlock;
    final range = clamped.normalizedRange;
    final rows = <String>[];
    for (var rowIndex = range.start.rowIndex;
        rowIndex <= range.end.rowIndex;
        rowIndex++) {
      final row = block.rows[rowIndex];
      final cells = <String>[];
      for (var columnIndex = range.start.columnIndex;
          columnIndex <= range.end.columnIndex;
          columnIndex++) {
        if (columnIndex < row.cells.length) {
          cells.add(_flattenInlines(row.cells[columnIndex].inlines));
        } else {
          cells.add('');
        }
      }
      rows.add(cells.join('\t'));
    }
    return rows.join('\n');
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
      final section = _sliceBlock(
        indexedBlock,
        start: indexedBlock.blockIndex == normalizedRange.start.blockIndex
            ? normalizedRange.start.textOffset
            : 0,
        end: indexedBlock.blockIndex == normalizedRange.end.blockIndex
            ? normalizedRange.end.textOffset
            : indexedBlock.text.length,
      );
      if (section.isNotEmpty) {
        sections.add(section);
      }
    }
    return sections.join('\n\n');
  }

  String _serializeBlock(BlockNode block, {required int indentLevel}) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return _flattenInlines((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return _flattenInlines((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.quote:
        return _serializeQuote(block as QuoteBlock, indentLevel: indentLevel);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _serializeList(block as ListBlock, indentLevel: indentLevel);
      case MarkdownBlockKind.codeBlock:
        return _trimTrailingNewlines((block as CodeBlock).code);
      case MarkdownBlockKind.table:
        return _serializeTable(block as TableBlock);
      case MarkdownBlockKind.image:
        return _serializeImage(block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return '---';
    }
  }

  String _serializeQuote(QuoteBlock block, {required int indentLevel}) {
    final inner = block.children
        .map((child) => _serializeBlock(child, indentLevel: indentLevel))
        .where((value) => value.trim().isNotEmpty)
        .join('\n\n');
    if (inner.isEmpty) {
      return '';
    }
    return inner
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
  }

  String _serializeList(ListBlock block, {required int indentLevel}) {
    final items = <String>[];
    for (var index = 0; index < block.items.length; index++) {
      final marker = block.ordered ? '${block.startIndex + index}.' : '-';
      final content = _serializeListItem(
        block.items[index],
        indentLevel: indentLevel + 1,
      );
      if (content.isEmpty) {
        continue;
      }
      final prefix = '${'  ' * indentLevel}$marker ';
      final continuation = '${'  ' * indentLevel}${' ' * (marker.length + 1)}';
      items.add(_prefixMultiline(content, prefix, continuation));
    }
    return items.join('\n');
  }

  String _serializeListItem(ListItemNode item, {required int indentLevel}) {
    final sections = <String>[];
    for (final child in item.children) {
      final text = _serializeBlock(child, indentLevel: indentLevel);
      if (text.trim().isEmpty) {
        continue;
      }
      sections.add(text);
    }
    return sections.join('\n');
  }

  String _serializeTable(TableBlock block) {
    return block.rows
        .map(
          (row) =>
              row.cells.map((cell) => _flattenInlines(cell.inlines)).join('\t'),
        )
        .join('\n');
  }

  String _serializeImage(ImageBlock block) {
    final label = block.alt?.trim().isNotEmpty == true
        ? block.alt!.trim()
        : block.title?.trim().isNotEmpty == true
            ? block.title!.trim()
            : block.url;
    return label;
  }

  String _flattenInlines(List<InlineNode> inlines) {
    final buffer = StringBuffer();
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.text:
          buffer.write((inline as TextInline).text);
          break;
        case MarkdownInlineKind.emphasis:
          buffer.write(_flattenInlines((inline as EmphasisInline).children));
          break;
        case MarkdownInlineKind.strong:
          buffer.write(_flattenInlines((inline as StrongInline).children));
          break;
        case MarkdownInlineKind.strikethrough:
          buffer.write(
            _flattenInlines((inline as StrikethroughInline).children),
          );
          break;
        case MarkdownInlineKind.link:
          final link = inline as LinkInline;
          final label = _flattenInlines(link.children).trim();
          if (link.destination.isEmpty) {
            buffer.write(label);
          } else if (label.isEmpty || label == link.destination) {
            buffer.write(link.destination);
          } else {
            buffer.write('$label (${link.destination})');
          }
          break;
        case MarkdownInlineKind.inlineCode:
          buffer.write((inline as InlineCode).text);
          break;
        case MarkdownInlineKind.softBreak:
        case MarkdownInlineKind.hardBreak:
          buffer.write('\n');
          break;
        case MarkdownInlineKind.image:
          final image = inline as InlineImage;
          buffer.write(image.alt ?? image.url);
          break;
      }
    }
    return buffer.toString();
  }

  String _prefixMultiline(
    String input,
    String firstPrefix,
    String continuationPrefix,
  ) {
    final lines = input.split('\n');
    if (lines.isEmpty) {
      return firstPrefix.trimRight();
    }
    return <String>[
      '$firstPrefix${lines.first}',
      for (final line in lines.skip(1))
        line.isEmpty
            ? continuationPrefix.trimRight()
            : '$continuationPrefix$line',
    ].join('\n');
  }

  String _trimTrailingNewlines(String value) {
    return value.replaceFirst(RegExp(r'\n+$'), '');
  }

  List<_IndexedPlainTextBlock> _indexBlocks(MarkdownDocument document) {
    return <_IndexedPlainTextBlock>[
      for (var index = 0; index < document.blocks.length; index++)
        _IndexedPlainTextBlock(
          blockIndex: index,
          text: _serializeBlock(document.blocks[index], indentLevel: 0),
        ),
    ].where((block) => block.text.isNotEmpty).toList(growable: false);
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
        : position.textOffset > block.text.length
            ? block.text.length
            : position.textOffset;
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
  });

  final int blockIndex;
  final String text;
}

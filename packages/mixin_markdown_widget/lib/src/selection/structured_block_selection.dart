import 'package:flutter/foundation.dart';

import '../core/document.dart';

enum StructuredSelectionAffinity {
  upstream,
  downstream,
}

@immutable
class StructuredBlockSelectionLeaf {
  const StructuredBlockSelectionLeaf._({
    required this.path,
    required this.leadingText,
    required this.firstLinePrefix,
    required this.continuationPrefix,
    required this.visibleText,
    required this.exportText,
    required this.segmentStart,
  });

  final PathInBlock path;
  final String leadingText;
  final String firstLinePrefix;
  final String continuationPrefix;
  final String visibleText;
  final String exportText;
  final int segmentStart;

  String get renderedText =>
      '$leadingText${_renderPrefixedText(visibleText, firstLinePrefix, continuationPrefix)}';

  String get serializedText =>
      '$leadingText${_renderPrefixedText(exportText, firstLinePrefix, continuationPrefix)}';

  int get segmentEnd => segmentStart + renderedText.length;

  int displayedOffsetForLocalOffset(int localOffset) {
    final clampedOffset = localOffset.clamp(0, visibleText.length).toInt();
    var renderedOffset =
        segmentStart + leadingText.length + firstLinePrefix.length;
    for (var index = 0; index < clampedOffset; index++) {
      renderedOffset += 1;
      if (visibleText.codeUnitAt(index) == 0x0A) {
        renderedOffset += continuationPrefix.length;
      }
    }
    return renderedOffset;
  }

  int localOffsetForDisplayedOffset(int displayedOffset) {
    final clampedDisplayed =
        displayedOffset.clamp(segmentStart, segmentEnd).toInt();
    var relative = clampedDisplayed - segmentStart;
    if (relative <= leadingText.length + firstLinePrefix.length) {
      return 0;
    }

    relative -= leadingText.length + firstLinePrefix.length;
    var localOffset = 0;
    while (localOffset < visibleText.length && relative > 0) {
      relative -= 1;
      localOffset += 1;
      if (relative <= 0) {
        break;
      }
      if (visibleText.codeUnitAt(localOffset - 1) == 0x0A) {
        if (relative <= continuationPrefix.length) {
          return localOffset;
        }
        relative -= continuationPrefix.length;
      }
    }
    return localOffset.clamp(0, visibleText.length).toInt();
  }
}

@immutable
class StructuredBlockSelection {
  const StructuredBlockSelection._({
    required this.plainText,
    required this.serializedText,
    required this.leaves,
  });

  factory StructuredBlockSelection.forBlock(BlockNode block) {
    return StructuredBlockSelection._fromBlueprints(
      _StructuredBlockSelectionBuilder().build(block),
    );
  }

  static String serializeBlockText(BlockNode block) {
    final structure = StructuredBlockSelection.forBlock(block);
    if (!structure.isEmpty) {
      return structure.serializedText;
    }
    return _StructuredBlockSelectionBuilder().exportBlockText(block);
  }

  factory StructuredBlockSelection._fromBlueprints(
    List<_LeafBlueprint> blueprints,
  ) {
    final leaves = <StructuredBlockSelectionLeaf>[];
    final visibleBuffer = StringBuffer();
    final serializedBuffer = StringBuffer();
    var segmentStart = 0;
    for (final blueprint in blueprints) {
      final leaf = StructuredBlockSelectionLeaf._(
        path: blueprint.path,
        leadingText: blueprint.leadingText,
        firstLinePrefix: blueprint.firstLinePrefix,
        continuationPrefix: blueprint.continuationPrefix,
        visibleText: blueprint.visibleText,
        exportText: blueprint.exportText,
        segmentStart: segmentStart,
      );
      leaves.add(leaf);
      visibleBuffer.write(leaf.renderedText);
      serializedBuffer.write(leaf.serializedText);
      segmentStart = visibleBuffer.length;
    }
    return StructuredBlockSelection._(
      plainText: visibleBuffer.toString(),
      serializedText: serializedBuffer.toString(),
      leaves: List<StructuredBlockSelectionLeaf>.unmodifiable(leaves),
    );
  }

  final String plainText;
  final String serializedText;
  final List<StructuredBlockSelectionLeaf> leaves;

  bool get isEmpty => leaves.isEmpty;

  StructuredBlockSelectionLeaf? leafForPath(PathInBlock path) {
    for (final leaf in leaves) {
      if (leaf.path == path) {
        return leaf;
      }
    }
    return null;
  }

  DocumentPosition startPosition({required int blockIndex}) {
    if (leaves.isEmpty) {
      return DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: 0,
      );
    }
    return DocumentPosition(
      blockIndex: blockIndex,
      path: leaves.first.path,
      textOffset: 0,
    );
  }

  DocumentPosition endPosition({required int blockIndex}) {
    if (leaves.isEmpty) {
      return DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: plainText.length,
      );
    }
    return DocumentPosition(
      blockIndex: blockIndex,
      path: leaves.last.path,
      textOffset: plainText.length,
    );
  }

  DocumentPosition normalizePosition({
    required int blockIndex,
    required DocumentPosition position,
    StructuredSelectionAffinity affinity =
        StructuredSelectionAffinity.downstream,
  }) {
    final clampedOffset =
        position.textOffset.clamp(0, plainText.length).toInt();
    final leaf = leafForPath(position.path);
    if (leaf != null &&
        clampedOffset >= leaf.segmentStart &&
        clampedOffset <= leaf.segmentEnd) {
      return DocumentPosition(
        blockIndex: blockIndex,
        path: leaf.path,
        textOffset: clampedOffset,
      );
    }
    return positionForDisplayedOffset(
      blockIndex: blockIndex,
      displayedOffset: clampedOffset,
      affinity: affinity,
    );
  }

  DocumentPosition positionForDisplayedOffset({
    required int blockIndex,
    required int displayedOffset,
    StructuredSelectionAffinity affinity =
        StructuredSelectionAffinity.downstream,
  }) {
    final clampedOffset = displayedOffset.clamp(0, plainText.length).toInt();
    if (leaves.isEmpty) {
      return DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: clampedOffset,
      );
    }

    for (var index = 0; index < leaves.length; index++) {
      final leaf = leaves[index];
      final isLastLeaf = index == leaves.length - 1;
      if (clampedOffset < leaf.segmentEnd ||
          (isLastLeaf && clampedOffset == plainText.length)) {
        if (clampedOffset == leaf.segmentStart &&
            affinity == StructuredSelectionAffinity.upstream &&
            index > 0) {
          return DocumentPosition(
            blockIndex: blockIndex,
            path: leaves[index - 1].path,
            textOffset: clampedOffset,
          );
        }
        return DocumentPosition(
          blockIndex: blockIndex,
          path: leaf.path,
          textOffset: clampedOffset,
        );
      }
    }

    return DocumentPosition(
      blockIndex: blockIndex,
      path: leaves.last.path,
      textOffset: plainText.length,
    );
  }

  DocumentRange rangeForDisplayedOffsets({
    required int blockIndex,
    required int startOffset,
    required int endOffset,
  }) {
    return DocumentRange(
      start: positionForDisplayedOffset(
        blockIndex: blockIndex,
        displayedOffset: startOffset,
        affinity: StructuredSelectionAffinity.downstream,
      ),
      end: positionForDisplayedOffset(
        blockIndex: blockIndex,
        displayedOffset: endOffset,
        affinity: StructuredSelectionAffinity.upstream,
      ),
    );
  }

  DocumentRange? wordRangeForPosition({
    required int blockIndex,
    required DocumentPosition position,
    required bool Function(String character) isWordCharacter,
  }) {
    final leaf = leafForPath(position.path) ??
        _leafContainingOffset(position.textOffset);
    if (leaf == null || leaf.visibleText.isEmpty) {
      return null;
    }

    var localOffset = leaf.localOffsetForDisplayedOffset(position.textOffset);
    if (localOffset > 0 &&
        localOffset == leaf.visibleText.length &&
        !isWordCharacter(leaf.visibleText[localOffset - 1])) {
      localOffset -= 1;
    }

    var start = localOffset.clamp(0, leaf.visibleText.length).toInt();
    var end = start;

    while (start > 0 && isWordCharacter(leaf.visibleText[start - 1])) {
      start -= 1;
    }
    while (end < leaf.visibleText.length &&
        isWordCharacter(leaf.visibleText[end])) {
      end += 1;
    }

    if (start == end && leaf.visibleText.isNotEmpty) {
      if (end < leaf.visibleText.length) {
        end += 1;
      } else if (start > 0) {
        start -= 1;
      }
    }

    return DocumentRange(
      start: DocumentPosition(
        blockIndex: blockIndex,
        path: leaf.path,
        textOffset: leaf.displayedOffsetForLocalOffset(start),
      ),
      end: DocumentPosition(
        blockIndex: blockIndex,
        path: leaf.path,
        textOffset: leaf.displayedOffsetForLocalOffset(end),
      ),
    );
  }

  StructuredBlockSelectionLeaf? _leafContainingOffset(int displayedOffset) {
    final clampedOffset = displayedOffset.clamp(0, plainText.length).toInt();
    for (final leaf in leaves) {
      if (clampedOffset >= leaf.segmentStart &&
          clampedOffset <= leaf.segmentEnd) {
        return leaf;
      }
    }
    return leaves.isEmpty ? null : leaves.last;
  }

  String serializeDisplayedRange({
    required int start,
    required int end,
  }) {
    final lower = start < 0
        ? 0
        : start > plainText.length
            ? plainText.length
            : start;
    final upper = end < 0
        ? 0
        : end > plainText.length
            ? plainText.length
            : end;
    if (lower >= upper || leaves.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (final leaf in leaves) {
      if (upper <= leaf.segmentStart) {
        break;
      }
      if (lower >= leaf.segmentEnd) {
        continue;
      }

      final localStart =
          lower <= leaf.segmentStart ? 0 : lower - leaf.segmentStart;
      final localEnd = upper >= leaf.segmentEnd
          ? leaf.renderedText.length
          : upper - leaf.segmentStart;
      if (localStart == 0 && localEnd == leaf.renderedText.length) {
        buffer.write(leaf.serializedText);
      } else {
        buffer.write(leaf.renderedText.substring(localStart, localEnd));
      }
    }
    return buffer.toString();
  }
}

@immutable
class _LeafBlueprint {
  const _LeafBlueprint({
    required this.path,
    required this.leadingText,
    required this.firstLinePrefix,
    required this.continuationPrefix,
    required this.visibleText,
    required this.exportText,
  });

  final PathInBlock path;
  final String leadingText;
  final String firstLinePrefix;
  final String continuationPrefix;
  final String visibleText;
  final String exportText;

  _LeafBlueprint copyWith({
    String? leadingText,
  }) {
    return _LeafBlueprint(
      path: path,
      leadingText: leadingText ?? this.leadingText,
      firstLinePrefix: firstLinePrefix,
      continuationPrefix: continuationPrefix,
      visibleText: visibleText,
      exportText: exportText,
    );
  }
}

class _StructuredBlockSelectionBuilder {
  String exportBlockText(BlockNode block) {
    return _exportBlockText(block);
  }

  List<_LeafBlueprint> build(BlockNode block) {
    return _buildBlock(
      block,
      pathPrefix: const <int>[],
      firstLinePrefix: '',
      continuationPrefix: '',
      listIndentLevel: 0,
    );
  }

  List<_LeafBlueprint> _buildBlock(
    BlockNode block, {
    required List<int> pathPrefix,
    required String firstLinePrefix,
    required String continuationPrefix,
    required int listIndentLevel,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        final visibleText = _visibleLeafText(block);
        final exportText = _exportLeafText(block);
        if (visibleText.isEmpty) {
          return const <_LeafBlueprint>[];
        }
        return <_LeafBlueprint>[
          _LeafBlueprint(
            path: PathInBlock(pathPrefix.isEmpty ? const <int>[0] : pathPrefix),
            leadingText: '',
            firstLinePrefix: firstLinePrefix,
            continuationPrefix: continuationPrefix,
            visibleText: visibleText,
            exportText: exportText,
          ),
        ];
      case MarkdownBlockKind.quote:
        final quote = block as QuoteBlock;
        final leaves = <_LeafBlueprint>[];
        for (var index = 0; index < quote.children.length; index++) {
          final childLeaves = _buildBlock(
            quote.children[index],
            pathPrefix: <int>[...pathPrefix, index],
            firstLinePrefix:
                leaves.isEmpty ? firstLinePrefix : continuationPrefix,
            continuationPrefix: continuationPrefix,
            listIndentLevel: listIndentLevel,
          );
          if (childLeaves.isEmpty) {
            continue;
          }
          if (leaves.isNotEmpty) {
            _prependLeadingText(childLeaves, '\n\n');
          }
          leaves.addAll(childLeaves);
        }
        return leaves;
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _buildList(
          block as ListBlock,
          pathPrefix: pathPrefix,
          firstLinePrefix: firstLinePrefix,
          continuationPrefix: continuationPrefix,
          listIndentLevel: listIndentLevel,
        );
      case MarkdownBlockKind.footnoteList:
        return _buildList(
          _footnoteListAsOrderedList(block as FootnoteListBlock),
          pathPrefix: pathPrefix,
          firstLinePrefix: firstLinePrefix,
          continuationPrefix: continuationPrefix,
          listIndentLevel: listIndentLevel,
        );
      case MarkdownBlockKind.table:
        return _buildTable(
          block as TableBlock,
          pathPrefix: pathPrefix,
          firstLinePrefix: firstLinePrefix,
          continuationPrefix: continuationPrefix,
          listIndentLevel: listIndentLevel,
        );
    }
  }

  List<_LeafBlueprint> _buildList(
    ListBlock block, {
    required List<int> pathPrefix,
    required String firstLinePrefix,
    required String continuationPrefix,
    required int listIndentLevel,
  }) {
    final leaves = <_LeafBlueprint>[];
    for (var itemIndex = 0; itemIndex < block.items.length; itemIndex++) {
      final item = block.items[itemIndex];
      final markerText = _listItemMarkerText(
        block,
        itemIndex,
        indentLevel: listIndentLevel,
      );
      final itemLeaves = <_LeafBlueprint>[];
      var hasContent = false;

      for (var childIndex = 0;
          childIndex < item.children.length;
          childIndex++) {
        final childLeaves = _buildBlock(
          item.children[childIndex],
          pathPrefix: <int>[...pathPrefix, itemIndex, childIndex + 1],
          firstLinePrefix:
              hasContent ? continuationPrefix + ' ' * markerText.length : '',
          continuationPrefix: continuationPrefix + ' ' * markerText.length,
          listIndentLevel:
              item.children[childIndex].kind == MarkdownBlockKind.orderedList ||
                      item.children[childIndex].kind ==
                          MarkdownBlockKind.unorderedList ||
                      item.children[childIndex].kind ==
                          MarkdownBlockKind.footnoteList
                  ? listIndentLevel + 1
                  : listIndentLevel,
        );
        if (childLeaves.isEmpty) {
          continue;
        }
        if (hasContent) {
          _prependLeadingText(childLeaves, '\n');
        }
        itemLeaves.addAll(childLeaves);
        hasContent = true;
      }

      if (!hasContent && item.taskState == null) {
        continue;
      }

      itemLeaves.insert(
        0,
        _LeafBlueprint(
          path: PathInBlock(<int>[...pathPrefix, itemIndex, 0]),
          leadingText: '',
          firstLinePrefix:
              leaves.isEmpty ? firstLinePrefix : continuationPrefix,
          continuationPrefix: continuationPrefix,
          visibleText: hasContent ? markerText : markerText.trimRight(),
          exportText: hasContent ? markerText : markerText.trimRight(),
        ),
      );

      if (leaves.isNotEmpty) {
        _prependLeadingText(itemLeaves, '\n');
      }
      leaves.addAll(itemLeaves);
    }
    return leaves;
  }

  List<_LeafBlueprint> _buildTable(
    TableBlock block, {
    required List<int> pathPrefix,
    required String firstLinePrefix,
    required String continuationPrefix,
    required int listIndentLevel,
  }) {
    final leaves = <_LeafBlueprint>[];
    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
      final row = block.rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.cells.length; columnIndex++) {
        final visibleText =
            _flattenVisibleInlines(row.cells[columnIndex].inlines);
        if (visibleText.isEmpty) {
          continue;
        }
        final leadingText = rowIndex == 0 && columnIndex == 0
            ? ''
            : columnIndex == 0
                ? '\n'
                : '\t';
        leaves.add(
          _LeafBlueprint(
            path: PathInBlock(<int>[...pathPrefix, rowIndex, columnIndex]),
            leadingText: leadingText,
            firstLinePrefix: columnIndex == 0
                ? (rowIndex == 0 ? firstLinePrefix : continuationPrefix)
                : '',
            continuationPrefix: continuationPrefix,
            visibleText: visibleText,
            exportText: _flattenExportInlines(row.cells[columnIndex].inlines),
          ),
        );
      }
    }
    return leaves;
  }

  String _visibleLeafText(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return _flattenVisibleInlines((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return _flattenVisibleInlines((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.definitionList:
        return _visibleDefinitionListText(block as DefinitionListBlock);
      case MarkdownBlockKind.codeBlock:
        return (block as CodeBlock).code;
      case MarkdownBlockKind.image:
        return _imageCaptionText(block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return '---';
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.table:
        return '';
    }
  }

  String _exportLeafText(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return _flattenExportInlines((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return _flattenExportInlines((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.definitionList:
        return _exportDefinitionListText(block as DefinitionListBlock);
      case MarkdownBlockKind.codeBlock:
        return (block as CodeBlock).code;
      case MarkdownBlockKind.image:
        return _exportImageText(block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return '---';
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.table:
        return '';
    }
  }

  String _visibleDefinitionListText(DefinitionListBlock block) {
    final items = <String>[];
    for (final item in block.items) {
      final term = _flattenVisibleInlines(item.term).trimRight();
      final definitions = <String>[];
      for (final definition in item.definitions) {
        final text = definition
            .map(_visibleBlockText)
            .where((value) => value.trim().isNotEmpty)
            .join('\n\n');
        if (text.isNotEmpty) {
          definitions.add(_prefixMultiline(text, ': ', '  '));
        }
      }
      final sections = <String>[];
      if (term.isNotEmpty) {
        sections.add(term);
      }
      sections.addAll(definitions);
      final serialized = sections.join('\n');
      if (serialized.isNotEmpty) {
        items.add(serialized);
      }
    }
    return items.join('\n');
  }

  String _visibleBlockText(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return _flattenVisibleInlines((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return _flattenVisibleInlines((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.quote:
        return (block as QuoteBlock)
            .children
            .map(_visibleBlockText)
            .where((value) => value.trim().isNotEmpty)
            .join('\n\n');
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _visibleListText(block as ListBlock);
      case MarkdownBlockKind.definitionList:
        return _visibleDefinitionListText(block as DefinitionListBlock);
      case MarkdownBlockKind.footnoteList:
        return _visibleListText(
            _footnoteListAsOrderedList(block as FootnoteListBlock));
      case MarkdownBlockKind.codeBlock:
        return (block as CodeBlock).code;
      case MarkdownBlockKind.table:
        return (block as TableBlock)
            .rows
            .map((row) => row.cells
                .map((cell) => _flattenVisibleInlines(cell.inlines))
                .join('\t'))
            .join('\n');
      case MarkdownBlockKind.image:
        return _imageCaptionText(block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return '---';
    }
  }

  String _exportDefinitionListText(DefinitionListBlock block) {
    final items = <String>[];
    for (final item in block.items) {
      final term = _flattenExportInlines(item.term).trimRight();
      final definitions = <String>[];
      for (final definition in item.definitions) {
        final text = definition
            .map(_exportBlockText)
            .where((value) => value.trim().isNotEmpty)
            .join('\n\n');
        if (text.isNotEmpty) {
          definitions.add(_prefixMultiline(text, ': ', '  '));
        }
      }
      final sections = <String>[];
      if (term.isNotEmpty) {
        sections.add(term);
      }
      sections.addAll(definitions);
      final serialized = sections.join('\n');
      if (serialized.isNotEmpty) {
        items.add(serialized);
      }
    }
    return items.join('\n');
  }

  String _exportBlockText(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        return _flattenExportInlines((block as HeadingBlock).inlines);
      case MarkdownBlockKind.paragraph:
        return _flattenExportInlines((block as ParagraphBlock).inlines);
      case MarkdownBlockKind.quote:
        return (block as QuoteBlock)
            .children
            .map(_exportBlockText)
            .where((value) => value.trim().isNotEmpty)
            .join('\n\n');
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return _exportListText(block as ListBlock);
      case MarkdownBlockKind.definitionList:
        return _exportDefinitionListText(block as DefinitionListBlock);
      case MarkdownBlockKind.footnoteList:
        return _exportListText(
            _footnoteListAsOrderedList(block as FootnoteListBlock));
      case MarkdownBlockKind.codeBlock:
        return (block as CodeBlock).code;
      case MarkdownBlockKind.table:
        return (block as TableBlock)
            .rows
            .map((row) => row.cells
                .map((cell) => _flattenExportInlines(cell.inlines))
                .join('\t'))
            .join('\n');
      case MarkdownBlockKind.image:
        return _exportImageText(block as ImageBlock);
      case MarkdownBlockKind.thematicBreak:
        return '---';
    }
  }

  String _visibleListText(ListBlock block) {
    final items = <String>[];
    for (var index = 0; index < block.items.length; index++) {
      final item = block.items[index];
      final markerText = _listItemMarkerText(
        block,
        index,
        indentLevel: 0,
      );
      final content = item.children
          .map(_visibleBlockText)
          .where((value) => value.trim().isNotEmpty)
          .join('\n');
      if (content.isEmpty && item.taskState == null) {
        continue;
      }
      if (content.isEmpty) {
        items.add(markerText.trimRight());
        continue;
      }
      items.add(
        _prefixMultiline(content, markerText, ' ' * markerText.length),
      );
    }
    return items.join('\n');
  }

  String _exportListText(ListBlock block) {
    final items = <String>[];
    for (var index = 0; index < block.items.length; index++) {
      final item = block.items[index];
      final markerText = _listItemMarkerText(
        block,
        index,
        indentLevel: 0,
      );
      final content = item.children
          .map(_exportBlockText)
          .where((value) => value.trim().isNotEmpty)
          .join('\n');
      if (content.isEmpty && item.taskState == null) {
        continue;
      }
      if (content.isEmpty) {
        items.add(markerText.trimRight());
        continue;
      }
      items.add(
        _prefixMultiline(content, markerText, ' ' * markerText.length),
      );
    }
    return items.join('\n');
  }

  String _flattenVisibleInlines(List<InlineNode> inlines) {
    final buffer = StringBuffer();
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.text:
          buffer.write((inline as TextInline).text);
          break;
        case MarkdownInlineKind.emphasis:
          buffer.write(
              _flattenVisibleInlines((inline as EmphasisInline).children));
          break;
        case MarkdownInlineKind.strong:
          buffer
              .write(_flattenVisibleInlines((inline as StrongInline).children));
          break;
        case MarkdownInlineKind.strikethrough:
          buffer.write(
              _flattenVisibleInlines((inline as StrikethroughInline).children));
          break;
        case MarkdownInlineKind.highlight:
          buffer.write(
              _flattenVisibleInlines((inline as HighlightInline).children));
          break;
        case MarkdownInlineKind.subscript:
          buffer.write(
              _flattenVisibleInlines((inline as SubscriptInline).children));
          break;
        case MarkdownInlineKind.superscript:
          buffer.write(
              _flattenVisibleInlines((inline as SuperscriptInline).children));
          break;
        case MarkdownInlineKind.link:
          buffer.write(_flattenVisibleInlines((inline as LinkInline).children));
          break;
        case MarkdownInlineKind.math:
          buffer.write((inline as MathInline).tex);
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

  String _flattenExportInlines(List<InlineNode> inlines) {
    final buffer = StringBuffer();
    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.text:
          buffer.write((inline as TextInline).text);
          break;
        case MarkdownInlineKind.emphasis:
          buffer.write(
              _flattenExportInlines((inline as EmphasisInline).children));
          break;
        case MarkdownInlineKind.strong:
          buffer
              .write(_flattenExportInlines((inline as StrongInline).children));
          break;
        case MarkdownInlineKind.strikethrough:
          buffer.write(
              _flattenExportInlines((inline as StrikethroughInline).children));
          break;
        case MarkdownInlineKind.highlight:
          buffer.write(
              _flattenExportInlines((inline as HighlightInline).children));
          break;
        case MarkdownInlineKind.subscript:
          buffer.write(
              _flattenExportInlines((inline as SubscriptInline).children));
          break;
        case MarkdownInlineKind.superscript:
          buffer.write(
              _flattenExportInlines((inline as SuperscriptInline).children));
          break;
        case MarkdownInlineKind.link:
          final link = inline as LinkInline;
          final label = _flattenExportInlines(link.children).trim();
          if (link.destination.isEmpty) {
            buffer.write(label);
          } else if (label.isEmpty || label == link.destination) {
            buffer.write(link.destination);
          } else {
            buffer.write('$label (${link.destination})');
          }
          break;
        case MarkdownInlineKind.math:
          buffer.write((inline as MathInline).tex);
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

  String _listItemMarkerText(
    ListBlock block,
    int index, {
    required int indentLevel,
  }) {
    final item = block.items[index];
    final marker = block.ordered ? '${block.startIndex + index}.' : '-';
    final checkbox = switch (item.taskState) {
      MarkdownTaskListItemState.checked => ' [x]',
      MarkdownTaskListItemState.unchecked => ' [ ]',
      null => '',
    };
    return '${'  ' * indentLevel}$marker$checkbox ';
  }

  String _imageCaptionText(ImageBlock block) {
    return (block.alt ?? block.title ?? '').trim();
  }

  String _exportImageText(ImageBlock block) {
    final label = block.alt?.trim().isNotEmpty == true
        ? block.alt!.trim()
        : block.title?.trim().isNotEmpty == true
            ? block.title!.trim()
            : block.url;
    return label;
  }

  ListBlock _footnoteListAsOrderedList(FootnoteListBlock block) {
    return ListBlock(
      id: block.id,
      ordered: true,
      startIndex: 1,
      items: block.items,
      sourceRange: block.sourceRange,
    );
  }
}

void _prependLeadingText(List<_LeafBlueprint> leaves, String leadingText) {
  if (leaves.isEmpty || leadingText.isEmpty) {
    return;
  }
  leaves[0] = leaves[0].copyWith(
    leadingText: '$leadingText${leaves[0].leadingText}',
  );
}

String _renderPrefixedText(
  String text,
  String firstLinePrefix,
  String continuationPrefix,
) {
  if (text.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  var wrotePrefix = false;
  for (var index = 0; index < text.length; index++) {
    if (!wrotePrefix) {
      buffer.write(firstLinePrefix);
      wrotePrefix = true;
    }
    final char = text[index];
    buffer.write(char);
    if (char == '\n' && index < text.length - 1) {
      buffer.write(continuationPrefix);
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

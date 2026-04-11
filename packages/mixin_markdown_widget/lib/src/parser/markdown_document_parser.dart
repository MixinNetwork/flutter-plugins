import 'dart:collection';

import 'package:markdown/markdown.dart' as md;

import '../core/document.dart';
import 'markdown_syntaxes.dart';

class MarkdownDocumentParser {
  const MarkdownDocumentParser();

  static final Expando<Map<MarkdownBlockKind, int>> _documentKindCounts =
      Expando<Map<MarkdownBlockKind, int>>('markdownDocumentKindCounts');

  MarkdownDocument parse(String source, {int version = 0}) {
    final normalizedSource = _normalizeSource(source);
    return _parseDocument(
      normalizedSource,
      version: version,
      sourceOffset: 0,
      initialKindCounts: const <MarkdownBlockKind, int>{},
    );
  }

  MarkdownDocument parseAppending(
    String source, {
    required MarkdownDocument previousDocument,
    int version = 0,
    bool assumeAppended = false,
  }) {
    final normalizedSource = _normalizeSource(source);
    return _parseAppendingNormalizedSource(
      normalizedSource,
      previousDocument: previousDocument,
      version: version,
      assumeAppended: assumeAppended,
    );
  }

  MarkdownDocument parseAppendingChunk(
    String chunk, {
    required MarkdownDocument previousDocument,
    int version = 0,
  }) {
    final normalizedChunk = _normalizeSource(chunk);
    final normalizedSource = '${previousDocument.sourceText}$normalizedChunk';
    return _parseAppendingNormalizedSource(
      normalizedSource,
      previousDocument: previousDocument,
      version: version,
      assumeAppended: true,
    );
  }

  MarkdownDocument _parseAppendingNormalizedSource(
    String normalizedSource, {
    required MarkdownDocument previousDocument,
    required int version,
    required bool assumeAppended,
  }) {
    if (previousDocument.blocks.isEmpty ||
        previousDocument.sourceText.isEmpty) {
      return parse(normalizedSource, version: version);
    }
    if (!assumeAppended &&
        !normalizedSource.startsWith(previousDocument.sourceText)) {
      return parse(normalizedSource, version: version);
    }

    final lastRange = previousDocument.blocks.last.sourceRange;
    if (lastRange == null ||
        lastRange.start < 0 ||
        lastRange.start > previousDocument.sourceText.length) {
      return parse(normalizedSource, version: version);
    }

    final prefixLength = previousDocument.blocks.length - 1;
    final prefixBlocks = prefixLength == 0
        ? const <BlockNode>[]
        : _BlockListPrefixView(previousDocument.blocks, prefixLength);
    if (prefixBlocks.isNotEmpty) {
      final prefixTailRange = prefixBlocks.last.sourceRange;
      if (prefixTailRange == null || prefixTailRange.end > lastRange.start) {
        return parse(normalizedSource, version: version);
      }
    }

    final initialKindCounts = _subtractBlockKinds(
      _kindCountsForDocument(previousDocument),
      previousDocument.blocks.last,
    );
    if (prefixLength > 0 && initialKindCounts.isEmpty) {
      return parse(normalizedSource, version: version);
    }

    final tailDocument = _parseDocument(
      normalizedSource.substring(lastRange.start),
      version: version,
      sourceOffset: lastRange.start,
      initialKindCounts: initialKindCounts,
    );

    final document = MarkdownDocument(
      blocks: _ConcatenatedBlockList(prefixBlocks, tailDocument.blocks),
      sourceText: normalizedSource,
      version: version,
    );
    _documentKindCounts[document] = _kindCountsForDocument(tailDocument);
    return document;
  }

  MarkdownDocument _parseDocument(
    String normalizedSource, {
    required int version,
    required int sourceOffset,
    required Map<MarkdownBlockKind, int> initialKindCounts,
  }) {
    final document = md.Document(
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: buildMarkdownBlockSyntaxes(),
      inlineSyntaxes: buildMarkdownInlineSyntaxes(),
      encodeHtml: false,
    );
    final nodes = document.parseLines(normalizedSource.split('\n'));
    final builder = _MarkdownAstBuilder(initialKindCounts: initialKindCounts);
    var blocks = builder.buildBlocks(nodes);
    final ranges = _scanTopLevelBlockRanges(
      normalizedSource,
      sourceOffset: sourceOffset,
    );
    if (ranges.length == blocks.length) {
      blocks = List<BlockNode>.generate(
        blocks.length,
        (index) => _withSourceRange(blocks[index], ranges[index]),
        growable: false,
      );
    }

    final parsedDocument = MarkdownDocument(
      blocks: List<BlockNode>.unmodifiable(blocks),
      sourceText: normalizedSource,
      version: version,
    );
    _documentKindCounts[parsedDocument] = builder.kindCounts;
    return parsedDocument;
  }

  String _normalizeSource(String source) {
    return source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  Map<MarkdownBlockKind, int> _countBlockKinds(List<BlockNode> blocks) {
    final counts = <MarkdownBlockKind, int>{};
    for (final block in blocks) {
      _countBlockKindsInBlock(block, counts);
    }
    return counts;
  }

  Map<MarkdownBlockKind, int> _kindCountsForDocument(
    MarkdownDocument document,
  ) {
    final cached = _documentKindCounts[document];
    if (cached != null) {
      return cached;
    }
    final counts = _countBlockKinds(document.blocks);
    _documentKindCounts[document] = counts;
    return counts;
  }

  Map<MarkdownBlockKind, int> _subtractBlockKinds(
    Map<MarkdownBlockKind, int> counts,
    BlockNode block,
  ) {
    final remaining = <MarkdownBlockKind, int>{...counts};
    final removed = <MarkdownBlockKind, int>{};
    _countBlockKindsInBlock(block, removed);
    for (final entry in removed.entries) {
      final nextCount = (remaining[entry.key] ?? 0) - entry.value;
      if (nextCount > 0) {
        remaining[entry.key] = nextCount;
      } else {
        remaining.remove(entry.key);
      }
    }
    return remaining;
  }

  void _countBlockKindsInBlock(
    BlockNode block,
    Map<MarkdownBlockKind, int> counts,
  ) {
    counts[block.kind] = (counts[block.kind] ?? 0) + 1;

    if (block is QuoteBlock) {
      for (final child in block.children) {
        _countBlockKindsInBlock(child, counts);
      }
      return;
    }

    if (block is ListBlock) {
      for (final item in block.items) {
        for (final child in item.children) {
          _countBlockKindsInBlock(child, counts);
        }
      }
      return;
    }

    if (block is FootnoteListBlock) {
      for (final item in block.items) {
        for (final child in item.children) {
          _countBlockKindsInBlock(child, counts);
        }
      }
      return;
    }

    if (block is DefinitionListBlock) {
      for (final item in block.items) {
        for (final definition in item.definitions) {
          for (final child in definition) {
            _countBlockKindsInBlock(child, counts);
          }
        }
      }
    }
  }

  BlockNode _withSourceRange(BlockNode block, SourceRange sourceRange) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return HeadingBlock(
          id: heading.id,
          level: heading.level,
          inlines: heading.inlines,
          anchorId: heading.anchorId,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return ParagraphBlock(
          id: paragraph.id,
          inlines: paragraph.inlines,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.quote:
        final quote = block as QuoteBlock;
        return QuoteBlock(
          id: quote.id,
          children: quote.children,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        final list = block as ListBlock;
        return ListBlock(
          id: list.id,
          ordered: list.ordered,
          items: list.items,
          startIndex: list.startIndex,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.definitionList:
        final definitionList = block as DefinitionListBlock;
        return DefinitionListBlock(
          id: definitionList.id,
          items: definitionList.items,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.footnoteList:
        final footnoteList = block as FootnoteListBlock;
        return FootnoteListBlock(
          id: footnoteList.id,
          items: footnoteList.items,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        return CodeBlock(
          id: codeBlock.id,
          code: codeBlock.code,
          language: codeBlock.language,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.table:
        final table = block as TableBlock;
        return TableBlock(
          id: table.id,
          alignments: table.alignments,
          rows: table.rows,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.image:
        final image = block as ImageBlock;
        return ImageBlock(
          id: image.id,
          url: image.url,
          alt: image.alt,
          title: image.title,
          sourceRange: sourceRange,
        );
      case MarkdownBlockKind.thematicBreak:
        final thematicBreak = block as ThematicBreakBlock;
        return ThematicBreakBlock(
          id: thematicBreak.id,
          sourceRange: sourceRange,
        );
    }
  }

  List<SourceRange> _scanTopLevelBlockRanges(
    String source, {
    required int sourceOffset,
  }) {
    if (source.isEmpty) {
      return const <SourceRange>[];
    }

    final lines = source.split('\n');
    final lineStarts = <int>[];
    var offset = 0;
    for (final line in lines) {
      lineStarts.add(offset);
      offset += line.length + 1;
    }

    final ranges = <SourceRange>[];
    var index = 0;
    while (index < lines.length) {
      if (_isBlankLine(lines[index])) {
        index += 1;
        continue;
      }

      final startIndex = index;
      final endIndex = _consumeBlock(lines, index);
      ranges.add(
        SourceRange(
          start: sourceOffset + lineStarts[startIndex],
          end: sourceOffset + _lineEndOffset(lines, lineStarts, endIndex),
        ),
      );
      index = endIndex + 1;
    }

    return ranges;
  }

  int _consumeBlock(List<String> lines, int startIndex) {
    final line = lines[startIndex];

    if (_isIndentedCodeBlockStart(line)) {
      return _consumeIndentedCodeBlock(lines, startIndex);
    }
    if (_isFenceStart(line)) {
      return _consumeFencedCodeBlock(lines, startIndex);
    }
    if (_isTableStart(lines, startIndex)) {
      return _consumeTable(lines, startIndex);
    }
    if (_isDefinitionListStart(lines, startIndex)) {
      return _consumeDefinitionList(lines, startIndex);
    }
    if (_isBlockquoteLine(line)) {
      return _consumeBlockquote(lines, startIndex);
    }
    if (_isListMarker(line)) {
      return _consumeList(lines, startIndex);
    }
    if (_isAtxHeading(line) || _isThematicBreak(line)) {
      return startIndex;
    }

    return _consumeParagraph(lines, startIndex);
  }

  int _consumeIndentedCodeBlock(List<String> lines, int startIndex) {
    var endIndex = startIndex;
    while (endIndex + 1 < lines.length) {
      final nextLine = lines[endIndex + 1];
      if (_isBlankLine(nextLine) || _isIndentedCodeBlockStart(nextLine)) {
        endIndex += 1;
        continue;
      }
      break;
    }
    return endIndex;
  }

  int _consumeFencedCodeBlock(List<String> lines, int startIndex) {
    final match = _fenceStartPattern.firstMatch(lines[startIndex]);
    if (match == null) {
      return startIndex;
    }
    final fence = match.group(1)!;
    for (var index = startIndex + 1; index < lines.length; index++) {
      if (_isFenceEnd(lines[index], fence)) {
        return index;
      }
    }
    return lines.length - 1;
  }

  int _consumeTable(List<String> lines, int startIndex) {
    var endIndex = startIndex + 1;
    while (endIndex + 1 < lines.length &&
        !_isBlankLine(lines[endIndex + 1]) &&
        _looksLikeTableRow(lines[endIndex + 1])) {
      endIndex += 1;
    }
    return endIndex;
  }

  int _consumeBlockquote(List<String> lines, int startIndex) {
    var endIndex = startIndex;
    while (endIndex + 1 < lines.length) {
      final nextIndex = endIndex + 1;
      final nextLine = lines[nextIndex];
      if (_isBlockquoteLine(nextLine)) {
        endIndex = nextIndex;
        continue;
      }
      if (_isBlankLine(nextLine) &&
          nextIndex + 1 < lines.length &&
          _isBlockquoteLine(lines[nextIndex + 1])) {
        endIndex = nextIndex + 1;
        continue;
      }
      break;
    }
    return endIndex;
  }

  int _consumeList(List<String> lines, int startIndex) {
    var endIndex = startIndex;
    while (endIndex + 1 < lines.length) {
      final nextIndex = endIndex + 1;
      final nextLine = lines[nextIndex];
      if (_isBlankLine(nextLine)) {
        final continuationIndex = nextIndex + 1;
        if (continuationIndex < lines.length &&
            _isListContinuationLine(lines[continuationIndex])) {
          endIndex = continuationIndex;
          continue;
        }
        break;
      }
      if (_isListContinuationLine(nextLine)) {
        endIndex = nextIndex;
        continue;
      }
      break;
    }
    return endIndex;
  }

  int _consumeParagraph(List<String> lines, int startIndex) {
    var endIndex = startIndex;
    while (endIndex + 1 < lines.length) {
      final nextIndex = endIndex + 1;
      if (_isBlankLine(lines[nextIndex])) {
        break;
      }
      if (endIndex == startIndex && _isSetextUnderline(lines[nextIndex])) {
        endIndex = nextIndex;
        break;
      }
      if (_startsNewTopLevelBlock(lines, nextIndex)) {
        break;
      }
      endIndex = nextIndex;
    }
    return endIndex;
  }

  int _consumeDefinitionList(List<String> lines, int startIndex) {
    var endIndex = startIndex + 1;
    while (endIndex + 1 < lines.length) {
      final nextIndex = endIndex + 1;
      final nextLine = lines[nextIndex];
      if (_isDefinitionMarker(nextLine) ||
          _isDefinitionContinuationLine(nextLine)) {
        endIndex = nextIndex;
        continue;
      }
      if (_isBlankLine(nextLine)) {
        final continuationIndex = nextIndex + 1;
        if (continuationIndex < lines.length &&
            _isDefinitionContinuationLine(lines[continuationIndex])) {
          endIndex = continuationIndex;
          continue;
        }
        break;
      }
      if (_isDefinitionListStart(lines, nextIndex)) {
        endIndex = nextIndex + 1;
        continue;
      }
      if (!_startsNewTopLevelBlock(lines, nextIndex)) {
        endIndex = nextIndex;
        continue;
      }
      break;
    }
    return endIndex;
  }

  bool _startsNewTopLevelBlock(List<String> lines, int index) {
    final line = lines[index];
    return _isIndentedCodeBlockStart(line) ||
        _isFenceStart(line) ||
        _isTableStart(lines, index) ||
        _isDefinitionListStart(lines, index) ||
        _isBlockquoteLine(line) ||
        _isListMarker(line) ||
        _isAtxHeading(line) ||
        _isThematicBreak(line);
  }

  bool _isBlankLine(String line) => line.trim().isEmpty;

  bool _isFenceStart(String line) => _fenceStartPattern.hasMatch(line);

  bool _isIndentedCodeBlockStart(String line) {
    return !_isBlankLine(line) && _leadingIndent(line) >= 4;
  }

  bool _isFenceEnd(String line, String fence) {
    final marker = fence[0];
    final minimumLength = fence.length;
    final pattern = RegExp(
      '^\\s{0,3}${RegExp.escape(marker)}{$minimumLength,}\\s*' r'$',
    );
    return pattern.hasMatch(line);
  }

  bool _isAtxHeading(String line) => _atxHeadingPattern.hasMatch(line);

  bool _isSetextUnderline(String line) =>
      _setextUnderlinePattern.hasMatch(line);

  bool _isThematicBreak(String line) => _thematicBreakPattern.hasMatch(line);

  bool _isBlockquoteLine(String line) => _blockquotePattern.hasMatch(line);

  bool _isListMarker(String line) => _listMarkerPattern.hasMatch(line);

  bool _isListContinuationLine(String line) {
    if (_isListMarker(line)) {
      return true;
    }
    return _leadingIndent(line) >= 2 ||
        _isBlockquoteLine(line) ||
        _isFenceStart(line) ||
        _isIndentedCodeBlockStart(line);
  }

  bool _isTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    return _looksLikeTableRow(lines[index]) &&
        _tableSeparatorPattern.hasMatch(lines[index + 1]);
  }

  bool _isDefinitionListStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    final term = lines[index];
    if (_isBlankLine(term) || _leadingIndent(term) > 3) {
      return false;
    }
    return _definitionMarkerPattern.hasMatch(lines[index + 1]);
  }

  bool _isDefinitionMarker(String line) {
    return _definitionMarkerPattern.hasMatch(line);
  }

  bool _isDefinitionContinuationLine(String line) {
    return _definitionContinuationPattern.hasMatch(line);
  }

  bool _looksLikeTableRow(String line) {
    final trimmed = line.trim();
    return trimmed.isNotEmpty && trimmed.contains('|');
  }

  int _leadingIndent(String line) {
    var indent = 0;
    while (indent < line.length && line.codeUnitAt(indent) == 0x20) {
      indent += 1;
    }
    return indent;
  }

  int _lineEndOffset(
    List<String> lines,
    List<int> lineStarts,
    int lineIndex,
  ) {
    final contentEnd = lineStarts[lineIndex] + lines[lineIndex].length;
    if (lineIndex < lines.length - 1) {
      return contentEnd + 1;
    }
    return contentEnd;
  }

  static final RegExp _fenceStartPattern = RegExp(r'^\s{0,3}([`~]{3,}).*$');
  static final RegExp _atxHeadingPattern = RegExp(r'^\s{0,3}#{1,6}(?:\s+|$)');
  static final RegExp _setextUnderlinePattern =
      RegExp(r'^\s{0,3}(?:=+|-+)\s*$');
  static final RegExp _blockquotePattern = RegExp(r'^\s{0,3}>\s?.*$');
  static final RegExp _listMarkerPattern =
      RegExp(r'^\s{0,3}(?:[-+*]|\d+[.)])\s+');
  static final RegExp _definitionMarkerPattern = RegExp(r'^\s{0,3}:\s?.*$');
  static final RegExp _definitionContinuationPattern =
      RegExp(r'^(?: {2,}|\t).*$');
  static final RegExp _tableSeparatorPattern = RegExp(
    r'^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$',
  );
  static final RegExp _thematicBreakPattern = RegExp(
    r'^\s{0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})\s*$',
  );
}

class _MarkdownAstBuilder {
  _MarkdownAstBuilder({Map<MarkdownBlockKind, int>? initialKindCounts})
      : _kindCounters = <MarkdownBlockKind, int>{
          ...?initialKindCounts,
        };

  final Map<MarkdownBlockKind, int> _kindCounters;

  Map<MarkdownBlockKind, int> get kindCounts =>
      Map<MarkdownBlockKind, int>.unmodifiable(_kindCounters);

  List<BlockNode> buildBlocks(List<md.Node> nodes) {
    final blocks = <BlockNode>[];
    for (final node in nodes) {
      final block = _buildBlock(node);
      if (block != null) {
        blocks.add(block);
      }
    }
    return blocks;
  }

  BlockNode? _buildBlock(md.Node node) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isEmpty) {
        return null;
      }
      return ParagraphBlock(
        id: _nextId(MarkdownBlockKind.paragraph, text),
        inlines: <InlineNode>[TextInline(text: text)],
      );
    }

    if (node is! md.Element) {
      return null;
    }

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return HeadingBlock(
          id: _nextId(MarkdownBlockKind.heading, node.textContent),
          level: int.parse(node.tag.substring(1)),
          inlines: _buildInlines(node.children),
          anchorId: node.generatedId,
        );
      case 'p':
        final imageBlock = _buildStandaloneImageParagraph(node);
        if (imageBlock != null) {
          return imageBlock;
        }
        return ParagraphBlock(
          id: _nextId(MarkdownBlockKind.paragraph, node.textContent),
          inlines: _buildInlines(node.children),
        );
      case 'blockquote':
        return QuoteBlock(
          id: _nextId(MarkdownBlockKind.quote, node.textContent),
          children: List<BlockNode>.unmodifiable(
              buildBlocks(node.children ?? const <md.Node>[])),
        );
      case 'ul':
        return ListBlock(
          id: _nextId(MarkdownBlockKind.unorderedList, node.textContent),
          ordered: false,
          items: List<ListItemNode>.unmodifiable(_buildListItems(node)),
        );
      case 'ol':
        return ListBlock(
          id: _nextId(MarkdownBlockKind.orderedList, node.textContent),
          ordered: true,
          startIndex: int.tryParse(node.attributes['start'] ?? '1') ?? 1,
          items: List<ListItemNode>.unmodifiable(_buildListItems(node)),
        );
      case 'dl':
        return _buildDefinitionList(node);
      case 'section':
        if (node.attributes['class'] == 'footnotes') {
          return _buildFootnoteList(node);
        }
        break;
      case 'pre':
        return _buildCodeBlock(node);
      case 'table':
        return _buildTable(node);
      case 'img':
        return ImageBlock(
          id: _nextId(MarkdownBlockKind.image,
              node.attributes['src'] ?? node.attributes['alt'] ?? ''),
          url: node.attributes['src'] ?? '',
          alt: node.attributes['alt'],
          title: node.attributes['title'],
        );
      case 'hr':
        return ThematicBreakBlock(
          id: _nextId(MarkdownBlockKind.thematicBreak, 'hr'),
        );
      default:
        final fallbackInlines = _buildInlines(node.children);
        if (fallbackInlines.isEmpty) {
          return null;
        }
        return ParagraphBlock(
          id: _nextId(MarkdownBlockKind.paragraph, node.textContent),
          inlines: fallbackInlines,
        );
    }

    return null;
  }

  List<ListItemNode> _buildListItems(md.Element listElement) {
    final items = <ListItemNode>[];
    for (final child in listElement.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'li') {
        continue;
      }
      items.add(_buildListItem(child));
    }
    return items;
  }

  ListItemNode _buildListItem(md.Element itemElement) {
    final taskState = _taskStateForListItem(itemElement);
    final contentNodes = _stripLeadingCheckbox(itemElement.children);
    final children = _buildContainerBlocks(contentNodes);
    return ListItemNode(
      taskState: taskState,
      children: List<BlockNode>.unmodifiable(children),
    );
  }

  List<BlockNode> _buildContainerBlocks(List<md.Node>? nodes) {
    final blocks = <BlockNode>[];
    final inlineBuffer = <md.Node>[];

    void flushInlineBuffer() {
      if (inlineBuffer.isEmpty) {
        return;
      }
      final bufferedNodes = List<md.Node>.unmodifiable(inlineBuffer);
      inlineBuffer.clear();
      final inlineChildren = _buildInlines(bufferedNodes);
      if (inlineChildren.isEmpty) {
        return;
      }
      blocks.add(
        ParagraphBlock(
          id: _nextId(
            MarkdownBlockKind.paragraph,
            bufferedNodes.map((node) => node.textContent).join(),
          ),
          inlines: List<InlineNode>.unmodifiable(inlineChildren),
        ),
      );
    }

    for (final node in nodes ?? const <md.Node>[]) {
      if (_isContainerBlockNode(node)) {
        flushInlineBuffer();
        final block = _buildBlock(node);
        if (block != null) {
          blocks.add(block);
        }
        continue;
      }
      inlineBuffer.add(node);
    }

    flushInlineBuffer();
    return blocks;
  }

  bool _isContainerBlockNode(md.Node node) {
    if (node is! md.Element) {
      return false;
    }
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'p':
      case 'blockquote':
      case 'ul':
      case 'ol':
      case 'dl':
      case 'pre':
      case 'table':
      case 'hr':
        return true;
      case 'section':
        return node.attributes['class'] == 'footnotes';
      default:
        return false;
    }
  }

  MarkdownTaskListItemState? _taskStateForListItem(md.Element itemElement) {
    final checkbox = _leadingCheckboxElement(itemElement.children);
    if (checkbox == null) {
      return null;
    }
    return checkbox.attributes['checked'] == 'true'
        ? MarkdownTaskListItemState.checked
        : MarkdownTaskListItemState.unchecked;
  }

  md.Element? _leadingCheckboxElement(List<md.Node>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return null;
    }
    final first = nodes.first;
    if (_isCheckboxInput(first)) {
      return first as md.Element;
    }
    if (first is md.Element && first.tag == 'p') {
      final paragraphChildren = first.children;
      if (paragraphChildren != null &&
          paragraphChildren.isNotEmpty &&
          _isCheckboxInput(paragraphChildren.first)) {
        return paragraphChildren.first as md.Element;
      }
    }
    return null;
  }

  bool _isCheckboxInput(md.Node node) {
    return node is md.Element &&
        node.tag == 'input' &&
        node.attributes['type'] == 'checkbox';
  }

  List<md.Node> _stripLeadingCheckbox(List<md.Node>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return const <md.Node>[];
    }

    final first = nodes.first;
    if (_isCheckboxInput(first)) {
      return List<md.Node>.unmodifiable(nodes.skip(1));
    }

    if (first is md.Element && first.tag == 'p') {
      final paragraphChildren = first.children ?? const <md.Node>[];
      if (paragraphChildren.isNotEmpty &&
          _isCheckboxInput(paragraphChildren.first)) {
        final paragraph = md.Element('p', paragraphChildren.skip(1).toList())
          ..attributes.addAll(first.attributes);
        return List<md.Node>.unmodifiable(
            <md.Node>[paragraph, ...nodes.skip(1)]);
      }
    }

    return List<md.Node>.unmodifiable(nodes);
  }

  DefinitionListBlock _buildDefinitionList(md.Element node) {
    final items = <DefinitionListItemNode>[];
    final children = node.children ?? const <md.Node>[];
    var index = 0;
    while (index < children.length) {
      final child = children[index];
      if (child is! md.Element || child.tag != 'dt') {
        index += 1;
        continue;
      }

      final terms = <List<InlineNode>>[];
      while (index < children.length) {
        final termNode = children[index];
        if (termNode is! md.Element || termNode.tag != 'dt') {
          break;
        }
        terms.add(
            List<InlineNode>.unmodifiable(_buildInlines(termNode.children)));
        index += 1;
      }

      final definitions = <List<BlockNode>>[];
      while (index < children.length) {
        final definitionNode = children[index];
        if (definitionNode is! md.Element || definitionNode.tag != 'dd') {
          break;
        }
        final blocks = _buildContainerBlocks(definitionNode.children);
        if (blocks.isNotEmpty) {
          definitions.add(List<BlockNode>.unmodifiable(blocks));
        }
        index += 1;
      }

      if (definitions.isEmpty) {
        continue;
      }

      for (final term in terms) {
        items.add(
          DefinitionListItemNode(
            term: term,
            definitions: List<List<BlockNode>>.unmodifiable(definitions),
          ),
        );
      }
    }

    return DefinitionListBlock(
      id: _nextId(MarkdownBlockKind.definitionList, node.textContent),
      items: List<DefinitionListItemNode>.unmodifiable(items),
    );
  }

  FootnoteListBlock _buildFootnoteList(md.Element node) {
    final orderedList = node.children?.firstWhere(
      (child) => child is md.Element && child.tag == 'ol',
      orElse: () => md.Element('ol', const <md.Node>[]),
    );

    final items = <ListItemNode>[];
    if (orderedList is md.Element) {
      for (final child in orderedList.children ?? const <md.Node>[]) {
        if (child is md.Element && child.tag == 'li') {
          items.add(_buildListItem(child));
        }
      }
    }

    return FootnoteListBlock(
      id: _nextId(MarkdownBlockKind.footnoteList, node.textContent),
      items: List<ListItemNode>.unmodifiable(items),
    );
  }

  CodeBlock _buildCodeBlock(md.Element node) {
    final codeElement = node.children != null && node.children!.isNotEmpty
        ? node.children!.firstWhere(
            (child) => child is md.Element && child.tag == 'code',
            orElse: () => node,
          )
        : node;
    final languageClass =
        codeElement is md.Element ? codeElement.attributes['class'] : null;
    final language =
        languageClass != null && languageClass.startsWith('language-')
            ? languageClass.substring('language-'.length)
            : null;
    return CodeBlock(
      id: _nextId(MarkdownBlockKind.codeBlock, node.textContent),
      code: codeElement is md.Element
          ? codeElement.textContent
          : node.textContent,
      language: language,
    );
  }

  ImageBlock? _buildStandaloneImageParagraph(md.Element node) {
    final children = node.children;
    if (children == null || children.length != 1) {
      return null;
    }
    final child = children.single;
    if (child is! md.Element || child.tag != 'img') {
      return null;
    }
    return ImageBlock(
      id: _nextId(
        MarkdownBlockKind.image,
        child.attributes['src'] ?? child.attributes['alt'] ?? '',
      ),
      url: child.attributes['src'] ?? '',
      alt: child.attributes['alt'],
      title: child.attributes['title'],
    );
  }

  TableBlock _buildTable(md.Element node) {
    final rows = <TableRowNode>[];
    final alignments = <MarkdownTableColumnAlignment>[];

    void appendRow(md.Element rowElement, {required bool headerSection}) {
      final cells = <TableCellNode>[];
      for (final child in rowElement.children ?? const <md.Node>[]) {
        if (child is! md.Element) {
          continue;
        }
        if (child.tag != 'th' && child.tag != 'td') {
          continue;
        }
        if (alignments.length < cells.length + 1) {
          alignments.add(_parseAlignment(child.attributes['align']));
        }
        cells.add(TableCellNode(
            inlines:
                List<InlineNode>.unmodifiable(_buildInlines(child.children))));
      }
      if (cells.isNotEmpty) {
        rows.add(TableRowNode(
            cells: List<TableCellNode>.unmodifiable(cells),
            isHeader: headerSection));
      }
    }

    for (final sectionNode in node.children ?? const <md.Node>[]) {
      if (sectionNode is! md.Element) {
        continue;
      }
      if (sectionNode.tag == 'thead' || sectionNode.tag == 'tbody') {
        final headerSection = sectionNode.tag == 'thead';
        for (final rowNode in sectionNode.children ?? const <md.Node>[]) {
          if (rowNode is md.Element && rowNode.tag == 'tr') {
            appendRow(rowNode, headerSection: headerSection);
          }
        }
        continue;
      }
      if (sectionNode.tag == 'tr') {
        appendRow(sectionNode, headerSection: rows.isEmpty);
      }
    }

    return TableBlock(
      id: _nextId(MarkdownBlockKind.table, node.textContent),
      alignments: List<MarkdownTableColumnAlignment>.unmodifiable(alignments),
      rows: List<TableRowNode>.unmodifiable(rows),
    );
  }

  List<InlineNode> _buildInlines(List<md.Node>? nodes) {
    final inlines = <InlineNode>[];
    for (final node in nodes ?? const <md.Node>[]) {
      if (node is md.Text) {
        if (node.text.isNotEmpty) {
          inlines.add(TextInline(text: node.text));
        }
        continue;
      }
      if (node is! md.Element) {
        continue;
      }
      switch (node.tag) {
        case 'em':
          inlines.add(EmphasisInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'strong':
          inlines.add(StrongInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'del':
          inlines.add(StrikethroughInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'mark':
          inlines.add(HighlightInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'sub':
          inlines.add(SubscriptInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'sup':
          inlines.add(SuperscriptInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'a':
          inlines.add(
            LinkInline(
              destination: node.attributes['href'] ?? '',
              title: node.attributes['title'],
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children)),
            ),
          );
          break;
        case 'code':
          inlines.add(InlineCode(text: node.textContent));
          break;
        case 'br':
          inlines.add(const HardBreakInline());
          break;
        case 'img':
          inlines.add(InlineImage(
              url: node.attributes['src'] ?? '', alt: node.attributes['alt']));
          break;
        default:
          final children = _buildInlines(node.children);
          if (children.isEmpty && node.textContent.isNotEmpty) {
            inlines.add(TextInline(text: node.textContent));
          } else {
            inlines.addAll(children);
          }
          break;
      }
    }
    return inlines;
  }

  MarkdownTableColumnAlignment _parseAlignment(String? raw) {
    switch (raw) {
      case 'left':
        return MarkdownTableColumnAlignment.left;
      case 'center':
        return MarkdownTableColumnAlignment.center;
      case 'right':
        return MarkdownTableColumnAlignment.right;
      default:
        return MarkdownTableColumnAlignment.none;
    }
  }

  String _nextId(MarkdownBlockKind kind, String signature) {
    final nextCount = (_kindCounters[kind] ?? 0) + 1;
    _kindCounters[kind] = nextCount;
    return '${kind.name}-$nextCount-${_stableHash(signature)}';
  }

  int _stableHash(String value) {
    const int fnvPrime = 16777619;
    int hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0x7fffffff;
    }
    return hash;
  }
}

class _BlockListPrefixView extends ListBase<BlockNode> {
  _BlockListPrefixView(this._source, this.length);

  final List<BlockNode> _source;
  @override
  final int length;

  @override
  set length(int newLength) {
    throw UnsupportedError('Cannot modify block prefix view length.');
  }

  @override
  BlockNode operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    return _source[index];
  }

  @override
  void operator []=(int index, BlockNode value) {
    throw UnsupportedError('Cannot modify block prefix view contents.');
  }
}

class _ConcatenatedBlockList extends ListBase<BlockNode> {
  _ConcatenatedBlockList(this._prefix, this._tail);

  final List<BlockNode> _prefix;
  final List<BlockNode> _tail;

  @override
  int get length => _prefix.length + _tail.length;

  @override
  set length(int newLength) {
    throw UnsupportedError('Cannot modify concatenated block list length.');
  }

  @override
  BlockNode operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    if (index < _prefix.length) {
      return _prefix[index];
    }
    return _tail[index - _prefix.length];
  }

  @override
  void operator []=(int index, BlockNode value) {
    throw UnsupportedError('Cannot modify concatenated block list contents.');
  }
}

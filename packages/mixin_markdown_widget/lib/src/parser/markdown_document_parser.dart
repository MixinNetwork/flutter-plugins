import 'dart:collection';

import 'package:markdown/markdown.dart' as md;

import '../core/document.dart';
import 'markdown_syntaxes.dart';

class MarkdownParserTiming {
  const MarkdownParserTiming({
    required this.totalMicros,
    required this.markdownParseLinesMicros,
    required this.buildBlocksMicros,
    required this.scanRangesMicros,
    required this.applyRangesMicros,
    required this.normalizeInlineMicros,
    required this.nextIdMicros,
    required this.parseLineCount,
  });

  final int totalMicros;
  final int markdownParseLinesMicros;
  final int buildBlocksMicros;
  final int scanRangesMicros;
  final int applyRangesMicros;
  final int normalizeInlineMicros;
  final int nextIdMicros;
  final int parseLineCount;
}

class MarkdownDocumentParser {
  const MarkdownDocumentParser({this.onTiming});

  final void Function(MarkdownParserTiming timing)? onTiming;

  static final Expando<Map<MarkdownBlockKind, int>> _documentKindCounts =
      Expando<Map<MarkdownBlockKind, int>>('markdownDocumentKindCounts');

  MarkdownDocument parse(String source, {int version = 0}) {
    final lines = _splitNormalizedLines(_normalizeSource(source));
    return parseLines(lines, version: version);
  }

  MarkdownDocument parseLines(List<String> lines, {int version = 0}) {
    return _parseDocument(
      lines,
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
    return parse(source, version: version);
  }

  MarkdownDocument parseAppendingChunk(
    List<String> sourceLines, {
    required MarkdownDocument previousDocument,
    required List<String> appendedLines,
    required List<String> previousTailLines,
    required int previousSourceLength,
    required bool previousSourceEndsWithNewline,
    required bool previousSourceEndsWithBlankLine,
    int version = 0,
  }) {
    return _parseAppendingLines(
      sourceLines,
      previousDocument: previousDocument,
      appendedLines: appendedLines,
      previousTailLines: previousTailLines,
      previousSourceLength: previousSourceLength,
      previousSourceEndsWithNewline: previousSourceEndsWithNewline,
      previousSourceEndsWithBlankLine: previousSourceEndsWithBlankLine,
      version: version,
    );
  }

  MarkdownDocument _parseAppendingLines(
    List<String> sourceLines, {
    required MarkdownDocument previousDocument,
    required List<String> appendedLines,
    required List<String> previousTailLines,
    required int previousSourceLength,
    required bool previousSourceEndsWithNewline,
    required bool previousSourceEndsWithBlankLine,
    required int version,
  }) {
    if (previousDocument.blocks.isEmpty || previousSourceLength == 0) {
      return parseLines(sourceLines, version: version);
    }
    if (_linesSourceLength(appendedLines) == 0) {
      final document = MarkdownDocument(
        blocks: previousDocument.blocks,
        version: version,
      );
      _documentKindCounts[document] = _kindCountsForDocument(previousDocument);
      return document;
    }

    final lastRange = previousDocument.blocks.last.sourceRange;
    if (lastRange == null ||
        lastRange.start < 0 ||
        lastRange.start > previousSourceLength) {
      return parseLines(sourceLines, version: version);
    }

    final hasBlankLineBoundary = _hasBlankLineBoundary(
      previousSourceEndsWithNewline: previousSourceEndsWithNewline,
      previousSourceEndsWithBlankLine: previousSourceEndsWithBlankLine,
      appendedLines: appendedLines,
    );
    if (hasBlankLineBoundary &&
        previousDocument.blocks.last is FootnoteListBlock) {
      return _parseAppendingAfterTrailingFootnotes(
        previousDocument: previousDocument,
        appendedLines: appendedLines,
        previousSourceLength: previousSourceLength,
        version: version,
      );
    }

    // A hidden trailing comment may still be open across a blank line.
    // Reparse its owning source tail before treating appended text as visible.
    final parseAppendedChunkAsNewBlocks = hasBlankLineBoundary &&
        !previousTailLines.any(
          MarkdownHtmlCommentBlockSyntax.openingPattern.hasMatch,
        ) &&
        _canKeepLastBlockStableAcrossBlankAppend(previousDocument.blocks.last);
    final prefixLength = parseAppendedChunkAsNewBlocks
        ? previousDocument.blocks.length
        : previousDocument.blocks.length - 1;
    if (prefixLength > 0) {
      final prefixTailRange =
          previousDocument.blocks[prefixLength - 1].sourceRange;
      final prefixBoundary = parseAppendedChunkAsNewBlocks
          ? previousSourceLength
          : lastRange.start;
      if (prefixTailRange == null || prefixTailRange.end > prefixBoundary) {
        return parseLines(sourceLines, version: version);
      }
    }

    final initialKindCounts = parseAppendedChunkAsNewBlocks
        ? _kindCountsForDocument(previousDocument)
        : _subtractBlockKinds(
            _kindCountsForDocument(previousDocument),
            previousDocument.blocks.last,
          );
    if (!parseAppendedChunkAsNewBlocks &&
        prefixLength > 0 &&
        initialKindCounts.isEmpty) {
      return parseLines(sourceLines, version: version);
    }

    final sourceOffset =
        parseAppendedChunkAsNewBlocks ? previousSourceLength : lastRange.start;
    final tailLines = parseAppendedChunkAsNewBlocks
        ? appendedLines
        : _appendLines(previousTailLines, appendedLines);
    final tailDocument = _parseDocument(
      tailLines,
      version: version,
      sourceOffset: sourceOffset,
      initialKindCounts: initialKindCounts,
    );

    final document = MarkdownDocument(
      blocks: _mergeBlockPrefix(
        previousDocument.blocks,
        prefixLength,
        tailDocument.blocks,
      ),
      version: version,
    );
    _documentKindCounts[document] = _kindCountsForDocument(tailDocument);
    return document;
  }

  MarkdownDocument _parseAppendingAfterTrailingFootnotes({
    required MarkdownDocument previousDocument,
    required List<String> appendedLines,
    required int previousSourceLength,
    required int version,
  }) {
    final previousFootnotes = previousDocument.blocks.last as FootnoteListBlock;
    final prefixLength = previousDocument.blocks.length - 1;
    final prefixKindCounts = _subtractBlockKinds(
      _kindCountsForDocument(previousDocument),
      previousFootnotes,
    );
    final tailDocument = _parseDocument(
      appendedLines,
      version: version,
      sourceOffset: previousSourceLength,
      initialKindCounts: prefixKindCounts,
    );

    final tailBlocks = tailDocument.blocks;
    final tailFootnotes =
        tailBlocks.isNotEmpty && tailBlocks.last is FootnoteListBlock
            ? tailBlocks.last as FootnoteListBlock
            : null;
    final tailContentLength =
        tailFootnotes == null ? tailBlocks.length : tailBlocks.length - 1;
    final mergedFootnotes = tailFootnotes == null
        ? previousFootnotes
        : _mergeFootnoteLists(previousFootnotes, tailFootnotes);
    final mergedTailBlocks = List<BlockNode>.unmodifiable(<BlockNode>[
      for (var index = 0; index < tailContentLength; index += 1)
        tailBlocks[index],
      mergedFootnotes,
    ]);
    final document = MarkdownDocument(
      blocks: _mergeBlockPrefix(
        previousDocument.blocks,
        prefixLength,
        mergedTailBlocks,
      ),
      version: version,
    );

    final kindCounts = <MarkdownBlockKind, int>{...prefixKindCounts};
    for (final block in mergedTailBlocks) {
      _countBlockKindsInBlock(block, kindCounts);
    }
    _documentKindCounts[document] = kindCounts;
    return document;
  }

  MarkdownDocument _parseDocument(
    List<String> lines, {
    required int version,
    required int sourceOffset,
    required Map<MarkdownBlockKind, int> initialKindCounts,
  }) {
    final timing = onTiming == null ? null : _MarkdownParserTimingBuilder();
    final totalStopwatch = timing == null ? null : (Stopwatch()..start());
    timing?.parseLineCount = lines.length;
    final document = md.Document(
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: buildMarkdownBlockSyntaxes(),
      inlineSyntaxes: buildMarkdownInlineSyntaxes(),
      encodeHtml: false,
    );
    final nodes = _measure(
      timing,
      (elapsed) => timing!.markdownParseLinesMicros += elapsed,
      () => document.parseLines(lines),
    );
    final builder = _MarkdownAstBuilder(
      initialKindCounts: initialKindCounts,
      timing: timing,
    );
    var blocks = _measure(
      timing,
      (elapsed) => timing!.buildBlocksMicros += elapsed,
      () => builder.buildBlocks(nodes),
    );
    final ranges = _measure(
      timing,
      (elapsed) => timing!.scanRangesMicros += elapsed,
      () => _scanTopLevelBlockRanges(
        lines,
        sourceOffset: sourceOffset,
      ),
    );
    final blockRanges = ranges.length == blocks.length + 1 &&
            (blocks.isEmpty || blocks.last is! FootnoteListBlock)
        ? ranges.take(blocks.length).toList(growable: false)
        : ranges;
    if (blockRanges.length == blocks.length) {
      blocks = _measure(
        timing,
        (elapsed) => timing!.applyRangesMicros += elapsed,
        () => List<BlockNode>.generate(
          blocks.length,
          (index) => _withSourceRange(blocks[index], blockRanges[index]),
          growable: false,
        ),
      );
    }

    final parsedDocument = MarkdownDocument(
      blocks: List<BlockNode>.unmodifiable(blocks),
      version: version,
    );
    _documentKindCounts[parsedDocument] = builder.kindCounts;
    if (timing != null && totalStopwatch != null) {
      totalStopwatch.stop();
      timing.totalMicros = totalStopwatch.elapsedMicroseconds;
      onTiming!(timing.build());
    }
    return parsedDocument;
  }

  T _measure<T>(
    _MarkdownParserTimingBuilder? timing,
    void Function(int elapsedMicros) record,
    T Function() run,
  ) {
    if (timing == null) {
      return run();
    }
    final stopwatch = Stopwatch()..start();
    final result = run();
    stopwatch.stop();
    record(stopwatch.elapsedMicroseconds);
    return result;
  }

  String _normalizeSource(String source) {
    if (!source.contains('\r')) {
      return source;
    }
    return source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  List<String> _splitNormalizedLines(String source) => source.split('\n');

  int _linesSourceLength(List<String> lines) {
    if (lines.isEmpty || (lines.length == 1 && lines.first.isEmpty)) {
      return 0;
    }
    var length = lines.length - 1;
    for (final line in lines) {
      length += line.length;
    }
    return length;
  }

  List<String> _appendLines(List<String> head, List<String> tail) {
    if (head.isEmpty || _linesSourceLength(head) == 0) {
      return List<String>.unmodifiable(tail);
    }
    if (tail.isEmpty || _linesSourceLength(tail) == 0) {
      return List<String>.unmodifiable(head);
    }
    return List<String>.unmodifiable(<String>[
      ...head.take(head.length - 1),
      '${head.last}${tail.first}',
      ...tail.skip(1),
    ]);
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

    if (block is DetailsBlock) {
      for (final child in block.children) {
        _countBlockKindsInBlock(child, counts);
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

  FootnoteListBlock _mergeFootnoteLists(
    FootnoteListBlock previous,
    FootnoteListBlock tail,
  ) {
    final sourceRangeStart = previous.sourceRange?.start;
    final sourceRangeEnd = tail.sourceRange?.end ?? previous.sourceRange?.end;
    return FootnoteListBlock(
      id: previous.id,
      items: List<ListItemNode>.unmodifiable(<ListItemNode>[
        ...previous.items,
        ...tail.items,
      ]),
      sourceRange: sourceRangeStart == null || sourceRangeEnd == null
          ? previous.sourceRange ?? tail.sourceRange
          : SourceRange(start: sourceRangeStart, end: sourceRangeEnd),
    );
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
      case MarkdownBlockKind.details:
        final details = block as DetailsBlock;
        return DetailsBlock(
          id: details.id,
          summary: details.summary,
          children: details.children,
          initiallyExpanded: details.initiallyExpanded,
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
          linkDestination: image.linkDestination,
          linkTitle: image.linkTitle,
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

  List<BlockNode> _mergeBlockPrefix(
    List<BlockNode> previousBlocks,
    int prefixLength,
    List<BlockNode> tailBlocks,
  ) {
    if (prefixLength == 0) {
      return tailBlocks;
    }
    if (tailBlocks.isEmpty) {
      if (prefixLength == previousBlocks.length) {
        return previousBlocks;
      }
      return _SegmentedBlockList.merge(
        previousBlocks,
        prefixLength,
        const <BlockNode>[],
      );
    }
    return _SegmentedBlockList.merge(previousBlocks, prefixLength, tailBlocks);
  }

  bool _hasBlankLineBoundary({
    required bool previousSourceEndsWithNewline,
    required bool previousSourceEndsWithBlankLine,
    required List<String> appendedLines,
  }) {
    final appendedStartsWithNewline =
        appendedLines.length > 1 && appendedLines.first.isEmpty;
    final appendedStartsWithBlankLine = appendedLines.length > 2 &&
        appendedLines[0].isEmpty &&
        appendedLines[1].isEmpty;
    if (previousSourceEndsWithBlankLine || appendedStartsWithBlankLine) {
      return true;
    }
    return previousSourceEndsWithNewline && appendedStartsWithNewline;
  }

  bool _canKeepLastBlockStableAcrossBlankAppend(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        return true;
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.details:
      case MarkdownBlockKind.codeBlock:
        return false;
    }
  }

  List<SourceRange> _scanTopLevelBlockRanges(
    List<String> lines, {
    required int sourceOffset,
  }) {
    if (lines.isEmpty || (lines.length == 1 && lines.first.isEmpty)) {
      return const <SourceRange>[];
    }

    final lineStarts = <int>[];
    var offset = 0;
    for (final line in lines) {
      lineStarts.add(offset);
      offset += line.length + 1;
    }

    final ranges = <SourceRange>[];
    int? hiddenStart;
    int? footnoteStart;
    int? footnoteEnd;
    var index = 0;
    while (index < lines.length) {
      if (_isBlankLine(lines[index])) {
        index += 1;
        continue;
      }

      if (MarkdownHtmlCommentBlockSyntax.openingPattern
          .hasMatch(lines[index])) {
        hiddenStart ??= index;
        while (index < lines.length) {
          final closed = lines[index].contains('-->');
          index += 1;
          if (closed) break;
        }
        continue;
      }

      // Let the next visible block own preceding hidden source, so reparsing
      // preserves comment boundaries without creating selectable empty blocks.
      final startIndex = hiddenStart ?? index;
      hiddenStart = null;
      if (_isFootnoteDefinitionStart(lines[index])) {
        final endIndex = _consumeFootnoteDefinition(lines, index);
        footnoteStart ??= sourceOffset + lineStarts[startIndex];
        footnoteEnd =
            sourceOffset + _lineEndOffset(lines, lineStarts, endIndex);
        index = endIndex + 1;
        continue;
      }

      final endIndex = _consumeBlock(lines, index);
      ranges.add(
        SourceRange(
          start: sourceOffset + lineStarts[startIndex],
          end: sourceOffset + _lineEndOffset(lines, lineStarts, endIndex),
        ),
      );
      index = endIndex + 1;
    }

    if (footnoteStart != null && footnoteEnd != null) {
      ranges.add(SourceRange(start: footnoteStart, end: footnoteEnd));
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
            _isListContinuationLineAfterBlank(lines[continuationIndex])) {
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

  int _consumeFootnoteDefinition(List<String> lines, int startIndex) {
    var endIndex = startIndex;
    while (endIndex + 1 < lines.length) {
      final nextIndex = endIndex + 1;
      final nextLine = lines[nextIndex];
      if (_isFootnoteDefinitionStart(nextLine)) {
        break;
      }
      if (_isBlankLine(nextLine)) {
        final continuationIndex = nextIndex + 1;
        if (continuationIndex < lines.length &&
            _isFootnoteContinuationLine(lines[continuationIndex])) {
          endIndex = continuationIndex;
          continue;
        }
        break;
      }
      if (_isFootnoteContinuationLine(nextLine)) {
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
        MarkdownHtmlCommentBlockSyntax.openingPattern.hasMatch(line) ||
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

  bool _isListContinuationLineAfterBlank(String line) {
    return _isListMarker(line) || _leadingIndent(line) >= 2;
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

  bool _isFootnoteDefinitionStart(String line) {
    return _footnoteDefinitionPattern.hasMatch(line);
  }

  bool _isFootnoteContinuationLine(String line) {
    return _leadingIndent(line) >= 4;
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
  static final RegExp _footnoteDefinitionPattern =
      RegExp(r'^\s{0,3}\[\^[^\]]+\]:');
  static final RegExp _definitionContinuationPattern =
      RegExp(r'^(?: {2,}|\t).*$');
  static final RegExp _tableSeparatorPattern = RegExp(
    r'^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$',
  );
  static final RegExp _thematicBreakPattern = RegExp(
    r'^\s{0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})\s*$',
  );
}

class _SegmentedBlockList extends ListBase<BlockNode> {
  _SegmentedBlockList._(this._segments, this.length);

  factory _SegmentedBlockList.merge(
    List<BlockNode> previousBlocks,
    int prefixLength,
    List<BlockNode> tailBlocks,
  ) {
    final segments = <_BlockSegment>[];
    var length = 0;

    void appendSegment(
      List<BlockNode> source,
      int sourceStart,
      int segmentLength,
    ) {
      if (segmentLength <= 0) {
        return;
      }
      segments.add(
        _BlockSegment(
          globalStart: length,
          source: source,
          sourceStart: sourceStart,
          length: segmentLength,
        ),
      );
      length += segmentLength;
    }

    if (previousBlocks is _SegmentedBlockList) {
      previousBlocks._appendPrefixSegments(segments, prefixLength);
      length = prefixLength;
    } else {
      appendSegment(previousBlocks, 0, prefixLength);
    }
    appendSegment(tailBlocks, 0, tailBlocks.length);
    return _SegmentedBlockList._(
      List<_BlockSegment>.unmodifiable(segments),
      length,
    );
  }

  final List<_BlockSegment> _segments;

  @override
  final int length;

  @override
  set length(int newLength) {
    throw UnsupportedError('Cannot modify segmented block list length.');
  }

  @override
  BlockNode operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    var low = 0;
    var high = _segments.length - 1;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final segment = _segments[mid];
      if (index < segment.globalStart) {
        high = mid - 1;
        continue;
      }
      final segmentEnd = segment.globalStart + segment.length;
      if (index >= segmentEnd) {
        low = mid + 1;
        continue;
      }
      return segment.source[segment.sourceStart + index - segment.globalStart];
    }
    throw StateError('Segmented block index was not found.');
  }

  @override
  void operator []=(int index, BlockNode value) {
    throw UnsupportedError('Cannot modify segmented block list contents.');
  }

  void _appendPrefixSegments(
    List<_BlockSegment> output,
    int prefixLength,
  ) {
    var remaining = prefixLength;
    var globalStart = 0;
    for (final segment in _segments) {
      if (remaining <= 0) {
        break;
      }
      final segmentLength =
          remaining < segment.length ? remaining : segment.length;
      output.add(
        _BlockSegment(
          globalStart: globalStart,
          source: segment.source,
          sourceStart: segment.sourceStart,
          length: segmentLength,
        ),
      );
      remaining -= segmentLength;
      globalStart += segmentLength;
    }
  }
}

class _BlockSegment {
  const _BlockSegment({
    required this.globalStart,
    required this.source,
    required this.sourceStart,
    required this.length,
  });

  final int globalStart;
  final List<BlockNode> source;
  final int sourceStart;
  final int length;
}

class _MarkdownParserTimingBuilder {
  int totalMicros = 0;
  int markdownParseLinesMicros = 0;
  int buildBlocksMicros = 0;
  int scanRangesMicros = 0;
  int applyRangesMicros = 0;
  int normalizeInlineMicros = 0;
  int nextIdMicros = 0;
  int parseLineCount = 0;

  MarkdownParserTiming build() {
    return MarkdownParserTiming(
      totalMicros: totalMicros,
      markdownParseLinesMicros: markdownParseLinesMicros,
      buildBlocksMicros: buildBlocksMicros,
      scanRangesMicros: scanRangesMicros,
      applyRangesMicros: applyRangesMicros,
      normalizeInlineMicros: normalizeInlineMicros,
      nextIdMicros: nextIdMicros,
      parseLineCount: parseLineCount,
    );
  }
}

class _MarkdownAstBuilder {
  _MarkdownAstBuilder({
    Map<MarkdownBlockKind, int>? initialKindCounts,
    _MarkdownParserTimingBuilder? timing,
  })  : _timing = timing,
        _kindCounters = <MarkdownBlockKind, int>{
          ...?initialKindCounts,
        };

  final Map<MarkdownBlockKind, int> _kindCounters;
  final _MarkdownParserTimingBuilder? _timing;

  Map<MarkdownBlockKind, int> get kindCounts =>
      Map<MarkdownBlockKind, int>.unmodifiable(_kindCounters);

  List<BlockNode> buildBlocks(List<md.Node> nodes) {
    final blocks = <BlockNode>[];
    for (final node in nodes) {
      if (node is md.Element && node.tag == 'html-fragment') {
        blocks.addAll(buildBlocks(node.children ?? const <md.Node>[]));
        continue;
      }
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
      case 'details':
        return _buildDetailsBlock(node);
      case 'summary':
        return ParagraphBlock(
          id: _nextId(MarkdownBlockKind.paragraph, node.textContent),
          inlines: _buildInlines(node.children),
        );
      case 'br':
        return ParagraphBlock(
          id: _nextId(MarkdownBlockKind.paragraph, 'br'),
          inlines: const <InlineNode>[HardBreakInline()],
        );
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
          items.add(_buildListItem(_stripFootnoteBackreferences(child)));
        }
      }
    }

    return FootnoteListBlock(
      id: _nextId(MarkdownBlockKind.footnoteList, node.textContent),
      items: List<ListItemNode>.unmodifiable(items),
    );
  }

  DetailsBlock _buildDetailsBlock(md.Element node) {
    final children = <BlockNode>[];
    List<InlineNode> summary = const <InlineNode>[];

    for (final child in node.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'summary') {
        if (summary.isEmpty) {
          summary =
              List<InlineNode>.unmodifiable(_buildInlines(child.children));
        }
        continue;
      }
      final block = _buildBlock(child);
      if (block != null) {
        children.add(block);
      }
    }

    return DetailsBlock(
      id: _nextId(MarkdownBlockKind.details, node.textContent),
      summary: summary.isEmpty
          ? const <InlineNode>[TextInline(text: 'Details')]
          : summary,
      children: List<BlockNode>.unmodifiable(children),
      initiallyExpanded: node.attributes.containsKey('open'),
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
      code: _normalizeCodeBlockText(
        codeElement is md.Element ? codeElement.textContent : node.textContent,
      ),
      language: language,
    );
  }

  String _normalizeCodeBlockText(String code) {
    if (code.endsWith('\r\n')) {
      return code.substring(0, code.length - 2);
    }
    if (code.endsWith('\n') || code.endsWith('\r')) {
      return code.substring(0, code.length - 1);
    }
    return code;
  }

  ImageBlock? _buildStandaloneImageParagraph(md.Element node) {
    final children = node.children;
    if (children == null || children.length != 1) {
      return null;
    }
    final child = children.single;
    md.Element? imageElement;
    md.Element? linkElement;

    if (child is md.Element && child.tag == 'img') {
      imageElement = child;
    } else if (child is md.Element && child.tag == 'a') {
      final linkChildren = child.children ?? const <md.Node>[];
      if (linkChildren.length == 1 &&
          linkChildren.single is md.Element &&
          (linkChildren.single as md.Element).tag == 'img') {
        linkElement = child;
        imageElement = linkChildren.single as md.Element;
      }
    }

    if (imageElement == null) {
      return null;
    }
    return ImageBlock(
      id: _nextId(
        MarkdownBlockKind.image,
        imageElement.attributes['src'] ?? imageElement.attributes['alt'] ?? '',
      ),
      url: imageElement.attributes['src'] ?? '',
      alt: imageElement.attributes['alt'],
      title: imageElement.attributes['title'],
      linkDestination: linkElement?.attributes['href'],
      linkTitle: linkElement?.attributes['title'],
    );
  }

  md.Element _stripFootnoteBackreferences(md.Element node) {
    final cleanedChildren = <md.Node>[];
    for (final child in node.children ?? const <md.Node>[]) {
      if (_isFootnoteBackreferenceNode(child)) {
        continue;
      }
      if (child is md.Element) {
        cleanedChildren.add(_stripFootnoteBackreferences(child));
      } else {
        cleanedChildren.add(child);
      }
    }
    final cleaned = md.Element(node.tag, cleanedChildren)
      ..attributes.addAll(node.attributes);
    return cleaned;
  }

  bool _isFootnoteBackreferenceNode(md.Node node) {
    if (node is! md.Element || node.tag != 'a') {
      return false;
    }
    final className = node.attributes['class'] ?? '';
    final href = node.attributes['href'] ?? '';
    return className.split(' ').contains('footnote-backref') ||
        href.startsWith('#fnref');
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
        final normalizedText = _normalizeInlineText(node.text);
        if (normalizedText.isNotEmpty) {
          inlines.add(TextInline(text: normalizedText));
        }
        continue;
      }
      if (node is! md.Element) {
        continue;
      }
      switch (node.tag) {
        case 'i':
        case 'em':
          inlines.add(EmphasisInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 'b':
        case 'strong':
          inlines.add(StrongInline(
              children:
                  List<InlineNode>.unmodifiable(_buildInlines(node.children))));
          break;
        case 's':
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
        case 'math':
          inlines.add(
            MathInline(
              tex: node.textContent,
              displayStyle: node.attributes['display'] == 'true',
            ),
          );
          break;
        case 'kbd':
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
          final normalizedText = _normalizeInlineText(node.textContent);
          if (children.isEmpty && normalizedText.isNotEmpty) {
            inlines.add(TextInline(text: normalizedText));
          } else {
            inlines.addAll(children);
          }
          break;
      }
    }
    return _measure(
      (elapsed) => _timing!.normalizeInlineMicros += elapsed,
      () => _normalizeInlineSequence(inlines).nodes,
    );
  }

  ({List<InlineNode> nodes, bool endsAtLineStart}) _normalizeInlineSequence(
    List<InlineNode> inlines, {
    bool atLineStart = true,
  }) {
    final normalized = <InlineNode>[];
    var isAtLineStart = atLineStart;

    for (final inline in inlines) {
      switch (inline.kind) {
        case MarkdownInlineKind.text:
          var text = (inline as TextInline).text;
          if (isAtLineStart) {
            text = text.replaceFirst(RegExp(r'^[ \t]+'), '');
          }
          if (text.isNotEmpty) {
            normalized.add(
              TextInline(text: text, sourceRange: inline.sourceRange),
            );
            isAtLineStart = text.endsWith('\n');
          }
          break;
        case MarkdownInlineKind.softBreak:
          normalized.add(inline);
          isAtLineStart = true;
          break;
        case MarkdownInlineKind.hardBreak:
          normalized.add(inline);
          isAtLineStart = true;
          break;
        case MarkdownInlineKind.emphasis:
          final emphasis = inline as EmphasisInline;
          final children = _normalizeInlineSequence(
            emphasis.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              EmphasisInline(
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.strong:
          final strong = inline as StrongInline;
          final children = _normalizeInlineSequence(
            strong.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              StrongInline(
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.strikethrough:
          final strike = inline as StrikethroughInline;
          final children = _normalizeInlineSequence(
            strike.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              StrikethroughInline(
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.highlight:
          final highlight = inline as HighlightInline;
          final children = _normalizeInlineSequence(
            highlight.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              HighlightInline(
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.subscript:
          final subscript = inline as SubscriptInline;
          final children = _normalizeInlineSequence(
            subscript.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              SubscriptInline(
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.superscript:
          final superscript = inline as SuperscriptInline;
          final children = _normalizeInlineSequence(
            superscript.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              SuperscriptInline(
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.link:
          final link = inline as LinkInline;
          final children = _normalizeInlineSequence(
            link.children,
            atLineStart: isAtLineStart,
          );
          if (children.nodes.isNotEmpty) {
            normalized.add(
              LinkInline(
                destination: link.destination,
                title: link.title,
                children: List<InlineNode>.unmodifiable(children.nodes),
                sourceRange: inline.sourceRange,
              ),
            );
          }
          isAtLineStart = children.endsAtLineStart;
          break;
        case MarkdownInlineKind.math:
        case MarkdownInlineKind.inlineCode:
        case MarkdownInlineKind.image:
          normalized.add(inline);
          isAtLineStart = false;
          break;
      }
    }

    return (nodes: normalized, endsAtLineStart: isAtLineStart);
  }

  String _normalizeInlineText(String text) {
    StringBuffer? buffer;
    var segmentStart = 0;
    var index = 0;
    while (index < text.length) {
      if (text.codeUnitAt(index) != 0x0A) {
        index += 1;
        continue;
      }

      var next = index + 1;
      while (next < text.length) {
        final codeUnit = text.codeUnitAt(next);
        if (codeUnit != 0x20 && codeUnit != 0x09) {
          break;
        }
        next += 1;
      }
      if (next == index + 1) {
        index += 1;
        continue;
      }

      buffer ??= StringBuffer();
      buffer.write(text.substring(segmentStart, index + 1));
      segmentStart = next;
      index = next;
    }

    if (buffer == null) {
      return text;
    }
    if (segmentStart < text.length) {
      buffer.write(text.substring(segmentStart));
    }
    return buffer.toString();
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
    return _measure(
      (elapsed) => _timing!.nextIdMicros += elapsed,
      () {
        final nextCount = (_kindCounters[kind] ?? 0) + 1;
        _kindCounters[kind] = nextCount;
        return '${kind.name}-$nextCount-${_stableHash(signature)}';
      },
    );
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

  T _measure<T>(
    void Function(int elapsedMicros) record,
    T Function() run,
  ) {
    if (_timing == null) {
      return run();
    }
    final stopwatch = Stopwatch()..start();
    final result = run();
    stopwatch.stop();
    record(stopwatch.elapsedMicroseconds);
    return result;
  }
}

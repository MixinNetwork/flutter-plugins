import 'package:flutter/material.dart';

import '../../clipboard/plain_text_serializer.dart';
import '../../core/document.dart';
import '../../widgets/markdown_theme.dart';
import '../code_syntax_highlighter.dart';
import '../pretext_text_block.dart';
import '../builder/markdown_inline_builder.dart';

@immutable
class SelectableTextDescriptor {
  const SelectableTextDescriptor({
    required this.plainText,
    required this.span,
    this.pretext,
  });

  final String plainText;
  final TextSpan span;
  final PretextTextDescriptor? pretext;

  bool get isEmpty => plainText.isEmpty;
}

@immutable
class PretextTextDescriptor {
  const PretextTextDescriptor({
    required this.runs,
    required this.fallbackStyle,
    required this.textAlign,
  });

  final List<MarkdownPretextInlineRun> runs;
  final TextStyle fallbackStyle;
  final TextAlign textAlign;
}

@immutable
class _PrefixedPretextRuns {
  const _PrefixedPretextRuns({
    required this.plainText,
    required this.runs,
  });

  final String plainText;
  final List<MarkdownPretextInlineRun> runs;
}

@immutable
class IndexedListSelectionDescriptor {
  const IndexedListSelectionDescriptor({
    required this.itemIndex,
    required this.startOffset,
    required this.prefixLength,
    required this.contentIndentLevel,
    required this.descriptor,
    required this.contentDescriptor,
  });

  final int itemIndex;
  final int startOffset;
  final int prefixLength;
  final int contentIndentLevel;
  final SelectableTextDescriptor descriptor;
  final SelectableTextDescriptor contentDescriptor;
}

@immutable
class IndexedBlockDescriptor {
  const IndexedBlockDescriptor({
    required this.childIndex,
    required this.block,
    required this.startOffset,
    required this.indentLevel,
    required this.descriptor,
  });

  final int childIndex;
  final BlockNode block;
  final int startOffset;
  final int indentLevel;
  final SelectableTextDescriptor descriptor;
}

@immutable
class ResolvedIndexedBlockEntry {
  const ResolvedIndexedBlockEntry({
    required this.entry,
    required this.renderObject,
    required this.rect,
  });

  final IndexedBlockDescriptor entry;
  final RenderBox renderObject;
  final Rect rect;
}

class MarkdownDescriptorExtractor {
  const MarkdownDescriptorExtractor({
    required this.theme,
    required this.plainTextSerializer,
    required this.inlineBuilder,
    required this.codeSyntaxHighlighter,
  });

  final MarkdownThemeData theme;
  final MarkdownPlainTextSerializer plainTextSerializer;
  final MarkdownInlineBuilder inlineBuilder;
  final MarkdownCodeSyntaxHighlighter codeSyntaxHighlighter;

  SelectableTextDescriptor buildSelectableDescriptorForBlock(
    BlockNode block, {
    int indentLevel = 0,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        return descriptorFromInlines(
          theme.headingStyleForLevel(heading.level),
          heading.inlines,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return descriptorFromInlines(
          theme.bodyStyle,
          paragraph.inlines,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(paragraph.inlines),
        );
      case MarkdownBlockKind.quote:
        return buildQuoteSelectableDescriptor(block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return buildListSelectableDescriptor(
          block as ListBlock,
          indentLevel: indentLevel,
        );
      case MarkdownBlockKind.definitionList:
        return buildDefinitionListSelectableDescriptor(
          block as DefinitionListBlock,
        );
      case MarkdownBlockKind.footnoteList:
        return buildFootnoteListSelectableDescriptor(
          block as FootnoteListBlock,
        );
      case MarkdownBlockKind.codeBlock:
        final codeBlock = block as CodeBlock;
        return descriptorFromRuns(
          codeSyntaxHighlighter.buildPretextRuns(
            source: codeBlock.code,
            baseStyle: theme.codeBlockStyle,
            theme: theme,
            language: codeBlock.language,
          ),
          plainText: codeBlock.code,
          fallbackStyle: theme.codeBlockStyle,
        );
      case MarkdownBlockKind.table:
        return buildTableSelectableDescriptor(block as TableBlock);
      case MarkdownBlockKind.image:
        final imageBlock = block as ImageBlock;
        final caption = imageCaptionText(imageBlock);
        if (caption.isEmpty) {
          return plainTextDescriptor('', theme.bodyStyle);
        }
        return buildImageCaptionDescriptor(imageBlock);
      case MarkdownBlockKind.thematicBreak:
        return plainTextDescriptor('---', theme.bodyStyle);
    }
  }

  SelectableTextDescriptor buildListSelectableDescriptor(
    ListBlock block, {
    int indentLevel = 0,
  }) {
    final itemDescriptors = buildIndexedListSelectionDescriptors(
      block,
      indentLevel: indentLevel,
    ).map((entry) => entry.descriptor).toList(growable: false);
    return joinSelectableTextDescriptors(
      itemDescriptors,
      separator: '\n',
      separatorStyle: theme.bodyStyle,
    );
  }

  SelectableTextDescriptor buildDefinitionListSelectableDescriptor(
    DefinitionListBlock block,
  ) {
    final itemDescriptors = <SelectableTextDescriptor>[];
    for (final item in block.items) {
      final termDescriptor =
          descriptorFromInlines(definitionTermStyle, item.term);
      final definitionDescriptors = <SelectableTextDescriptor>[];
      for (final definition in item.definitions) {
        final childDescriptors = <SelectableTextDescriptor>[];
        for (final child in definition) {
          final descriptor = buildSelectableDescriptorForBlock(
            child,
            indentLevel: 1,
          );
          if (!descriptor.isEmpty) {
            childDescriptors.add(descriptor);
          }
        }
        final definitionDescriptor = joinSelectableTextDescriptors(
          childDescriptors,
          separator: '\n\n',
          separatorStyle: theme.bodyStyle,
        );
        if (!definitionDescriptor.isEmpty) {
          definitionDescriptors.add(
            prefixSelectableTextDescriptor(
              definitionDescriptor,
              firstPrefix: ': ',
              continuationPrefix: '  ',
              style: theme.bodyStyle,
            ),
          );
        }
      }
      final itemDescriptor = joinSelectableTextDescriptors(
        <SelectableTextDescriptor>[termDescriptor, ...definitionDescriptors],
        separator: '\n',
        separatorStyle: theme.bodyStyle,
      );
      if (!itemDescriptor.isEmpty) {
        itemDescriptors.add(itemDescriptor);
      }
    }
    return joinSelectableTextDescriptors(
      itemDescriptors,
      separator: '\n',
      separatorStyle: theme.bodyStyle,
    );
  }

  SelectableTextDescriptor buildFootnoteListSelectableDescriptor(
    FootnoteListBlock block,
  ) {
    return buildListSelectableDescriptor(footnoteListAsOrderedList(block));
  }

  List<IndexedBlockDescriptor> buildIndexedBlockDescriptors(
    List<BlockNode> blocks, {
    int indentLevel = 0,
    required String separator,
  }) {
    final entries = <IndexedBlockDescriptor>[];
    var offset = 0;
    for (var index = 0; index < blocks.length; index++) {
      final descriptor = buildSelectableDescriptorForBlock(
        blocks[index],
        indentLevel: indentLevel,
      );
      if (descriptor.isEmpty) {
        continue;
      }
      if (entries.isNotEmpty) {
        offset += separator.length;
      }
      entries.add(
        IndexedBlockDescriptor(
          childIndex: index,
          block: blocks[index],
          startOffset: offset,
          indentLevel: indentLevel,
          descriptor: descriptor,
        ),
      );
      offset += descriptor.plainText.length;
    }
    return entries;
  }

  List<IndexedListSelectionDescriptor> buildIndexedListSelectionDescriptors(
    ListBlock block, {
    int indentLevel = 0,
  }) {
    final entries = <IndexedListSelectionDescriptor>[];
    var offset = 0;
    for (var index = 0; index < block.items.length; index++) {
      if (entries.isNotEmpty) {
        offset += 1;
      }
      final entry = _buildIndexedListSelectionDescriptor(
        block,
        index,
        startOffset: offset,
        indentLevel: indentLevel,
      );
      if (entry == null) {
        if (entries.isNotEmpty) {
          offset -= 1;
        }
        continue;
      }
      entries.add(entry);
      offset += entry.descriptor.plainText.length;
    }
    return entries;
  }

  IndexedListSelectionDescriptor? _buildIndexedListSelectionDescriptor(
    ListBlock block,
    int index, {
    required int startOffset,
    int indentLevel = 0,
  }) {
    final prefix = listItemPrefixText(
      block,
      index,
      indentLevel: indentLevel,
    );
    final contentDescriptor = buildListItemSelectableDescriptor(
      block.items[index],
      indentLevel: indentLevel + 1,
    );
    if (contentDescriptor.isEmpty && block.items[index].taskState == null) {
      return null;
    }
    if (contentDescriptor.isEmpty) {
      final prefixOnly = prefix.trimRight();
      return IndexedListSelectionDescriptor(
        itemIndex: index,
        startOffset: startOffset,
        prefixLength: prefixOnly.length,
        contentIndentLevel: indentLevel + 1,
        descriptor: plainTextDescriptor(prefixOnly, theme.bodyStyle),
        contentDescriptor: plainTextDescriptor('', theme.bodyStyle),
      );
    }
    final continuationPrefix = ' ' * prefix.length;
    final descriptor = prefixSelectableTextDescriptor(
      contentDescriptor,
      firstPrefix: prefix,
      continuationPrefix: continuationPrefix,
      style: theme.bodyStyle,
    );
    return IndexedListSelectionDescriptor(
      itemIndex: index,
      startOffset: startOffset,
      prefixLength: prefix.length,
      contentIndentLevel: indentLevel + 1,
      descriptor: descriptor,
      contentDescriptor: contentDescriptor,
    );
  }

  SelectableTextDescriptor buildListItemSelectableDescriptor(
    ListItemNode item, {
    required int indentLevel,
  }) {
    final childDescriptors = <SelectableTextDescriptor>[];
    for (final child in item.children) {
      final descriptor = buildSelectableDescriptorForBlock(
        child,
        indentLevel: indentLevel,
      );
      if (!descriptor.isEmpty) {
        childDescriptors.add(descriptor);
      }
    }
    return joinSelectableTextDescriptors(
      childDescriptors,
      separator: '\n',
      separatorStyle: theme.bodyStyle,
    );
  }

  SelectableTextDescriptor buildQuoteSelectableDescriptor(QuoteBlock block) {
    final childDescriptors = <SelectableTextDescriptor>[];
    for (final child in block.children) {
      final descriptor = buildSelectableDescriptorForBlock(child);
      if (!descriptor.isEmpty) {
        childDescriptors.add(descriptor);
      }
    }
    final joined = joinSelectableTextDescriptors(
      childDescriptors,
      separator: '\n\n',
      separatorStyle: theme.quoteStyle,
    );
    return joined;
  }

  DocumentRange? resolveSelectionUnitRange(
    DocumentPosition position,
    BlockNode block, {
    int baseOffset = 0,
    int indentLevel = 0,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.quote:
        final quoteBlock = block as QuoteBlock;
        return _resolveQuoteBlockSelectionRange(
          position,
          quoteBlock,
          indexedBlocks: buildIndexedBlockDescriptors(
            quoteBlock.children,
            separator: '\n\n',
          ),
          baseOffset: baseOffset,
        );
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        final listBlock = block as ListBlock;
        return _resolveListItemSelectionRange(
          position,
          listBlock,
          indexedItems: buildIndexedListSelectionDescriptors(
            listBlock,
            indentLevel: indentLevel,
          ),
          baseOffset: baseOffset,
        );
      case MarkdownBlockKind.footnoteList:
        return resolveSelectionUnitRange(
          position,
          footnoteListAsOrderedList(block as FootnoteListBlock),
          baseOffset: baseOffset,
          indentLevel: indentLevel,
        );
      case MarkdownBlockKind.table:
        return resolveTableCellSelectionRange(
          position,
          block as TableBlock,
          baseOffset: baseOffset,
        );
      default:
        return null;
    }
  }

  DocumentRange? resolveTableCellSelectionRange(
    DocumentPosition position,
    TableBlock block, {
    int baseOffset = 0,
  }) {
    final cellRange = _tableCellTextRange(
      block,
      position.textOffset - baseOffset,
    );
    if (cellRange == null) {
      return null;
    }
    return _rangeForBlockOffsets(
      blockIndex: position.blockIndex,
      startOffset: baseOffset + cellRange.start,
      endOffset: baseOffset + cellRange.end,
    );
  }

  SelectableTextDescriptor buildImageCaptionDescriptor(ImageBlock block) {
    final caption = imageCaptionText(block);
    return plainTextDescriptor(caption, imageCaptionStyle);
  }

  SelectableTextDescriptor buildTableSelectableDescriptor(TableBlock block) {
    final rowDescriptors = <SelectableTextDescriptor>[];
    for (final row in block.rows) {
      final cellDescriptors = <SelectableTextDescriptor>[];
      for (final cell in row.cells) {
        cellDescriptors.add(descriptorFromInlines(
          row.isHeader ? theme.tableHeaderStyle : theme.bodyStyle,
          cell.inlines,
          textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
            cell.inlines,
          ),
        ));
      }
      rowDescriptors.add(
        joinSelectableTextDescriptors(
          cellDescriptors,
          separator: '\t',
          separatorStyle:
              row.isHeader ? theme.tableHeaderStyle : theme.bodyStyle,
        ),
      );
    }
    return joinSelectableTextDescriptors(
      rowDescriptors,
      separator: '\n',
      separatorStyle: theme.bodyStyle,
    );
  }

  SelectableTextDescriptor descriptorFromRuns(
    List<MarkdownPretextInlineRun> runs, {
    required String plainText,
    required TextStyle fallbackStyle,
    TextAlign textAlign = TextAlign.start,
  }) {
    return _descriptorFromSpan(
      buildMarkdownPretextSpan(
        runs: runs,
        fallbackStyle: fallbackStyle,
      ) as TextSpan,
      plainText,
      pretext: PretextTextDescriptor(
        runs: runs,
        fallbackStyle: fallbackStyle,
        textAlign: textAlign,
      ),
    );
  }

  SelectableTextDescriptor descriptorFromInlines(
    TextStyle style,
    List<InlineNode> inlines, {
    TextAlign textAlign = TextAlign.start,
  }) {
    final runs = inlineBuilder.buildPretextRuns(style, inlines);
    return descriptorFromRuns(
      runs,
      plainText: MarkdownInlineBuilder.flattenInlineText(inlines),
      fallbackStyle: style,
      textAlign: textAlign,
    );
  }

  SelectableTextDescriptor _descriptorFromSpan(
    TextSpan span,
    String plainText, {
    PretextTextDescriptor? pretext,
  }) {
    return SelectableTextDescriptor(
      plainText: plainText,
      span: span,
      pretext: pretext,
    );
  }

  SelectableTextDescriptor plainTextDescriptor(String text, TextStyle style) {
    return descriptorFromRuns(
      <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(text: text, style: style),
      ],
      plainText: text,
      fallbackStyle: style,
    );
  }

  SelectableTextDescriptor joinSelectableTextDescriptors(
    List<SelectableTextDescriptor> descriptors, {
    required String separator,
    required TextStyle separatorStyle,
  }) {
    final nonEmpty =
        descriptors.where((descriptor) => !descriptor.isEmpty).toList();
    if (nonEmpty.isEmpty) {
      return plainTextDescriptor('', separatorStyle);
    }
    if (nonEmpty.length == 1) {
      return nonEmpty.single;
    }
    final buffer = StringBuffer();
    final children = <InlineSpan>[];
    for (var index = 0; index < nonEmpty.length; index++) {
      if (index > 0) {
        buffer.write(separator);
        children.add(TextSpan(style: separatorStyle, text: separator));
      }
      buffer.write(nonEmpty[index].plainText);
      children.add(nonEmpty[index].span);
    }
    if (nonEmpty.every((descriptor) => descriptor.pretext != null)) {
      final runs = <MarkdownPretextInlineRun>[];
      for (var index = 0; index < nonEmpty.length; index++) {
        if (index > 0 && separator.isNotEmpty) {
          runs.add(
              MarkdownPretextInlineRun(text: separator, style: separatorStyle));
        }
        runs.addAll(nonEmpty[index].pretext!.runs);
      }
      return descriptorFromRuns(
        runs,
        plainText: buffer.toString(),
        fallbackStyle: nonEmpty.first.pretext!.fallbackStyle,
      );
    }
    return SelectableTextDescriptor(
      plainText: buffer.toString(),
      span: TextSpan(children: children),
    );
  }

  DocumentRange? _resolveListItemSelectionRange(
    DocumentPosition position,
    ListBlock block, {
    required List<IndexedListSelectionDescriptor> indexedItems,
    int baseOffset = 0,
  }) {
    if (indexedItems.isEmpty) {
      return null;
    }
    final offset = position.textOffset;
    for (final item in indexedItems) {
      final start = baseOffset + item.startOffset;
      final end = start + item.descriptor.plainText.length;
      if (offset >= start && offset <= end) {
        final childUnit = _resolveListItemChildSelectionRange(
          position,
          block.items[item.itemIndex].children,
          itemStartOffset: start,
          contentBaseOffset: start + item.prefixLength,
          indentLevel: item.contentIndentLevel,
          continuationIndent: item.prefixLength,
        );
        if (childUnit != null) {
          return childUnit;
        }
        return _rangeForBlockOffsets(
          blockIndex: position.blockIndex,
          startOffset: start,
          endOffset: end,
        );
      }
    }
    final last = indexedItems.last;
    return _rangeForBlockOffsets(
      blockIndex: position.blockIndex,
      startOffset: baseOffset + last.startOffset,
      endOffset:
          baseOffset + last.startOffset + last.descriptor.plainText.length,
    );
  }

  DocumentRange? _resolveQuoteBlockSelectionRange(
    DocumentPosition position,
    QuoteBlock block, {
    required List<IndexedBlockDescriptor> indexedBlocks,
    int baseOffset = 0,
  }) {
    if (indexedBlocks.isEmpty) {
      return null;
    }
    final offset = position.textOffset;
    for (final entry in indexedBlocks) {
      final start = baseOffset + entry.startOffset;
      final end = start + entry.descriptor.plainText.length;
      if (offset >= start && offset <= end) {
        final nested = resolveSelectionUnitRange(
          position,
          entry.block,
          baseOffset: start,
          indentLevel: entry.indentLevel,
        );
        if (nested != null) {
          return nested;
        }
        return _rangeForBlockOffsets(
          blockIndex: position.blockIndex,
          startOffset: start,
          endOffset: end,
        );
      }
    }
    final last = indexedBlocks.last;
    return _rangeForBlockOffsets(
      blockIndex: position.blockIndex,
      startOffset: baseOffset + last.startOffset,
      endOffset:
          baseOffset + last.startOffset + last.descriptor.plainText.length,
    );
  }

  DocumentRange? _resolveListItemChildSelectionRange(
    DocumentPosition position,
    List<BlockNode> blocks, {
    required int itemStartOffset,
    required int contentBaseOffset,
    required int indentLevel,
    int continuationIndent = 0,
  }) {
    final indexedBlocks = buildIndexedBlockDescriptors(
      blocks,
      indentLevel: indentLevel,
      separator: '\n',
    );
    if (indexedBlocks.isEmpty) {
      return null;
    }
    final offset = position.textOffset;
    for (final entry in indexedBlocks) {
      final rawChildBaseOffset = contentBaseOffset + entry.startOffset;
      final rawChildEndOffset =
          rawChildBaseOffset + entry.descriptor.plainText.length;
      if (offset < rawChildBaseOffset || offset > rawChildEndOffset) {
        continue;
      }

      final childUnit = resolveSelectionUnitRange(
            position,
            entry.block,
            baseOffset: rawChildBaseOffset +
                (entry.childIndex > 0 ? continuationIndent : 0),
            indentLevel: entry.indentLevel,
          ) ??
          _rangeForBlockOffsets(
            blockIndex: position.blockIndex,
            startOffset: rawChildBaseOffset,
            endOffset: rawChildEndOffset,
          );

      if (entry.childIndex == 0 && _isLeadListTextBlock(entry.block)) {
        return _rangeForBlockOffsets(
          blockIndex: position.blockIndex,
          startOffset: itemStartOffset,
          endOffset: childUnit.end.textOffset,
        );
      }
      return childUnit;
    }
    return null;
  }

  bool _isLeadListTextBlock(BlockNode block) {
    switch (block.kind) {
      case MarkdownBlockKind.paragraph:
      case MarkdownBlockKind.heading:
        return true;
      case MarkdownBlockKind.quote:
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
      case MarkdownBlockKind.definitionList:
      case MarkdownBlockKind.footnoteList:
      case MarkdownBlockKind.codeBlock:
      case MarkdownBlockKind.table:
      case MarkdownBlockKind.image:
      case MarkdownBlockKind.thematicBreak:
        return false;
    }
  }

  DocumentRange _rangeForBlockOffsets({
    required int blockIndex,
    required int startOffset,
    required int endOffset,
  }) {
    return DocumentRange(
      start: DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: startOffset,
      ),
      end: DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: endOffset,
      ),
    );
  }

  ({int start, int end})? _tableCellTextRange(
      TableBlock block, int textOffset) {
    var currentOffset = 0;
    for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
      final row = block.rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.cells.length; columnIndex++) {
        final cellLength = MarkdownInlineBuilder.flattenInlineText(
          row.cells[columnIndex].inlines,
        ).length;
        final cellStart = currentOffset;
        final cellEnd = cellStart + cellLength;
        if (textOffset <= cellEnd) {
          return (start: cellStart, end: cellEnd);
        }
        currentOffset = cellEnd + 1;
      }
    }
    return null;
  }

  SelectableTextDescriptor prefixSelectableTextDescriptor(
    SelectableTextDescriptor descriptor, {
    required String firstPrefix,
    required String continuationPrefix,
    required TextStyle style,
  }) {
    if (descriptor.isEmpty) {
      return plainTextDescriptor('', style);
    }
    final pretext = descriptor.pretext;
    if (pretext != null) {
      final prefixed = _prefixPretextRuns(
        pretext.runs,
        firstPrefix: firstPrefix,
        continuationPrefix: continuationPrefix,
        prefixStyle: style,
      );
      return descriptorFromRuns(
        prefixed.runs,
        plainText: prefixed.plainText,
        fallbackStyle: pretext.fallbackStyle,
        textAlign: pretext.textAlign,
      );
    }
    if (descriptor.plainText.contains('\n')) {
      final lines = descriptor.plainText.split('\n');
      final buffer = StringBuffer();
      for (var index = 0; index < lines.length; index++) {
        final prefix = index == 0 ? firstPrefix : continuationPrefix;
        if (index > 0) {
          buffer.write('\n');
        }
        if (lines[index].isEmpty) {
          buffer.write(prefix.trimRight());
        } else {
          buffer.write(prefix);
          buffer.write(lines[index]);
        }
      }
      return plainTextDescriptor(buffer.toString(), style);
    }
    return SelectableTextDescriptor(
      plainText: '$firstPrefix${descriptor.plainText}',
      span: TextSpan(
        children: <InlineSpan>[
          TextSpan(style: style, text: firstPrefix),
          descriptor.span,
        ],
      ),
    );
  }

  static String imageCaptionText(ImageBlock block) {
    return (block.alt ?? block.title ?? '').trim();
  }

  _PrefixedPretextRuns _prefixPretextRuns(
    List<MarkdownPretextInlineRun> runs, {
    required String firstPrefix,
    required String continuationPrefix,
    required TextStyle prefixStyle,
  }) {
    final buffer = StringBuffer();
    final prefixedRuns = <MarkdownPretextInlineRun>[];
    var pendingPrefix = firstPrefix;
    var atLineStart = true;

    void writePrefix({required bool trimTrailing}) {
      final prefixText =
          trimTrailing ? pendingPrefix.trimRight() : pendingPrefix;
      if (prefixText.isNotEmpty) {
        prefixedRuns.add(
          MarkdownPretextInlineRun(text: prefixText, style: prefixStyle),
        );
        buffer.write(prefixText);
      }
      atLineStart = false;
      pendingPrefix = continuationPrefix;
    }

    for (final run in runs) {
      final segments = run.text.split('\n');
      for (var index = 0; index < segments.length; index++) {
        final segmentText = segments[index];
        if (segmentText.isNotEmpty) {
          if (atLineStart) {
            writePrefix(trimTrailing: false);
          }
          prefixedRuns.add(run.copyWithText(segmentText));
          buffer.write(segmentText);
        }

        if (index == segments.length - 1) {
          continue;
        }

        if (atLineStart) {
          writePrefix(trimTrailing: true);
        }
        prefixedRuns
            .add(MarkdownPretextInlineRun(text: '\n', style: run.style));
        buffer.write('\n');
        atLineStart = true;
        pendingPrefix = continuationPrefix;
      }
    }

    if (atLineStart) {
      writePrefix(trimTrailing: true);
    }

    return _PrefixedPretextRuns(
      plainText: buffer.toString(),
      runs: List<MarkdownPretextInlineRun>.unmodifiable(prefixedRuns),
    );
  }

  TextStyle get imageCaptionStyle {
    return theme.bodyStyle.copyWith(
      fontSize: 13,
      color: theme.bodyStyle.color?.withValues(alpha: 0.72),
    );
  }

  TextStyle get definitionTermStyle {
    return theme.bodyStyle.copyWith(fontWeight: FontWeight.w700);
  }

  static String listItemPrefixText(
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

  static ListBlock footnoteListAsOrderedList(FootnoteListBlock block) {
    return ListBlock(
      id: block.id,
      ordered: true,
      startIndex: 1,
      items: block.items,
      sourceRange: block.sourceRange,
    );
  }
}

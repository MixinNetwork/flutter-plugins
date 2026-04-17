import 'package:flutter/foundation.dart';

enum MarkdownBlockKind {
  heading,
  paragraph,
  quote,
  orderedList,
  unorderedList,
  definitionList,
  footnoteList,
  codeBlock,
  table,
  image,
  thematicBreak,
}

enum MarkdownInlineKind {
  text,
  emphasis,
  strong,
  strikethrough,
  highlight,
  subscript,
  superscript,
  link,
  math,
  inlineCode,
  softBreak,
  hardBreak,
  image,
}

enum MarkdownTaskListItemState {
  checked,
  unchecked,
}

enum MarkdownTableColumnAlignment {
  left,
  center,
  right,
  none,
}

@immutable
class SourceRange {
  const SourceRange({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;
}

@immutable
class MarkdownDocument {
  const MarkdownDocument({
    required this.blocks,
    required this.sourceText,
    this.version = 0,
  });

  const MarkdownDocument.empty()
      : blocks = const <BlockNode>[],
        sourceText = '',
        version = 0;

  final List<BlockNode> blocks;
  final String sourceText;
  final int version;
}

@immutable
abstract class BlockNode {
  const BlockNode({
    required this.id,
    required this.kind,
    this.sourceRange,
  });

  final String id;
  final MarkdownBlockKind kind;
  final SourceRange? sourceRange;
}

@immutable
class HeadingBlock extends BlockNode {
  const HeadingBlock({
    required super.id,
    required this.level,
    required this.inlines,
    this.anchorId,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.heading);

  final int level;
  final List<InlineNode> inlines;
  final String? anchorId;
}

@immutable
class ParagraphBlock extends BlockNode {
  const ParagraphBlock({
    required super.id,
    required this.inlines,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.paragraph);

  final List<InlineNode> inlines;
}

@immutable
class QuoteBlock extends BlockNode {
  const QuoteBlock({
    required super.id,
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.quote);

  final List<BlockNode> children;
}

@immutable
class ListBlock extends BlockNode {
  const ListBlock({
    required super.id,
    required this.ordered,
    required this.items,
    this.startIndex = 1,
    super.sourceRange,
  }) : super(
          kind: ordered
              ? MarkdownBlockKind.orderedList
              : MarkdownBlockKind.unorderedList,
        );

  final bool ordered;
  final int startIndex;
  final List<ListItemNode> items;
}

@immutable
class ListItemNode {
  const ListItemNode({
    required this.children,
    this.taskState,
  });

  final List<BlockNode> children;
  final MarkdownTaskListItemState? taskState;
}

@immutable
class DefinitionListBlock extends BlockNode {
  const DefinitionListBlock({
    required super.id,
    required this.items,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.definitionList);

  final List<DefinitionListItemNode> items;
}

@immutable
class DefinitionListItemNode {
  const DefinitionListItemNode({
    required this.term,
    required this.definitions,
  });

  final List<InlineNode> term;
  final List<List<BlockNode>> definitions;
}

@immutable
class FootnoteListBlock extends BlockNode {
  const FootnoteListBlock({
    required super.id,
    required this.items,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.footnoteList);

  final List<ListItemNode> items;
}

@immutable
class CodeBlock extends BlockNode {
  const CodeBlock({
    required super.id,
    required this.code,
    this.language,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.codeBlock);

  final String code;
  final String? language;
}

@immutable
class TableBlock extends BlockNode {
  const TableBlock({
    required super.id,
    required this.alignments,
    required this.rows,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.table);

  final List<MarkdownTableColumnAlignment> alignments;
  final List<TableRowNode> rows;
}

@immutable
class TableRowNode {
  const TableRowNode({
    required this.cells,
    required this.isHeader,
  });

  final List<TableCellNode> cells;
  final bool isHeader;
}

@immutable
class TableCellNode {
  const TableCellNode({required this.inlines});

  final List<InlineNode> inlines;
}

@immutable
class ImageBlock extends BlockNode {
  const ImageBlock({
    required super.id,
    required this.url,
    this.alt,
    this.title,
    this.linkDestination,
    this.linkTitle,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.image);

  final String url;
  final String? alt;
  final String? title;
  final String? linkDestination;
  final String? linkTitle;
}

@immutable
class ThematicBreakBlock extends BlockNode {
  const ThematicBreakBlock({
    required super.id,
    super.sourceRange,
  }) : super(kind: MarkdownBlockKind.thematicBreak);
}

@immutable
abstract class InlineNode {
  const InlineNode({
    required this.kind,
    this.sourceRange,
  });

  final MarkdownInlineKind kind;
  final SourceRange? sourceRange;
}

@immutable
class TextInline extends InlineNode {
  const TextInline({
    required this.text,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.text);

  final String text;
}

@immutable
class EmphasisInline extends InlineNode {
  const EmphasisInline({
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.emphasis);

  final List<InlineNode> children;
}

@immutable
class StrongInline extends InlineNode {
  const StrongInline({
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.strong);

  final List<InlineNode> children;
}

@immutable
class StrikethroughInline extends InlineNode {
  const StrikethroughInline({
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.strikethrough);

  final List<InlineNode> children;
}

@immutable
class HighlightInline extends InlineNode {
  const HighlightInline({
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.highlight);

  final List<InlineNode> children;
}

@immutable
class SubscriptInline extends InlineNode {
  const SubscriptInline({
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.subscript);

  final List<InlineNode> children;
}

@immutable
class SuperscriptInline extends InlineNode {
  const SuperscriptInline({
    required this.children,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.superscript);

  final List<InlineNode> children;
}

@immutable
class LinkInline extends InlineNode {
  const LinkInline({
    required this.destination,
    required this.children,
    this.title,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.link);

  final String destination;
  final String? title;
  final List<InlineNode> children;
}

@immutable
class MathInline extends InlineNode {
  const MathInline({
    required this.tex,
    this.displayStyle = false,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.math);

  final String tex;
  final bool displayStyle;
}

@immutable
class InlineCode extends InlineNode {
  const InlineCode({
    required this.text,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.inlineCode);

  final String text;
}

@immutable
class SoftBreakInline extends InlineNode {
  const SoftBreakInline({super.sourceRange})
      : super(kind: MarkdownInlineKind.softBreak);
}

@immutable
class HardBreakInline extends InlineNode {
  const HardBreakInline({super.sourceRange})
      : super(kind: MarkdownInlineKind.hardBreak);
}

@immutable
class InlineImage extends InlineNode {
  const InlineImage({
    required this.url,
    this.alt,
    super.sourceRange,
  }) : super(kind: MarkdownInlineKind.image);

  final String url;
  final String? alt;
}

@immutable
class PathInBlock implements Comparable<PathInBlock> {
  const PathInBlock(this.segments);

  final List<int> segments;

  @override
  int compareTo(PathInBlock other) {
    final minLength = segments.length < other.segments.length
        ? segments.length
        : other.segments.length;
    for (var index = 0; index < minLength; index++) {
      final comparison = segments[index].compareTo(other.segments[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return segments.length.compareTo(other.segments.length);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PathInBlock && listEquals(other.segments, segments);
  }

  @override
  int get hashCode => Object.hashAll(segments);
}

@immutable
class DocumentPosition implements Comparable<DocumentPosition> {
  const DocumentPosition({
    required this.blockIndex,
    required this.path,
    required this.textOffset,
  });

  final int blockIndex;
  final PathInBlock path;
  final int textOffset;

  @override
  int compareTo(DocumentPosition other) {
    final blockComparison = blockIndex.compareTo(other.blockIndex);
    if (blockComparison != 0) {
      return blockComparison;
    }
    final pathComparison = path.compareTo(other.path);
    if (pathComparison != 0) {
      return pathComparison;
    }
    return textOffset.compareTo(other.textOffset);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DocumentPosition &&
        other.blockIndex == blockIndex &&
        other.path == path &&
        other.textOffset == textOffset;
  }

  @override
  int get hashCode => Object.hash(blockIndex, path, textOffset);
}

@immutable
class DocumentSelection {
  const DocumentSelection({
    required this.base,
    required this.extent,
  });

  final DocumentPosition base;
  final DocumentPosition extent;

  DocumentRange get normalizedRange {
    if (base.compareTo(extent) <= 0) {
      return DocumentRange(start: base, end: extent);
    }
    return DocumentRange(start: extent, end: base);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DocumentSelection &&
        other.base == base &&
        other.extent == extent;
  }

  @override
  int get hashCode => Object.hash(base, extent);
}

@immutable
class DocumentRange {
  const DocumentRange({
    required this.start,
    required this.end,
  });

  final DocumentPosition start;
  final DocumentPosition end;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DocumentRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

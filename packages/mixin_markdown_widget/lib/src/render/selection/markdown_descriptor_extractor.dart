import 'package:flutter/material.dart';

import '../../clipboard/plain_text_serializer.dart';
import '../../core/document.dart';
import '../../widgets/markdown_theme.dart';
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
  });

  final MarkdownThemeData theme;
  final MarkdownPlainTextSerializer plainTextSerializer;
  final MarkdownInlineBuilder inlineBuilder;

  SelectableTextDescriptor buildSelectableDescriptorForBlock(
    BlockNode block, {
    int indentLevel = 0,
  }) {
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        if (MarkdownInlineBuilder.inlinesContainMath(heading.inlines)) {
          return plainTextDescriptor(
            MarkdownInlineBuilder.flattenInlineText(heading.inlines),
            theme.headingStyleForLevel(heading.level),
          );
        }
        return descriptorFromInlines(
          theme.headingStyleForLevel(heading.level),
          heading.inlines,
          textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
              heading.inlines),
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        if (MarkdownInlineBuilder.inlinesContainMath(paragraph.inlines)) {
          return plainTextDescriptor(
            MarkdownInlineBuilder.flattenInlineText(paragraph.inlines),
            theme.bodyStyle,
          );
        }
        return descriptorFromInlines(
          theme.bodyStyle,
          paragraph.inlines,
          textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
              paragraph.inlines),
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
        return plainTextDescriptor(codeBlock.code, theme.codeBlockStyle);
      case MarkdownBlockKind.table:
        return plainTextDescriptor(
          plainTextSerializer.serializeBlockText(block),
          theme.bodyStyle,
        );
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

  SelectableTextDescriptor buildImageCaptionDescriptor(ImageBlock block) {
    final caption = imageCaptionText(block);
    return plainTextDescriptor(caption, imageCaptionStyle);
  }

  SelectableTextDescriptor descriptorFromInlines(
    TextStyle style,
    List<InlineNode> inlines, {
    TextAlign textAlign = TextAlign.start,
  }) {
    return _descriptorFromSpan(
      TextSpan(
          style: style, children: inlineBuilder.buildInlineSpans(style, inlines)),
      MarkdownInlineBuilder.flattenInlineText(inlines),
      pretext: PretextTextDescriptor(
        runs: inlineBuilder.buildPretextRuns(style, inlines),
        fallbackStyle: style,
        textAlign: textAlign,
      ),
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
    return SelectableTextDescriptor(
      plainText: text,
      span: TextSpan(style: style, text: text),
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
    return SelectableTextDescriptor(
      plainText: buffer.toString(),
      span: TextSpan(children: children),
    );
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

  TextStyle get imageCaptionStyle {
    return theme.bodyStyle.copyWith(
      fontSize: 13,
      color: theme.bodyStyle.color?.withOpacity(0.72),
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

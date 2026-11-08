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

class MarkdownDescriptorCache {
  final Map<String, _CachedBlockDescriptor> _blockDescriptors =
      <String, _CachedBlockDescriptor>{};

  _CachedBlockDescriptor? _blockDescriptor(String key) =>
      _blockDescriptors[key];

  void _storeBlockDescriptor(
    String key,
    String blockId,
    BlockNode block,
    int indentLevel,
    SelectableTextDescriptor descriptor,
  ) {
    _blockDescriptors[key] = _CachedBlockDescriptor(
      blockId: blockId,
      block: block,
      indentLevel: indentLevel,
      descriptor: descriptor,
    );
  }

  void cleanup(Set<String> validIds) {
    _blockDescriptors.removeWhere(
      (_, entry) => !validIds.contains(entry.blockId),
    );
  }
}

class _CachedBlockDescriptor {
  const _CachedBlockDescriptor({
    required this.blockId,
    required this.block,
    required this.indentLevel,
    required this.descriptor,
  });

  final String blockId;
  final BlockNode block;
  final int indentLevel;
  final SelectableTextDescriptor descriptor;
}

class MarkdownDescriptorExtractor {
  MarkdownDescriptorExtractor({
    required this.theme,
    required this.plainTextSerializer,
    required this.inlineBuilder,
    required this.codeSyntaxHighlighter,
    required this.cache,
  });

  final MarkdownThemeData theme;
  final MarkdownPlainTextSerializer plainTextSerializer;
  final MarkdownInlineBuilder inlineBuilder;
  final MarkdownCodeSyntaxHighlighter codeSyntaxHighlighter;
  final MarkdownDescriptorCache cache;

  SelectableTextDescriptor buildSelectableDescriptorForBlock(
    BlockNode block, {
    int indentLevel = 0,
    TextStyle? paragraphStyle,
  }) {
    if (paragraphStyle != null) {
      return _buildSelectableDescriptorForBlock(
        block,
        indentLevel: indentLevel,
        paragraphStyle: paragraphStyle,
      );
    }

    final cacheKey = '${block.id}:$indentLevel';
    final cached = cache._blockDescriptor(cacheKey);
    if (cached != null &&
        identical(cached.block, block) &&
        cached.indentLevel == indentLevel) {
      return cached.descriptor;
    }

    final descriptor = _buildSelectableDescriptorForBlock(
      block,
      indentLevel: indentLevel,
    );
    cache._storeBlockDescriptor(
      cacheKey,
      block.id,
      block,
      indentLevel,
      descriptor,
    );
    return descriptor;
  }

  SelectableTextDescriptor _buildSelectableDescriptorForBlock(
    BlockNode block, {
    int indentLevel = 0,
    TextStyle? paragraphStyle,
  }) {
    final effectiveParagraphStyle = paragraphStyle ?? theme.bodyStyle;
    final effectiveInlineCodeStyle = _styleForContext(
      theme.inlineCodeStyle,
      paragraphStyle,
    );
    final effectiveLinkStyle = _linkStyleForContext(paragraphStyle);
    switch (block.kind) {
      case MarkdownBlockKind.heading:
        final heading = block as HeadingBlock;
        final style = _styleForContext(
          theme.headingStyleForLevel(heading.level),
          paragraphStyle,
        );
        return descriptorFromInlines(
          style,
          heading.inlines,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(heading.inlines),
          inlineCodeStyle: effectiveInlineCodeStyle,
          linkStyle: effectiveLinkStyle,
        );
      case MarkdownBlockKind.paragraph:
        final paragraph = block as ParagraphBlock;
        return descriptorFromInlines(
          effectiveParagraphStyle,
          paragraph.inlines,
          textAlign:
              MarkdownInlineBuilder.resolvedInlineTextAlign(paragraph.inlines),
          inlineCodeStyle: effectiveInlineCodeStyle,
          linkStyle: effectiveLinkStyle,
        );
      case MarkdownBlockKind.quote:
        return buildQuoteSelectableDescriptor(block as QuoteBlock);
      case MarkdownBlockKind.orderedList:
      case MarkdownBlockKind.unorderedList:
        return buildListSelectableDescriptor(
          block as ListBlock,
          indentLevel: indentLevel,
          paragraphStyle: paragraphStyle,
        );
      case MarkdownBlockKind.definitionList:
        return buildDefinitionListSelectableDescriptor(
          block as DefinitionListBlock,
        );
      case MarkdownBlockKind.footnoteList:
        return buildFootnoteListSelectableDescriptor(
          block as FootnoteListBlock,
        );
      case MarkdownBlockKind.details:
        return buildDetailsSelectableDescriptor(block as DetailsBlock);
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
        return buildTableSelectableDescriptor(
          block as TableBlock,
          textStyleContext: paragraphStyle,
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
    TextStyle? paragraphStyle,
  }) {
    final itemDescriptors = <SelectableTextDescriptor>[
      for (var index = 0; index < block.items.length; index++)
        if (_buildListItemDescriptor(
          block,
          index,
          indentLevel: indentLevel,
          paragraphStyle: paragraphStyle,
        )
            case final descriptor?)
          descriptor,
    ];
    return joinSelectableTextDescriptors(
      itemDescriptors,
      separator: '\n',
      separatorStyle: paragraphStyle ?? theme.bodyStyle,
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

  SelectableTextDescriptor buildDetailsSelectableDescriptor(
    DetailsBlock block,
  ) {
    return joinSelectableTextDescriptors(
      <SelectableTextDescriptor>[
        for (final child in detailsSelectionBlocks(block))
          buildSelectableDescriptorForBlock(child),
      ],
      separator: '\n\n',
      separatorStyle: theme.bodyStyle,
    );
  }

  /// The text of list item [index]: its marker followed by its content, or
  /// null for an empty item without a task checkbox.
  SelectableTextDescriptor? _buildListItemDescriptor(
    ListBlock block,
    int index, {
    int indentLevel = 0,
    TextStyle? paragraphStyle,
  }) {
    final effectiveParagraphStyle = paragraphStyle ?? theme.bodyStyle;
    final prefix = listItemPrefixText(
      block,
      index,
      indentLevel: indentLevel,
    );
    final contentDescriptor = buildListItemSelectableDescriptor(
      block.items[index],
      indentLevel: indentLevel + 1,
      paragraphStyle: paragraphStyle,
    );
    if (contentDescriptor.isEmpty && block.items[index].taskState == null) {
      return null;
    }
    if (contentDescriptor.isEmpty) {
      return plainTextDescriptor(prefix.trimRight(), effectiveParagraphStyle);
    }
    return prefixSelectableTextDescriptor(
      contentDescriptor,
      firstPrefix: prefix,
      continuationPrefix: ' ' * prefix.length,
      style: effectiveParagraphStyle,
    );
  }

  SelectableTextDescriptor buildListItemSelectableDescriptor(
    ListItemNode item, {
    required int indentLevel,
    TextStyle? paragraphStyle,
  }) {
    final childDescriptors = <SelectableTextDescriptor>[];
    for (final child in item.children) {
      final descriptor = buildSelectableDescriptorForBlock(
        child,
        indentLevel: indentLevel,
        paragraphStyle: paragraphStyle,
      );
      if (!descriptor.isEmpty) {
        childDescriptors.add(descriptor);
      }
    }
    return joinSelectableTextDescriptors(
      childDescriptors,
      separator: '\n',
      separatorStyle: paragraphStyle ?? theme.bodyStyle,
    );
  }

  SelectableTextDescriptor buildQuoteSelectableDescriptor(QuoteBlock block) {
    final childDescriptors = <SelectableTextDescriptor>[];
    for (final child in block.children) {
      final descriptor = buildSelectableDescriptorForBlock(
        child,
        paragraphStyle: theme.quoteStyle,
      );
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

  TextStyle _styleForContext(TextStyle style, TextStyle? textStyleContext) {
    if (textStyleContext == null) {
      return style;
    }
    final bodyFontSize = theme.bodyStyle.fontSize;
    final contextFontSize = textStyleContext.fontSize;
    final styleFontSize = style.fontSize;
    final scaledFontSize =
        bodyFontSize == null || contextFontSize == null || styleFontSize == null
            ? styleFontSize ?? contextFontSize
            : styleFontSize * contextFontSize / bodyFontSize;
    return style.copyWith(
      color: textStyleContext.color,
      fontSize: scaledFontSize,
      fontStyle: textStyleContext.fontStyle,
    );
  }

  TextStyle? _linkStyleForContext(TextStyle? textStyleContext) {
    if (textStyleContext == null) {
      return null;
    }
    final linkColor = theme.linkStyle.color;
    return _styleForContext(theme.linkStyle, textStyleContext).copyWith(
      color: linkColor,
      decoration: theme.linkStyle.decoration,
      decorationColor: theme.linkStyle.decorationColor ?? linkColor,
    );
  }

  SelectableTextDescriptor buildImageCaptionDescriptor(ImageBlock block) {
    final caption = imageCaptionText(block);
    return plainTextDescriptor(caption, imageCaptionStyle);
  }

  SelectableTextDescriptor buildTableSelectableDescriptor(
    TableBlock block, {
    TextStyle? textStyleContext,
  }) {
    final bodyStyle = _styleForContext(theme.bodyStyle, textStyleContext);
    final tableHeaderStyle = _styleForContext(
      theme.tableHeaderStyle,
      textStyleContext,
    );
    final inlineCodeStyle = _styleForContext(
      theme.inlineCodeStyle,
      textStyleContext,
    );
    final linkStyle = _linkStyleForContext(textStyleContext);
    final rowDescriptors = <SelectableTextDescriptor>[];
    for (final row in block.rows) {
      final cellDescriptors = <SelectableTextDescriptor>[];
      for (final cell in row.cells) {
        cellDescriptors.add(descriptorFromInlines(
          row.isHeader ? tableHeaderStyle : bodyStyle,
          cell.inlines,
          textAlign: MarkdownInlineBuilder.resolvedInlineTextAlign(
            cell.inlines,
          ),
          inlineCodeStyle: inlineCodeStyle,
          linkStyle: linkStyle,
        ));
      }
      rowDescriptors.add(
        joinSelectableTextDescriptors(
          cellDescriptors,
          separator: '\t',
          separatorStyle: row.isHeader ? tableHeaderStyle : bodyStyle,
        ),
      );
    }
    return joinSelectableTextDescriptors(
      rowDescriptors,
      separator: '\n',
      separatorStyle: bodyStyle,
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
    TextStyle? inlineCodeStyle,
    TextStyle? linkStyle,
  }) {
    final runs = inlineBuilder.buildPretextRuns(
      style,
      inlines,
      inlineCodeStyle: inlineCodeStyle,
      linkStyle: linkStyle,
    );
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

  static List<BlockNode> detailsSelectionBlocks(DetailsBlock block) {
    return <BlockNode>[
      ParagraphBlock(id: '${block.id}:summary', inlines: block.summary),
      ...block.children,
    ];
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

import 'package:markdown/markdown.dart' as md;

import '../core/document.dart';

class MarkdownDocumentParser {
  const MarkdownDocumentParser();

  MarkdownDocument parse(String source, {int version = 0}) {
    final normalizedSource = source.replaceAll('\r\n', '\n');
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      encodeHtml: false,
    );
    final nodes = document.parseLines(normalizedSource.split('\n'));
    final builder = _MarkdownAstBuilder();
    final blocks = builder.buildBlocks(nodes);
    return MarkdownDocument(
      blocks: List<BlockNode>.unmodifiable(blocks),
      sourceText: normalizedSource,
      version: version,
    );
  }
}

class _MarkdownAstBuilder {
  final Map<MarkdownBlockKind, int> _kindCounters = <MarkdownBlockKind, int>{};

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
        );
      case 'p':
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
  }

  List<ListItemNode> _buildListItems(md.Element listElement) {
    final items = <ListItemNode>[];
    for (final child in listElement.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'li') {
        continue;
      }
      final children = buildBlocks(child.children ?? const <md.Node>[]);
      if (children.isEmpty) {
        final inlineChildren = _buildInlines(child.children);
        if (inlineChildren.isNotEmpty) {
          items.add(
            ListItemNode(
              children: <BlockNode>[
                ParagraphBlock(
                  id: _nextId(MarkdownBlockKind.paragraph, child.textContent),
                  inlines: inlineChildren,
                ),
              ],
            ),
          );
        }
        continue;
      }
      items.add(ListItemNode(children: List<BlockNode>.unmodifiable(children)));
    }
    return items;
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

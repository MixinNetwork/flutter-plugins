import 'package:markdown/markdown.dart' as md;

List<md.BlockSyntax> buildMarkdownBlockSyntaxes() {
  return <md.BlockSyntax>[
    const md.FencedCodeBlockSyntax(),
    const md.HeaderWithIdSyntax(),
    const md.SetextHeaderWithIdSyntax(),
    const md.TableSyntax(),
    const md.UnorderedListWithCheckboxSyntax(),
    const md.OrderedListWithCheckboxSyntax(),
    const md.FootnoteDefSyntax(),
    const MarkdownDefinitionListSyntax(),
  ];
}

List<md.InlineSyntax> buildMarkdownInlineSyntaxes() {
  return <md.InlineSyntax>[
    MarkdownInlineHtmlTagSyntax(),
    MarkdownHighlightSyntax(),
    MarkdownSubscriptSyntax(),
    MarkdownSuperscriptSyntax(),
    MarkdownDoubleTildeStrikethroughSyntax(),
    md.EmojiSyntax(),
    md.ColorSwatchSyntax(),
    md.AutolinkExtensionSyntax(),
    md.InlineHtmlSyntax(),
  ];
}

class MarkdownDefinitionListSyntax extends md.BlockSyntax {
  const MarkdownDefinitionListSyntax();

  static final RegExp _definitionPattern = RegExp(r'^\s{0,3}:\s?(.*)$');
  static final RegExp _continuationPattern = RegExp(r'^(?: {2,}|\t)(.*)$');
  static final RegExp _blankPattern = RegExp(r'^\s*$');

  @override
  RegExp get pattern => _definitionPattern;

  @override
  bool canParse(md.BlockParser parser) {
    if (parser.current.isBlankLine ||
        _leadingIndent(parser.current.content) > 3) {
      return false;
    }
    final next = parser.next;
    return next != null && _definitionPattern.hasMatch(next.content);
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final children = <md.Node>[];

    while (!parser.isDone) {
      final termLine = parser.current.content.trimRight();
      final next = parser.next;
      if (termLine.trim().isEmpty ||
          next == null ||
          !_definitionPattern.hasMatch(next.content)) {
        break;
      }

      children.add(
          md.Element('dt', <md.Node>[md.UnparsedContent(termLine.trim())]));
      parser.advance();

      while (!parser.isDone &&
          _definitionPattern.hasMatch(parser.current.content)) {
        final lines = _parseDefinitionLines(parser);
        final definitionChildren = md.BlockParser(lines, parser.document)
            .parseLines(parentSyntax: this, disabledSetextHeading: true);
        children.add(md.Element('dd', definitionChildren));
      }

      if (parser.isDone) {
        break;
      }

      if (_blankPattern.hasMatch(parser.current.content)) {
        final nextTerm = parser.peek(1);
        final nextDefinition = parser.peek(2);
        if (nextTerm != null &&
            nextDefinition != null &&
            nextTerm.content.trim().isNotEmpty &&
            _definitionPattern.hasMatch(nextDefinition.content)) {
          parser.advance();
          continue;
        }
        break;
      }

      final nextDefinition = parser.next;
      if (nextDefinition == null ||
          !_definitionPattern.hasMatch(nextDefinition.content)) {
        break;
      }
    }

    if (children.isEmpty) {
      return null;
    }
    return md.Element('dl', children);
  }

  List<md.Line> _parseDefinitionLines(md.BlockParser parser) {
    final match = _definitionPattern.firstMatch(parser.current.content)!;
    final lines = <md.Line>[md.Line(match.group(1) ?? '')];
    parser.advance();

    while (!parser.isDone) {
      final current = parser.current.content;
      if (_definitionPattern.hasMatch(current)) {
        break;
      }

      if (_blankPattern.hasMatch(current)) {
        final next = parser.peek(1);
        if (next != null && _continuationPattern.hasMatch(next.content)) {
          lines.add(parser.current);
          parser.advance();
          continue;
        }
        break;
      }

      final continuation = _continuationPattern.firstMatch(current);
      if (continuation != null) {
        lines.add(md.Line(continuation.group(1) ?? ''));
        parser.advance();
        continue;
      }

      final next = parser.next;
      if (next != null && _definitionPattern.hasMatch(next.content)) {
        break;
      }

      lines.add(md.Line(current));
      parser.advance();
    }

    return lines;
  }

  int _leadingIndent(String line) {
    var indent = 0;
    while (indent < line.length && line.codeUnitAt(indent) == 0x20) {
      indent += 1;
    }
    return indent;
  }
}

class MarkdownInlineHtmlTagSyntax extends md.InlineSyntax {
  MarkdownInlineHtmlTagSyntax() : super(r'<', startCharacter: 0x3C);

  static final RegExp _lineBreakPattern = RegExp(
    r'^<br\s*/?>',
    caseSensitive: false,
  );
  static final RegExp _pairedTagPattern = RegExp(
    r'^<(em|strong|del|mark|sub|sup|code)>(.*?)</\1>',
    caseSensitive: false,
  );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    startMatchPos ??= parser.pos;
    if (parser.source.codeUnitAt(startMatchPos) != 0x3C) {
      return false;
    }

    final source = parser.source.substring(startMatchPos);
    final lineBreakMatch = _lineBreakPattern.firstMatch(source);
    if (lineBreakMatch != null) {
      parser.writeText();
      parser.addNode(md.Element.empty('br'));
      parser.consume(lineBreakMatch.group(0)!.length);
      return true;
    }

    final pairMatch = _pairedTagPattern.firstMatch(source);
    if (pairMatch == null) {
      return false;
    }

    final tag = pairMatch.group(1)!.toLowerCase();
    final content = pairMatch.group(2) ?? '';
    parser.writeText();
    parser.addNode(
      md.Element(
        tag,
        tag == 'code'
            ? <md.Node>[md.Text(content)]
            : parser.document.parseInline(content),
      ),
    );
    parser.consume(pairMatch.group(0)!.length);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    throw UnimplementedError('MarkdownInlineHtmlTagSyntax overrides tryMatch.');
  }
}

class MarkdownDoubleTildeStrikethroughSyntax extends md.DelimiterSyntax {
  MarkdownDoubleTildeStrikethroughSyntax()
      : super(
          '~+',
          requiresDelimiterRun: true,
          allowIntraWord: true,
          startCharacter: 0x7E,
          tags: <md.DelimiterTag>[md.DelimiterTag('del', 2)],
        );
}

class MarkdownHighlightSyntax extends _DelimitedInlineSyntax {
  MarkdownHighlightSyntax() : super(delimiter: '==', tag: 'mark');
}

class MarkdownSubscriptSyntax extends _DelimitedInlineSyntax {
  MarkdownSubscriptSyntax() : super(delimiter: '~', tag: 'sub');

  @override
  bool isValidContent(String content) {
    return super.isValidContent(content) && !_hasBoundaryWhitespace(content);
  }
}

class MarkdownSuperscriptSyntax extends _DelimitedInlineSyntax {
  MarkdownSuperscriptSyntax() : super(delimiter: '^', tag: 'sup');

  @override
  bool isValidContent(String content) {
    return super.isValidContent(content) && !_hasBoundaryWhitespace(content);
  }

  @override
  bool canStartMatch(String source, int index) {
    if (!super.canStartMatch(source, index)) {
      return false;
    }
    final previousIndex = index - 1;
    return previousIndex < 0 || source.codeUnitAt(previousIndex) != 0x5B;
  }
}

bool _hasBoundaryWhitespace(String content) {
  return content.isNotEmpty &&
      (RegExp(r'^\s').hasMatch(content) || RegExp(r'\s$').hasMatch(content));
}

abstract class _DelimitedInlineSyntax extends md.InlineSyntax {
  _DelimitedInlineSyntax({
    required this.delimiter,
    required this.tag,
  }) : super(RegExp.escape(delimiter), startCharacter: delimiter.codeUnitAt(0));

  final String delimiter;
  final String tag;

  bool isValidContent(String content) {
    return content.isNotEmpty && !content.contains('\n');
  }

  bool canStartMatch(String source, int index) => true;

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    startMatchPos ??= parser.pos;
    if (!_isDelimiterAt(parser.source, startMatchPos) ||
        !canStartMatch(parser.source, startMatchPos)) {
      return false;
    }

    final start = startMatchPos + delimiter.length;
    final end = _findClosingDelimiter(parser.source, start);
    if (end == null) {
      return false;
    }

    final content = parser.source.substring(start, end);
    if (!isValidContent(content)) {
      return false;
    }

    parser.writeText();
    parser.addNode(md.Element(tag, parser.document.parseInline(content)));
    parser.consume(end + delimiter.length - startMatchPos);
    return true;
  }

  int? _findClosingDelimiter(String source, int start) {
    var index = start;
    while (index <= source.length - delimiter.length) {
      if (source.codeUnitAt(index) == 0x5C) {
        index += 2;
        continue;
      }
      if (_isDelimiterAt(source, index)) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  bool _isDelimiterAt(String source, int index) {
    if (index < 0 || index + delimiter.length > source.length) {
      return false;
    }
    if (!source.startsWith(delimiter, index)) {
      return false;
    }

    final delimiterCodeUnit = delimiter.codeUnitAt(0);
    final beforeIndex = index - 1;
    final afterIndex = index + delimiter.length;
    if (delimiter.length == 1) {
      if (beforeIndex >= 0 &&
          source.codeUnitAt(beforeIndex) == delimiterCodeUnit) {
        return false;
      }
      if (afterIndex < source.length &&
          source.codeUnitAt(afterIndex) == delimiterCodeUnit) {
        return false;
      }
      return true;
    }

    if (beforeIndex >= 0 &&
        source.codeUnitAt(beforeIndex) == delimiterCodeUnit) {
      return false;
    }
    if (afterIndex < source.length &&
        source.codeUnitAt(afterIndex) == delimiterCodeUnit) {
      return false;
    }
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    throw UnimplementedError('_DelimitedInlineSyntax overrides tryMatch.');
  }
}

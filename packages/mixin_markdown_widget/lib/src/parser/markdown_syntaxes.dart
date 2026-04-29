import 'package:markdown/markdown.dart' as md;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

List<md.BlockSyntax> buildMarkdownBlockSyntaxes() {
  return <md.BlockSyntax>[
    const md.FencedCodeBlockSyntax(),
    const MarkdownMathBlockSyntax(),
    const MarkdownHtmlBlockSyntax(),
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
    MarkdownDollarMathSyntax(),
    MarkdownBackslashMathSyntax(),
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

class MarkdownHtmlBlockSyntax extends md.BlockSyntax {
  const MarkdownHtmlBlockSyntax();

  static const Set<String> _supportedBlockTags = <String>{
    'details',
    'summary',
    'br',
    'p',
    'blockquote',
    'ul',
    'ol',
    'li',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };

  static final RegExp _openingPattern = RegExp(
    r'^\s{0,3}<([A-Za-z][A-Za-z0-9-]*)(?:\s+[^>]*)?>',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _openingPattern;

  @override
  bool canParse(md.BlockParser parser) {
    final match = _openingPattern.firstMatch(parser.current.content);
    if (match == null) {
      return false;
    }
    return _supportedBlockTags.contains(match.group(1)!.toLowerCase());
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final match = _openingPattern.firstMatch(firstLine)!;
    final tag = match.group(1)!.toLowerCase();
    final lines = <String>[];

    if (_lineContainsClosingTag(firstLine, tag) || _isVoidLine(firstLine)) {
      lines.add(firstLine);
      parser.advance();
    } else {
      var depth = 0;
      while (!parser.isDone) {
        final line = parser.current.content;
        lines.add(line);
        depth += _openingTagCount(line, tag);
        depth -= _closingTagCount(line, tag);
        parser.advance();
        if (depth <= 0 || parser.isDone) {
          break;
        }
      }
    }

    final source = lines.join('\n');
    final nodes = tag == 'details'
        ? _convertDetailsFragment(source)
        : _convertHtmlFragment(source);
    if (nodes.isEmpty) {
      return null;
    }
    if (nodes.length == 1) {
      return nodes.single;
    }
    return md.Element('html-fragment', nodes);
  }

  bool _isVoidLine(String line) {
    return RegExp(r'<(?:br|img)(?:\s+[^>]*)?\s*/?>', caseSensitive: false)
        .hasMatch(line);
  }

  bool _lineContainsClosingTag(String line, String tag) {
    return RegExp('</$tag\\s*>', caseSensitive: false).hasMatch(line);
  }

  int _openingTagCount(String line, String tag) {
    return RegExp('<$tag(?:\\s+[^>]*)?>', caseSensitive: false)
        .allMatches(line)
        .length;
  }

  int _closingTagCount(String line, String tag) {
    return RegExp('</$tag\\s*>', caseSensitive: false).allMatches(line).length;
  }

  List<md.Node> _convertHtmlFragment(String source) {
    final fragment = html_parser.parseFragment(source);
    return fragment.nodes.expand(_convertHtmlNode).toList(growable: false);
  }

  List<md.Node> _convertDetailsFragment(String source) {
    final match = RegExp(
      r'^\s{0,3}<details([^>]*)>([\s\S]*)</details>\s*$',
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) {
      return _convertHtmlFragment(source);
    }

    final attributesSource = match.group(1) ?? '';
    var bodySource = match.group(2) ?? '';
    final summaryMatch = RegExp(
      r'<summary(?:\s+[^>]*)?>([\s\S]*?)</summary>',
      caseSensitive: false,
    ).firstMatch(bodySource);

    md.Element? summary;
    if (summaryMatch != null) {
      final summaryNodes = _convertHtmlFragment(summaryMatch.group(0)!);
      for (final node in summaryNodes) {
        if (node is md.Element && node.tag == 'summary') {
          summary = node;
          break;
        }
      }
      bodySource = bodySource.replaceRange(
        summaryMatch.start,
        summaryMatch.end,
        '',
      );
    }

    final details = md.Element(
      'details',
      <md.Node>[
        if (summary != null) summary,
        ..._parseMarkdownFragment(bodySource),
      ],
    );
    if (RegExp(r'(^|\s)open(?:\s|=|$)', caseSensitive: false)
        .hasMatch(attributesSource)) {
      details.attributes['open'] = '';
    }
    return <md.Node>[details];
  }

  List<md.Node> _parseMarkdownFragment(String source) {
    final normalizedSource = _normalizeMarkdownFragmentSource(source);
    if (normalizedSource.isEmpty) {
      return const <md.Node>[];
    }
    final document = md.Document(
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: buildMarkdownBlockSyntaxes(),
      inlineSyntaxes: buildMarkdownInlineSyntaxes(),
      encodeHtml: false,
    );
    return document.parseLines(normalizedSource.split('\n'));
  }

  String _normalizeMarkdownFragmentSource(String source) {
    return _trimSurroundingBlankLines(source).replaceAllMapped(
      RegExp(r'([^\n])\n([ \t]*(?:[-+*]|\d+[.)])\s+)', multiLine: true),
      (match) => '${match.group(1)}\n\n${match.group(2)}',
    );
  }

  String _trimSurroundingBlankLines(String source) {
    final lines = source.split('\n');
    var start = 0;
    var end = lines.length;
    while (start < end && lines[start].trim().isEmpty) {
      start += 1;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end -= 1;
    }
    return lines.sublist(start, end).join('\n');
  }

  bool _shouldPreserveHtmlWhitespaceText(String text) {
    if (text.isEmpty || text.trim().isNotEmpty) {
      return false;
    }
    if (text.contains('\n') || text.contains('\r')) {
      return false;
    }
    return text.contains(RegExp(r'[ \t]'));
  }

  Iterable<md.Node> _convertHtmlNode(html_dom.Node node) sync* {
    if (node is html_dom.Text) {
      final originalText = node.text;
      final text = _normalizeHtmlText(originalText);
      if (text.trim().isNotEmpty) {
        yield md.Text(text);
      } else if (_shouldPreserveHtmlWhitespaceText(originalText)) {
        yield md.Text(' ');
      }
      return;
    }
    if (node is! html_dom.Element) {
      return;
    }

    final tag = node.localName?.toLowerCase();
    if (tag == null || tag == 'script' || tag == 'style') {
      return;
    }
    if (tag == 'html' || tag == 'head' || tag == 'body') {
      for (final child in node.nodes) {
        yield* _convertHtmlNode(child);
      }
      return;
    }

    if (tag == 'br') {
      yield md.Element.empty('br');
      return;
    }
    if (tag == 'img') {
      yield _elementFromHtml(node, 'img', const <md.Node>[]);
      return;
    }

    final children = <md.Node>[
      for (final child in node.nodes) ..._convertHtmlNode(child),
    ];
    if (!_supportedBlockTags.contains(tag) &&
        !MarkdownInlineHtmlTagSyntax.supportedTags.contains(tag)) {
      yield* children;
      return;
    }
    yield _elementFromHtml(node, tag, children);
  }

  md.Element _elementFromHtml(
    html_dom.Element node,
    String tag,
    List<md.Node> children,
  ) {
    final element =
        children.isEmpty ? md.Element.empty(tag) : md.Element(tag, children);
    for (final entry in node.attributes.entries) {
      element.attributes[entry.key.toString().toLowerCase()] = entry.value;
    }
    return element;
  }

  String _normalizeHtmlText(String text) {
    return text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
  }
}

class MarkdownMathBlockSyntax extends md.BlockSyntax {
  const MarkdownMathBlockSyntax();

  static final RegExp _openingPattern = RegExp(r'^\s{0,3}(\$\$|\\\[)\s*$');

  @override
  RegExp get pattern => _openingPattern;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _openingPattern.firstMatch(parser.current.content)!;
    final opening = match.group(1)!;
    final closing = opening == r'\[' ? r'\]' : r'$$';
    final lines = <String>[];

    parser.advance();
    while (!parser.isDone) {
      if (_isClosingFence(parser.current.content, closing)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    final math = md.Element.text('math', _trimMathContent(lines.join('\n')))
      ..attributes['display'] = 'true';
    return md.Element('p', <md.Node>[math]);
  }

  bool _isClosingFence(String line, String closing) {
    return RegExp(r'^\s{0,3}' + RegExp.escape(closing) + r'\s*$')
        .hasMatch(line);
  }
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

  static const Set<String> supportedTags = <String>{
    'a',
    'b',
    'i',
    's',
    'span',
    'small',
    'kbd',
    'u',
    'ins',
    'em',
    'strong',
    'del',
    'mark',
    'sub',
    'sup',
    'code',
  };
  static final RegExp _lineBreakPattern = RegExp(
    r'^<br(?:\s+[^>]*)?\s*/?>',
    caseSensitive: false,
  );
  static final RegExp _pairedTagPattern = RegExp(
    r'^<([A-Za-z][A-Za-z0-9-]*)(\s+[^>]*)?>(.*?)</\1>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _attributePattern = RegExp(
    r"""([A-Za-z_:][A-Za-z0-9_:\-.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>/=`]+)))?""",
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
    if (!supportedTags.contains(tag)) {
      return false;
    }
    final rawAttributes = pairMatch.group(2);
    final content = pairMatch.group(3) ?? '';
    parser.writeText();
    final element = md.Element(
      tag,
      tag == 'code'
          ? <md.Node>[md.Text(content)]
          : parser.document.parseInline(content),
    );
    if (rawAttributes != null && rawAttributes.trim().isNotEmpty) {
      element.attributes.addAll(_parseAttributes(rawAttributes));
    }
    parser.addNode(element);
    parser.consume(pairMatch.group(0)!.length);
    return true;
  }

  Map<String, String> _parseAttributes(String source) {
    final attributes = <String, String>{};
    for (final match in _attributePattern.allMatches(source)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) {
        continue;
      }
      final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      attributes[name.toLowerCase()] = value;
    }
    return attributes;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    throw UnimplementedError('MarkdownInlineHtmlTagSyntax overrides tryMatch.');
  }
}

class MarkdownDollarMathSyntax extends md.InlineSyntax {
  MarkdownDollarMathSyntax() : super(r'\$', startCharacter: 0x24);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    startMatchPos ??= parser.pos;
    if (parser.source.codeUnitAt(startMatchPos) != 0x24) {
      return false;
    }

    final isDisplay = startMatchPos + 1 < parser.source.length &&
        parser.source.codeUnitAt(startMatchPos + 1) == 0x24;
    final delimiter = isDisplay ? r'$$' : r'$';
    final match = _extractDelimitedMath(
      parser.source,
      startMatchPos,
      openDelimiter: delimiter,
      closeDelimiter: delimiter,
      allowBoundaryWhitespace: isDisplay,
    );
    if (match == null) {
      return false;
    }

    parser.writeText();
    parser.addNode(
      md.Element.text('math', match.content)
        ..attributes['display'] = '$isDisplay',
    );
    parser.consume(match.sourceLength);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    throw UnimplementedError('MarkdownDollarMathSyntax overrides tryMatch.');
  }
}

class MarkdownBackslashMathSyntax extends md.InlineSyntax {
  MarkdownBackslashMathSyntax() : super(r'\\', startCharacter: 0x5C);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    startMatchPos ??= parser.pos;
    if (parser.source.codeUnitAt(startMatchPos) != 0x5C ||
        startMatchPos + 1 >= parser.source.length) {
      return false;
    }

    final next = parser.source.codeUnitAt(startMatchPos + 1);
    final isInline = next == 0x28;
    final isDisplay = next == 0x5B;
    if (!isInline && !isDisplay) {
      return false;
    }

    final openDelimiter = isInline ? r'\(' : r'\[';
    final closeDelimiter = isInline ? r'\)' : r'\]';
    final match = _extractDelimitedMath(
      parser.source,
      startMatchPos,
      openDelimiter: openDelimiter,
      closeDelimiter: closeDelimiter,
      allowBoundaryWhitespace: true,
      trimBoundaryWhitespace: isInline,
    );
    if (match == null) {
      return false;
    }

    parser.writeText();
    parser.addNode(
      md.Element.text('math', match.content)
        ..attributes['display'] = '${!isInline}',
    );
    parser.consume(match.sourceLength);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    throw UnimplementedError('MarkdownBackslashMathSyntax overrides tryMatch.');
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

_DelimitedMathMatch? _extractDelimitedMath(
  String source,
  int start, {
  required String openDelimiter,
  required String closeDelimiter,
  required bool allowBoundaryWhitespace,
  bool trimBoundaryWhitespace = false,
}) {
  final contentStart = start + openDelimiter.length;
  if (contentStart >= source.length) {
    return null;
  }

  if (!allowBoundaryWhitespace &&
      RegExp(r'\s').hasMatch(source[contentStart])) {
    return null;
  }

  var searchIndex = contentStart;
  while (searchIndex < source.length) {
    final closingIndex = source.indexOf(closeDelimiter, searchIndex);
    if (closingIndex < 0) {
      return null;
    }
    if (_isEscapedCharacter(source, closingIndex)) {
      searchIndex = closingIndex + 1;
      continue;
    }

    final content = source.substring(contentStart, closingIndex);
    if (content.isEmpty) {
      return null;
    }
    if (!allowBoundaryWhitespace &&
        (RegExp(r'^\s').hasMatch(content) ||
            RegExp(r'\s$').hasMatch(content))) {
      searchIndex = closingIndex + 1;
      continue;
    }
    final normalized = _trimMathContent(content);
    return _DelimitedMathMatch(
      content: trimBoundaryWhitespace ? normalized.trim() : normalized,
      sourceLength: closingIndex + closeDelimiter.length - start,
    );
  }

  return null;
}

class _DelimitedMathMatch {
  const _DelimitedMathMatch({
    required this.content,
    required this.sourceLength,
  });

  final String content;
  final int sourceLength;
}

String _trimMathContent(String content) {
  return content
      .replaceFirst(RegExp(r'^\n+'), '')
      .replaceFirst(RegExp(r'\n+$'), '');
}

bool _isEscapedCharacter(String source, int index) {
  var slashCount = 0;
  var cursor = index - 1;
  while (cursor >= 0 && source.codeUnitAt(cursor) == 0x5C) {
    slashCount += 1;
    cursor -= 1;
  }
  return slashCount.isOdd;
}

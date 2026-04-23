import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/builder/markdown_inline_builder.dart';
import 'package:mixin_markdown_widget/src/render/local_image_provider_io.dart';
import 'package:mixin_markdown_widget/src/render/markdown_block_widgets.dart';
import 'package:mixin_markdown_widget/src/render/pretext_text_block.dart';
import 'package:mixin_markdown_widget/src/render/selectable_block.dart';
import 'package:mixin_markdown_widget/src/selection/structured_block_selection.dart';

int _countStyledDescendantSpans(InlineSpan span, TextStyle? rootStyle) {
  if (span is! TextSpan) {
    return 0;
  }

  var count = 0;
  final style = span.style;
  if (style != null && style != rootStyle) {
    count += 1;
  }

  final children = span.children;
  if (children == null) {
    return count;
  }

  for (final child in children) {
    count += _countStyledDescendantSpans(child, rootStyle);
  }
  return count;
}

Iterable<WidgetSpan> _collectWidgetSpans(InlineSpan span) sync* {
  if (span is WidgetSpan) {
    yield span;
    return;
  }
  if (span is! TextSpan) {
    return;
  }
  final children = span.children;
  if (children == null) {
    return;
  }
  for (final child in children) {
    yield* _collectWidgetSpans(child);
  }
}

Iterable<InlineNode> _flattenInlineNodes(List<InlineNode> inlines) sync* {
  for (final inline in inlines) {
    yield inline;
    switch (inline.kind) {
      case MarkdownInlineKind.emphasis:
        yield* _flattenInlineNodes((inline as EmphasisInline).children);
        break;
      case MarkdownInlineKind.strong:
        yield* _flattenInlineNodes((inline as StrongInline).children);
        break;
      case MarkdownInlineKind.strikethrough:
        yield* _flattenInlineNodes((inline as StrikethroughInline).children);
        break;
      case MarkdownInlineKind.highlight:
        yield* _flattenInlineNodes((inline as HighlightInline).children);
        break;
      case MarkdownInlineKind.subscript:
        yield* _flattenInlineNodes((inline as SubscriptInline).children);
        break;
      case MarkdownInlineKind.superscript:
        yield* _flattenInlineNodes((inline as SuperscriptInline).children);
        break;
      case MarkdownInlineKind.link:
        yield* _flattenInlineNodes((inline as LinkInline).children);
        break;
      case MarkdownInlineKind.text:
      case MarkdownInlineKind.math:
      case MarkdownInlineKind.inlineCode:
      case MarkdownInlineKind.softBreak:
      case MarkdownInlineKind.hardBreak:
      case MarkdownInlineKind.image:
        break;
    }
  }
}

String _inlinePlainText(List<InlineNode> inlines) {
  final buffer = StringBuffer();
  for (final inline in inlines) {
    switch (inline.kind) {
      case MarkdownInlineKind.text:
        buffer.write((inline as TextInline).text);
        break;
      case MarkdownInlineKind.emphasis:
        buffer.write(_inlinePlainText((inline as EmphasisInline).children));
        break;
      case MarkdownInlineKind.strong:
        buffer.write(_inlinePlainText((inline as StrongInline).children));
        break;
      case MarkdownInlineKind.strikethrough:
        buffer
            .write(_inlinePlainText((inline as StrikethroughInline).children));
        break;
      case MarkdownInlineKind.highlight:
        buffer.write(_inlinePlainText((inline as HighlightInline).children));
        break;
      case MarkdownInlineKind.subscript:
        buffer.write(_inlinePlainText((inline as SubscriptInline).children));
        break;
      case MarkdownInlineKind.superscript:
        buffer.write(_inlinePlainText((inline as SuperscriptInline).children));
        break;
      case MarkdownInlineKind.link:
        buffer.write(_inlinePlainText((inline as LinkInline).children));
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
        buffer.write((inline as InlineImage).alt ?? '');
        break;
    }
  }
  return buffer.toString();
}

bool _hasMeaningfulHorizontalOverlap(Rect a, Rect b) {
  final verticalOverlap = (a.bottom <= b.top || b.bottom <= a.top) == false;
  final horizontalOverlap = (a.right < b.left || b.right < a.left) == false &&
      math.min(a.right, b.right) - math.max(a.left, b.left) > 1.0;
  return verticalOverlap && horizontalOverlap;
}

Future<void> _doubleTapAt(WidgetTester tester, Offset target) async {
  await tester.tapAt(target);
  await tester.pump();
  await tester.tapAt(target);
  await tester.pump();
}

Future<void> _tripleTapAt(WidgetTester tester, Offset target) async {
  await _doubleTapAt(tester, target);
  await tester.tapAt(target);
  await tester.pump();
}

List<Rect> _globalSelectionRectsForBlock(
  WidgetTester tester,
  Finder blockFinder, {
  required int start,
  required int end,
}) {
  final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
  final element = tester.element(blockFinder);
  final renderBox = tester.renderObject<RenderBox>(blockFinder);
  final rects = block.spec.selectionRectResolver!.call(
    element,
    renderBox.size,
    DocumentRange(
      start: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: start,
      ),
      end: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: end,
      ),
    ),
  );
  final origin = renderBox.localToGlobal(Offset.zero);
  return rects.map((rect) => rect.shift(origin)).toList(growable: false);
}

Rect _mergedRect(Iterable<Rect> rects) {
  final list = rects.toList(growable: false);
  return Rect.fromLTRB(
    list.map((rect) => rect.left).reduce(math.min),
    list.map((rect) => rect.top).reduce(math.min),
    list.map((rect) => rect.right).reduce(math.max),
    list.map((rect) => rect.bottom).reduce(math.max),
  );
}

double _tightTextHeight(String text, TextStyle style) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  final boxes = textPainter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  if (boxes.isNotEmpty) {
    return boxes.map((box) => box.bottom).reduce(math.max) -
        boxes.map((box) => box.top).reduce(math.min);
  }
  final lineMetrics = textPainter.computeLineMetrics().first;
  return lineMetrics.ascent + lineMetrics.descent;
}

Finder _decoratedInlineTextFinder() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_DecoratedInlineText',
  );
}

void main() {
  test('parses common markdown blocks into a document model', () {
    const input = '''
# Heading

Paragraph with **bold** text.

- First
- Second

| Name | Value |
| --- | ---: |
| row | 42 |

```dart
void main() {}
```
''';

    final parser = MarkdownDocumentParser();
    final document = parser.parse(input);

    expect(document.blocks, hasLength(5));
    expect(document.blocks[0], isA<HeadingBlock>());
    expect(document.blocks[1], isA<ParagraphBlock>());
    expect(document.blocks[2], isA<ListBlock>());
    expect(document.blocks[3], isA<TableBlock>());
    expect(document.blocks[4], isA<CodeBlock>());

    final list = document.blocks[2] as ListBlock;
    expect(list.items, hasLength(2));
  });

  test('serializes markdown document into predictable plain text', () {
    const input = '''
# Heading

Paragraph with [link](https://example.com).

- First
- Second

| Name | Value |
| --- | ---: |
| row | 42 |

```dart
void main() {}
```
''';

    final controller = MarkdownController(data: input);

    expect(
      controller.plainText,
      'Heading\n\n'
      'Paragraph with link (https://example.com).\n\n'
      '- First\n'
      '- Second\n\n'
      'Name\tValue\n'
      'row\t42\n\n'
      'void main() {}',
    );
  });

  test('parses extended markdown constructs into the document model', () {
    const input = '''
### Heading Title

- [x] Done
- [ ] Todo

Term
: Definition with ==mark== and H~2~O and 2^10^ and <sup>html</sup> plus https://example.com and :white_check_mark:

Reference[^note]

[^note]: Footnote body
''';

    final document = const MarkdownDocumentParser().parse(input);

    expect(document.blocks, hasLength(5));

    final heading = document.blocks[0] as HeadingBlock;
    expect(heading.anchorId, 'heading-title');

    final list = document.blocks[1] as ListBlock;
    expect(list.items[0].taskState, MarkdownTaskListItemState.checked);
    expect(list.items[1].taskState, MarkdownTaskListItemState.unchecked);

    final definitionList = document.blocks[2] as DefinitionListBlock;
    expect(definitionList.items, hasLength(1));
    final definitionParagraph =
        definitionList.items.first.definitions.first.first as ParagraphBlock;
    final definitionKinds = _flattenInlineNodes(definitionParagraph.inlines)
        .map((inline) => inline.kind)
        .toSet();
    expect(definitionKinds, contains(MarkdownInlineKind.highlight));
    expect(definitionKinds, contains(MarkdownInlineKind.subscript));
    expect(definitionKinds, contains(MarkdownInlineKind.superscript));
    expect(definitionKinds, contains(MarkdownInlineKind.link));

    final referenceParagraph = document.blocks[3] as ParagraphBlock;
    expect(
      _flattenInlineNodes(referenceParagraph.inlines)
          .map((inline) => inline.kind),
      contains(MarkdownInlineKind.superscript),
    );

    final footnotes = document.blocks[4] as FootnoteListBlock;
    expect(footnotes.items, hasLength(1));
  });

  test('strips the synthetic trailing newline from fenced code blocks', () {
    const input = '''
```dart
const value = 42;
return value;
```
''';

    final document = const MarkdownDocumentParser().parse(input);
    final codeBlock = document.blocks.single as CodeBlock;

    expect(codeBlock.code, 'const value = 42;\nreturn value;');
    expect(codeBlock.code.endsWith('\n'), isFalse);
  });

  test('parses simple inline html anchor tags into link nodes', () {
    const input = '''
💡 <a href="/MixinNetwork/flutter-plugins/new/main?filename=.github/instructions/*.instructions.md" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Add Copilot custom instructions</a> for smarter, more guided reviews. <a href="https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Learn how to get started</a>.
''';

    final document = const MarkdownDocumentParser().parse(input);
    final paragraph = document.blocks.single as ParagraphBlock;
    final links = _flattenInlineNodes(paragraph.inlines)
        .whereType<LinkInline>()
        .toList(growable: false);

    expect(links, hasLength(2));
    expect(
      links[0].destination,
      '/MixinNetwork/flutter-plugins/new/main?filename=.github/instructions/*.instructions.md',
    );
    expect(
        _inlinePlainText(links[0].children), 'Add Copilot custom instructions');
    expect(
      links[1].destination,
      'https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot',
    );
    expect(_inlinePlainText(links[1].children), 'Learn how to get started');
  });

  test('parses additional simple inline html tags into existing inline nodes',
      () {
    const input = '''
Before <b>bold</b> <i>italic</i> <s>strike</s> <kbd>cmd</kbd> <span data-x="1">span text</span> <small>small text</small> <u>underlined</u> <ins>inserted</ins> after
''';

    final document = const MarkdownDocumentParser().parse(input);
    final paragraph = document.blocks.single as ParagraphBlock;
    final flattened =
        _flattenInlineNodes(paragraph.inlines).toList(growable: false);

    expect(flattened.any((inline) => inline is StrongInline), isTrue);
    expect(flattened.any((inline) => inline is EmphasisInline), isTrue);
    expect(flattened.any((inline) => inline is StrikethroughInline), isTrue);
    expect(flattened.any((inline) => inline is InlineCode), isTrue);
    expect(
      _inlinePlainText(paragraph.inlines),
      'Before bold italic strike cmd span text small text underlined inserted after',
    );
  });

  test('does not treat footnote references as custom superscript spans', () {
    const input = '''
Here is a statement with a footnote.[^1] Another reference can be added here.[^long]

[^1]: This is a simple footnote.
[^long]: This footnote contains a longer explanation to showcase how multiple lines can be formatted in a footnote.
''';

    final document = const MarkdownDocumentParser().parse(input);
    final paragraph = document.blocks[0] as ParagraphBlock;

    expect(
      _inlinePlainText(paragraph.inlines),
      'Here is a statement with a footnote.1 Another reference can be added here.2',
    );

    final superscripts = paragraph.inlines
        .whereType<SuperscriptInline>()
        .map((inline) => _inlinePlainText(inline.children))
        .toList(growable: false);
    expect(superscripts, const <String>['1', '2']);
  });

  test('serializes task lists and definition lists predictably', () {
    const input = '''
- [x] Done
- [ ] Todo

Term
: Definition
''';

    final controller = MarkdownController(data: input);

    expect(
      controller.plainText,
      '- [x] Done\n- [ ] Todo\n\nTerm\n: Definition',
    );
  });

  test('keeps rich inline styles inside tight list items', () {
    const input = '- before **bold** [link](https://example.com) `code` after';

    final document = const MarkdownDocumentParser().parse(input);
    final list = document.blocks.single as ListBlock;
    final paragraph = list.items.single.children.single as ParagraphBlock;

    expect(paragraph.inlines.length, greaterThan(1));
    expect(
      paragraph.inlines.map((inline) => inline.kind),
      containsAll(<MarkdownInlineKind>[
        MarkdownInlineKind.strong,
        MarkdownInlineKind.link,
        MarkdownInlineKind.inlineCode,
      ]),
    );
  });

  test('parses and serializes inline and display math', () {
    const input = r'''
Inline $a^2+b^2=c^2$ and \(e^{i\pi}+1=0\).

$$
\int_0^1 x^2 dx
$$
''';

    final document = const MarkdownDocumentParser().parse(input);

    expect(document.blocks, hasLength(2));

    final paragraph = document.blocks.first as ParagraphBlock;
    final mathInlines = _flattenInlineNodes(paragraph.inlines)
        .whereType<MathInline>()
        .toList(growable: false);
    expect(mathInlines, hasLength(2));
    expect(mathInlines[0].displayStyle, isFalse);
    expect(mathInlines[0].tex, 'a^2+b^2=c^2');
    expect(mathInlines[1].displayStyle, isFalse);
    expect(mathInlines[1].tex, r'e^{i\pi}+1=0');

    final display = document.blocks[1] as ParagraphBlock;
    expect(display.inlines.single, isA<MathInline>());
    expect((display.inlines.single as MathInline).displayStyle, isTrue);
    expect((display.inlines.single as MathInline).tex, r'\int_0^1 x^2 dx');

    final controller = MarkdownController(data: input);
    expect(
      controller.plainText,
      'Inline a^2+b^2=c^2 and e^{i\\pi}+1=0.\n\n\\int_0^1 x^2 dx',
    );
  });

  test('parses backslash inline math with surrounding whitespace', () {
    const input =
        r'Quadratic formula: \( x = \frac{-b \pm \sqrt{b^2-4ac}}{2a} \).';

    final document = const MarkdownDocumentParser().parse(input);

    expect(document.blocks, hasLength(1));
    final paragraph = document.blocks.single as ParagraphBlock;
    final mathInlines = _flattenInlineNodes(paragraph.inlines)
        .whereType<MathInline>()
        .toList(growable: false);
    expect(mathInlines, hasLength(1));
    expect(mathInlines.single.displayStyle, isFalse);
    expect(
      mathInlines.single.tex,
      r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
    );

    final controller = MarkdownController(data: input);
    expect(
      controller.plainText,
      r'Quadratic formula: x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}.',
    );
  });

  test('parses standalone linked images into image blocks', () {
    const input =
        '[![alt text](https://example.com/image.png)](https://example.com/page)';

    final document = const MarkdownDocumentParser().parse(input);
    final image = document.blocks.single as ImageBlock;

    expect(image.url, 'https://example.com/image.png');
    expect(image.alt, 'alt text');
    expect(image.linkDestination, 'https://example.com/page');
  });

  test('tracks draft and committed blocks during streaming', () {
    final controller = MarkdownController(data: '# Title');

    expect(controller.streamingState.hasDraft, isFalse);
    expect(controller.streamingState.committedBlocks, hasLength(1));

    controller.appendChunk('\n\nParagraph');

    expect(controller.streamingState.hasDraft, isTrue);
    expect(controller.streamingState.committedBlocks, hasLength(1));
    expect(controller.streamingState.draftBlock, isA<ParagraphBlock>());

    controller.commitStream();

    expect(controller.streamingState.hasDraft, isFalse);
    expect(controller.streamingState.committedBlocks, hasLength(2));
  });

  test('assigns source ranges and reuses committed prefix blocks on append',
      () {
    final controller = MarkdownController(data: '# Title\n\nIntro');
    final initialHeading = controller.document.blocks.first as HeadingBlock;

    expect(initialHeading.sourceRange, isNotNull);
    expect(initialHeading.sourceRange!.start, 0);

    controller.appendChunk('\n\nParagraph');

    expect(controller.document.blocks, hasLength(3));
    expect(identical(controller.document.blocks.first, initialHeading), isTrue);
    expect(controller.document.blocks.last.sourceRange, isNotNull);
    expect(controller.document.blocks.last.sourceRange!.start, greaterThan(0));
  });

  test('documentListenable only fires on document changes', () {
    final controller = MarkdownController(data: '# Title');
    var documentNotifications = 0;
    controller.documentListenable.addListener(() {
      documentNotifications += 1;
    });

    controller.appendChunk('\n\nParagraph');
    expect(documentNotifications, 1);

    controller.commitStream();
    expect(documentNotifications, 1);
  });

  test('assigns source ranges for setext headings and indented code blocks',
      () {
    const input = 'Title\n=====\n\n    final answer = 42;\n';

    final document = const MarkdownDocumentParser().parse(input);

    expect(document.blocks, hasLength(2));
    expect(document.blocks.first, isA<HeadingBlock>());
    expect(document.blocks.last, isA<CodeBlock>());
    expect(document.blocks.first.sourceRange, isNotNull);
    expect(document.blocks.last.sourceRange, isNotNull);
    expect(
      document.blocks.last.sourceRange!.start,
      greaterThan(document.blocks.first.sourceRange!.end),
    );
  });

  test('append parsing keeps stable prefix before list tail reparsing', () {
    final controller = MarkdownController(
      data: '# Title\n\nIntro\n\n- item\n  continuation',
    );
    final initialHeading = controller.document.blocks[0];
    final initialParagraph = controller.document.blocks[1];

    controller.appendChunk('\n\n    code tail');

    expect(identical(controller.document.blocks[0], initialHeading), isTrue);
    expect(identical(controller.document.blocks[1], initialParagraph), isTrue);
  });

  test('serializes a selected range across multiple blocks', () {
    const input = '''
# Heading

Paragraph body

- Item one
- Item two
''';

    final controller = MarkdownController(data: input);
    const serializer = MarkdownPlainTextSerializer();

    final text = serializer.serializeSelection(
      controller.document,
      const DocumentSelection(
        base: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 2,
        ),
        extent: DocumentPosition(
          blockIndex: 2,
          path: PathInBlock(<int>[0]),
          textOffset: 9,
        ),
      ),
    );

    expect(text, 'ading\n\nParagraph body\n\n- Item on');
  });

  test('serializes visible selection offsets correctly around links', () {
    const input = 'Paragraph with [link](https://example.com) tail';

    final controller = MarkdownController(data: input);
    const serializer = MarkdownPlainTextSerializer();
    final paragraph = controller.document.blocks.single as ParagraphBlock;
    final visibleText = _inlinePlainText(paragraph.inlines);
    final start = visibleText.indexOf('link');
    final end = visibleText.length;

    final text = serializer.serializeSelection(
      controller.document,
      const DocumentSelection(
        base: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 15,
        ),
        extent: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 24,
        ),
      ),
    );

    expect(start, 15);
    expect(end, 24);
    expect(text, 'link tail');
  });

  test('select all still serializes full link destinations', () {
    final controller = MarkdownController(
      data: 'Paragraph with [link](https://example.com) tail',
    );
    final selectionController = MarkdownSelectionController()
      ..attachDocument(controller.document)
      ..selectAll();

    final selection = selectionController.selection!.normalizedRange;

    expect(selection.end.textOffset, 24);
    expect(selection.end.path.segments, const <int>[0]);
    expect(
      selectionController.selectedPlainText,
      'Paragraph with link (https://example.com) tail',
    );
  });

  test('serializes a fully selected list block with link destinations', () {
    const input = '- before [link](https://example.com) after';

    final controller = MarkdownController(data: input);
    const serializer = MarkdownPlainTextSerializer();
    final list = controller.document.blocks.single as ListBlock;
    final structure = StructuredBlockSelection.forBlock(list);

    final text = serializer.serializeSelection(
      controller.document,
      DocumentSelection(
        base: structure.startPosition(blockIndex: 0),
        extent: structure.endPosition(blockIndex: 0),
      ),
    );

    expect(structure.plainText, '- before link after');
    expect(text, '- before link (https://example.com) after');
  });

  test('serializes a fully selected footnote block with link destinations', () {
    const input = '''
Reference[^note]

[^note]: Footnote [link](https://example.com)
''';

    final controller = MarkdownController(data: input);
    const serializer = MarkdownPlainTextSerializer();
    final footnotes = controller.document.blocks.last as FootnoteListBlock;
    final structure = StructuredBlockSelection.forBlock(footnotes);

    final text = serializer.serializeSelection(
      controller.document,
      DocumentSelection(
        base: structure.startPosition(blockIndex: 1),
        extent: structure.endPosition(blockIndex: 1),
      ),
    );

    expect(structure.plainText.trimRight(), '1. Footnote link');
    expect(text.trimRight(), '1. Footnote link (https://example.com)');
  });

  test('serializes a fully selected definition list with link destinations',
      () {
    const input = '''
Term
: before [link](https://example.com) after
''';

    final controller = MarkdownController(data: input);
    const serializer = MarkdownPlainTextSerializer();
    final definitionList =
        controller.document.blocks.single as DefinitionListBlock;
    final structure = StructuredBlockSelection.forBlock(definitionList);

    final text = serializer.serializeSelection(
      controller.document,
      DocumentSelection(
        base: structure.startPosition(blockIndex: 0),
        extent: structure.endPosition(blockIndex: 0),
      ),
    );

    expect(structure.plainText, 'Term\n: before link after');
    expect(text, 'Term\n: before link (https://example.com) after');
  });

  test('selection controller selects and exposes plain text', () {
    final controller = MarkdownController(data: '# Heading\n\nParagraph');
    final selectionController = MarkdownSelectionController()
      ..attachDocument(controller.document)
      ..selectAll();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Heading\n\nParagraph');

    selectionController.setSelection(
      const DocumentSelection(
        base: DocumentPosition(
          blockIndex: 1,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        extent: DocumentPosition(
          blockIndex: 1,
          path: PathInBlock(<int>[0]),
          textOffset: 4,
        ),
      ),
    );

    expect(selectionController.selectedPlainText, 'Para');
  });

  testWidgets('renders markdown from controller updates', (tester) async {
    final controller = MarkdownController(data: '# Hello');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(controller: controller),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);

    controller.appendChunk('\n\nAdditional paragraph');
    await tester.pumpAndSettle();

    expect(find.text('Additional paragraph'), findsOneWidget);
  });

  testWidgets('uses pretext for plain-text headings and paragraphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: '# Heading\n\nPlain paragraph'),
        ),
      ),
    );

    expect(find.byType(MarkdownPretextTextBlock), findsNWidgets(2));
  });

  testWidgets('renders dividers under h1 and h2 only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '# Heading 1\n\n## Heading 2\n\n### Heading 3',
          ),
        ),
      ),
    );

    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('uses pretext for rich inline paragraphs too', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: 'Paragraph with **bold** [link](https://example.com) `code`',
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownPretextTextBlock), findsOneWidget);
  });

  testWidgets('renders math with flutter_math_fork through pretext blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'Inline $a^2+b^2=c^2$ and $$\int_0^1 x^2 dx$$',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.byType(MarkdownPretextTextBlock), findsOneWidget);
  });

  testWidgets('aligns inline math to the text baseline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'Inline $a^2+b^2=c^2$ formula.',
          ),
        ),
      ),
    );

    final textWidget = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(MarkdownWidget),
            matching: find.byType(Text),
          )
          .first,
    );
    final widgetSpans = _collectWidgetSpans(textWidget.textSpan!).toList();

    expect(widgetSpans, hasLength(1));
    expect(widgetSpans.single.alignment, PlaceholderAlignment.baseline);
    expect(widgetSpans.single.baseline, TextBaseline.alphabetic);
  });

  testWidgets('math selection geometry tracks live widget bounds in paragraphs',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'Before $x^2$ after',
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Before x^2 after'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockContext = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    final blockOrigin = blockRenderBox.localToGlobal(Offset.zero);
    final mathRect = tester.getRect(find.byType(Math).first);
    final mathStart = block.spec.plainText.indexOf('x^2');
    final mathEnd = mathStart + 'x^2'.length;

    final selectionRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathStart,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathEnd,
        ),
      ),
    );
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(blockOrigin))
        .toList(growable: false);

    expect(globalSelectionRects, isNotEmpty);
    expect(
      globalSelectionRects.any((rect) => rect.overlaps(mathRect.inflate(1))),
      isTrue,
    );
    final mathSelectionRect = globalSelectionRects.firstWhere(
      (rect) => rect.overlaps(mathRect.inflate(1)),
    );
    expect(mathSelectionRect.contains(mathRect.center), isTrue);
    expect(mathSelectionRect.width, lessThan(mathRect.width + 16));
    expect(mathSelectionRect.left, lessThanOrEqualTo(mathRect.left + 6));
    expect(mathSelectionRect.right, greaterThanOrEqualTo(mathRect.right - 6));

    final leftOffset = block.spec.textOffsetResolver!(
      blockContext,
      blockRenderBox.size,
      blockRenderBox.globalToLocal(mathRect.centerLeft + const Offset(1, 0)),
    );
    final rightOffset = block.spec.textOffsetResolver!(
      blockContext,
      blockRenderBox.size,
      blockRenderBox.globalToLocal(mathRect.centerRight + const Offset(2, 0)),
    );

    expect(leftOffset, mathStart);
    expect(rightOffset, mathEnd);
  });

  testWidgets(
      'math selection geometry tracks live widget bounds after inline code',
      (tester) async {
    const data = r'test `math` a \( x = \frac{-b \pm \sqrt{b^2-4ac}}{2a} \)';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: data,
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('test math a ') &&
          widget.spec.plainText
              .contains(r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockContext = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    final blockOrigin = blockRenderBox.localToGlobal(Offset.zero);
    final mathRect = tester.getRect(find.byType(Math).first);
    final mathStart =
        block.spec.plainText.indexOf(r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}');
    final mathEnd = mathStart + r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}'.length;

    final selectionRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathStart,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathEnd,
        ),
      ),
    );
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(blockOrigin))
        .toList(growable: false);

    expect(globalSelectionRects, isNotEmpty);
    final mathSelectionRect = globalSelectionRects.firstWhere(
      (rect) => rect.overlaps(mathRect.inflate(1)),
    );
    expect(mathSelectionRect.contains(mathRect.center), isTrue);
    expect(mathSelectionRect.width, lessThan(mathRect.width + 16));
    expect(mathSelectionRect.left, lessThanOrEqualTo(mathRect.left + 6));
    expect(mathSelectionRect.right, greaterThanOrEqualTo(mathRect.right - 6));

    final leftOffset = block.spec.textOffsetResolver!(
      blockContext,
      blockRenderBox.size,
      blockRenderBox.globalToLocal(mathRect.centerLeft + const Offset(1, 0)),
    );
    final rightOffset = block.spec.textOffsetResolver!(
      blockContext,
      blockRenderBox.size,
      blockRenderBox.globalToLocal(mathRect.centerRight + const Offset(2, 0)),
    );

    expect(leftOffset, mathStart);
    expect(rightOffset, mathEnd);
  });

  testWidgets('inline code stays compact when a paragraph also contains math',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'test `math` a \( x = \frac{-b \pm \sqrt{b^2-4ac}}{2a} \)',
          ),
        ),
      ),
    );

    expect(_decoratedInlineTextFinder(), findsWidgets);
  });

  testWidgets(
      'selection across text inline code and math does not produce overlapping boxes',
      (tester) async {
    const data = r'test `math` a \( x = \frac{-b \pm \sqrt{b^2-4ac}}{2a} \)';
    const mathText = r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: data,
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('test math a ') &&
          widget.spec.plainText.contains(mathText),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockContext = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    final mathEnd = block.spec.plainText.indexOf(mathText) + mathText.length;
    final selectionRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathEnd,
        ),
      ),
    );

    expect(selectionRects, isNotEmpty);
    final sortedRects = selectionRects.toList(growable: false)
      ..sort((a, b) {
        final topCompare = a.top.compareTo(b.top);
        if (topCompare != 0) {
          return topCompare;
        }
        return a.left.compareTo(b.left);
      });
    for (var index = 0; index < sortedRects.length - 1; index++) {
      final current = sortedRects[index];
      final next = sortedRects[index + 1];
      final sameLine = (next.top - current.top).abs() <= 2.0 &&
          (next.bottom - current.bottom).abs() <= 2.0;
      if (!sameLine) {
        continue;
      }
      expect(current.overlaps(next), isFalse);
    }
  });

  testWidgets('pretext blocks with math paint selection above child',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: r'before $x^2$ after'),
        ),
      ),
    );

    final paragraphFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('before x^2 after'),
    );
    final paragraph = tester.widget<SelectableMarkdownBlock>(paragraphFinder);

    expect(
      paragraph.spec.selectionPaintOrder,
      SelectableBlockSelectionPaintOrder.aboveChild,
    );
  });

  testWidgets('display math selection geometry tracks live widget bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'$$x^2$$',
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('x^2'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockContext = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    final blockOrigin = blockRenderBox.localToGlobal(Offset.zero);
    final mathRect = tester.getRect(find.byType(Math).first);
    final mathStart = block.spec.plainText.indexOf('x^2');
    final mathEnd = mathStart + 'x^2'.length;

    final selectionRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathStart,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathEnd,
        ),
      ),
    );
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(blockOrigin))
        .toList(growable: false);

    expect(globalSelectionRects, isNotEmpty);
    final mathSelectionRect = globalSelectionRects.firstWhere(
      (rect) => rect.overlaps(mathRect.inflate(1)),
    );
    expect(mathSelectionRect.contains(mathRect.center), isTrue);
    expect(mathSelectionRect.width, lessThan(mathRect.width + 16));
    expect(mathSelectionRect.left, lessThanOrEqualTo(mathRect.left + 6));
    expect(mathSelectionRect.right, greaterThanOrEqualTo(mathRect.right - 6));
  });

  testWidgets('math selection geometry tracks live widget bounds inside lists',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'- Before $x^2$ after',
          ),
        ),
      ),
    );

    final listBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('- Before x^2 after'),
    );
    final listBlock = tester.widget<SelectableMarkdownBlock>(listBlockFinder);
    final listContext = tester.element(listBlockFinder);
    final listRenderBox = tester.renderObject<RenderBox>(listBlockFinder);
    final listOrigin = listRenderBox.localToGlobal(Offset.zero);
    final mathRect = tester.getRect(find.byType(Math).first);
    final mathStart = listBlock.spec.plainText.indexOf('x^2');
    final mathEnd = mathStart + 'x^2'.length;

    final selectionRects = listBlock.spec.selectionRectResolver!(
      listContext,
      listRenderBox.size,
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathStart,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: mathEnd,
        ),
      ),
    );
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(listOrigin))
        .toList(growable: false);

    expect(globalSelectionRects, isNotEmpty);
    expect(
      globalSelectionRects.any((rect) => rect.overlaps(mathRect.inflate(1))),
      isTrue,
    );

    final leftOffset = listBlock.spec.textOffsetResolver!(
      listContext,
      listRenderBox.size,
      listRenderBox.globalToLocal(mathRect.centerLeft + const Offset(1, 0)),
    );
    final rightOffset = listBlock.spec.textOffsetResolver!(
      listContext,
      listRenderBox.size,
      listRenderBox.globalToLocal(mathRect.centerRight + const Offset(2, 0)),
    );

    expect(leftOffset, mathStart);
    expect(rightOffset, mathEnd);
  });

  testWidgets('renders backslash inline math with surrounding whitespace', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data:
                r'Quadratic formula: \( x = \frac{-b \pm \sqrt{b^2-4ac}}{2a} \).',
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\('), findsNothing);
    expect(find.textContaining(r'\)'), findsNothing);
  });

  testWidgets('tap on links still triggers onTapLink when selection is enabled',
      (
    tester,
  ) async {
    String? tappedDestination;
    String? tappedLabel;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: 'Visit [Example](https://example.com)',
            onTapLink: (destination, title, label) {
              tappedDestination = destination;
              tappedLabel = label;
            },
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Visit Example'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderBox = tester.renderObject<RenderBox>(richTextFinder);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);
    final linkBoxes = painter.getBoxesForSelection(
      const TextSelection(baseOffset: 6, extentOffset: 13),
    );

    await tester.tapAt(
      renderBox.localToGlobal(linkBoxes.first.toRect().center),
    );
    await tester.pump();

    expect(tappedDestination, 'https://example.com');
    expect(tappedLabel, 'Example');
  });

  testWidgets('tap on inline html anchor tags triggers onTapLink',
      (tester) async {
    String? tappedDestination;
    String? tappedLabel;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data:
                '💡 <a href="https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Learn how to get started</a>.',
            onTapLink: (destination, title, label) {
              tappedDestination = destination;
              tappedLabel = label;
            },
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Learn how to get started'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderBox = tester.renderObject<RenderBox>(richTextFinder);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);
    final plainText = richText.text.toPlainText();
    final start = plainText.indexOf('Learn how to get started');
    final end = start + 'Learn how to get started'.length;
    final linkBoxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );

    await tester
        .tapAt(renderBox.localToGlobal(linkBoxes.first.toRect().center));
    await tester.pump();

    expect(
      tappedDestination,
      'https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot',
    );
    expect(tappedLabel, 'Learn how to get started');
  });

  testWidgets('uses pretext for list items, quotes, and table cells', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
- First **item**
- Second [link](https://example.com)

> Quoted `text`

| Name | Value |
| --- | ---: |
| row | **42** |
''',
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownPretextTextBlock), findsAtLeastNWidgets(7));
  });

  testWidgets('renders task lists, definition lists, footnotes, and emoji', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
- [x] Done
- [ ] Todo

Term
: Definition with :white_check_mark:

Reference[^note]

[^note]: Footnote body
''',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsOneWidget);
    expect(find.textContaining('Term'), findsOneWidget);
    expect(find.textContaining('Definition with ✅'), findsOneWidget);
    expect(find.textContaining('Footnote body'), findsOneWidget);
  });

  testWidgets('renders footnotes as ordered block content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
Reference[^note]

[^note]: First paragraph

    Second paragraph
''',
          ),
        ),
      ),
    );

    expect(find.text('1.'), findsOneWidget);
    expect(find.textContaining('First paragraph'), findsOneWidget);
    expect(find.textContaining('Second paragraph'), findsOneWidget);
  });

  testWidgets(
      'renders multiple footnote references without swallowing body text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
Here is a statement with a footnote.[^1] Another reference can be added here.[^long]

[^1]: This is a simple footnote.
[^long]: This footnote contains a longer explanation to showcase how multiple lines can be formatted in a footnote. It supports Markdown formatting such as **bold** and *italic* text.
''',
          ),
        ),
      ),
    );

    final renderedText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(
      renderedText,
      contains('Here is a statement with a footnote.1 Another'),
    );
    expect(
      renderedText,
      contains('reference can be added here.2'),
    );
    expect(
      find.textContaining('This is a simple footnote.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'This footnote contains a longer explanation',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders tables and code blocks with direct data input', (
    tester,
  ) async {
    const input = '''
| Language | Kind |
| --- | --- |
| Dart | SDK |

```text
copy me
```
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: input),
        ),
      ),
    );

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
    expect(find.textContaining('copy me'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsWidgets,
    );
  });

  testWidgets('table selectable clip radius matches the table frame radius', (
    tester,
  ) async {
    const input = '''
| A | B |
| --- | --- |
| 1 | 2 |
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: input),
        ),
      ),
    );

    final context = tester.element(find.byType(MarkdownWidget));
    final theme = MarkdownTheme.of(context);
    final tableBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.child is MarkdownTableBlockView,
    );
    expect(tableBlockFinder, findsOneWidget);

    final tableBlock = tester.widget<SelectableMarkdownBlock>(tableBlockFinder);
    expect(tableBlock.spec.highlightBorderRadius, theme.tableBorderRadius);
  });

  testWidgets('table frame paints border above the clipped table content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: MarkdownTableFrame(
              theme: MarkdownThemeData.fallback(context),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    final frameFinder = find.byType(MarkdownTableFrame);
    expect(frameFinder, findsOneWidget);

    final customPaintFinder = find.descendant(
      of: frameFinder,
      matching: find.byType(CustomPaint),
    );
    expect(customPaintFinder, findsOneWidget);
    expect(
      tester.widget<CustomPaint>(customPaintFinder).foregroundPainter,
      isNotNull,
    );

    final clipFinder = find.descendant(
      of: frameFinder,
      matching: find.byType(ClipRRect),
    );
    expect(clipFinder, findsOneWidget);
  });

  testWidgets(
      'code blocks render without an outer border and keep copy in the top right',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
```dart
final settleResult = 42;
```
''',
          ),
        ),
      ),
    );

    final theme = MarkdownTheme.of(tester.element(find.byType(MarkdownWidget)));
    final codeBlockBox = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .firstWhere((widget) {
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color != null &&
          decoration.borderRadius != null &&
          decoration.border == null;
    });
    final decoration = codeBlockBox.decoration as BoxDecoration;
    expect(decoration.border, isNull);
    expect(decoration.color, theme.inlineCodeBackgroundColor);

    final codeBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color ==
              theme.inlineCodeBackgroundColor &&
          (widget.decoration as BoxDecoration).border == null,
    );
    expect(codeBlockFinder, findsOneWidget);

    final copyButton = find.byTooltip('Copy code');
    expect(copyButton, findsOneWidget);
    final buttonTopRight = tester.getTopRight(copyButton);
    final codeBlockTopRight = tester.getTopRight(codeBlockFinder);
    expect((buttonTopRight.dx - codeBlockTopRight.dx).abs(), lessThan(36));
    expect((buttonTopRight.dy - codeBlockTopRight.dy).abs(), lessThan(36));

    final markdownWidth = tester.getSize(find.byType(MarkdownWidget)).width -
        theme.padding.resolve(TextDirection.ltr).horizontal;
    final codeBlockWidth = tester.getSize(codeBlockFinder).width;
    expect(codeBlockWidth, closeTo(markdownWidth, 1.0));
  });

  testWidgets('wraps compact tables inside the viewport when columns are few',
      (tester) async {
    const input = '''
| Name | Description |
| --- | --- |
| Dart | This description is intentionally long so the table should wrap inside the available width instead of forcing a horizontal scroll for a simple two-column layout. |
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: MarkdownWidget(
                data: input,
                selectable: false,
              ),
            ),
          ),
        ),
      ),
    );

    final horizontalScrollFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollFinder, findsOneWidget);

    final tableRenderBox = tester.renderObject<RenderBox>(find.byType(Table));
    // The table should be exactly taking its available width (320 max minus markdown container padding, ~288)
    expect(tableRenderBox.size.width, closeTo(288.0, 2.0));

    final descriptionHeaderFinder =
        find.text('Description', findRichText: true);
    final descriptionCellFinder = find.textContaining(
      'This description is intentionally long',
      findRichText: true,
    );

    expect(descriptionHeaderFinder, findsOneWidget);
    expect(descriptionCellFinder, findsOneWidget);
    expect(
      tester.getSize(descriptionCellFinder).height,
      greaterThan(tester.getSize(descriptionHeaderFinder).height * 1.5),
    );
  });

  testWidgets('keeps horizontal scrolling for wider comparison tables', (
    tester,
  ) async {
    const input = '''
| A | B | C | D | E |
| --- | --- | --- | --- | --- |
| alpha | beta | gamma | delta | epsilon |
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: MarkdownWidget(
                data: input,
                selectable: false,
              ),
            ),
          ),
        ),
      ),
    );

    final horizontalScrollFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollFinder, findsOneWidget);

    final tableRenderBox = tester.renderObject<RenderBox>(find.byType(Table));
    expect(tableRenderBox.size.width, greaterThan(320.0));
  });

  testWidgets('renders syntax-highlighted code spans', (tester) async {
    const input = '''
```dart
const value = 42;
return value;
```
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: input),
        ),
      ),
    );
    await tester.pump();

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('const value = 42;'),
    );

    expect(richTextFinder, findsOneWidget);

    final richText = tester.widget<RichText>(richTextFinder);
    final rootSpan = richText.text as TextSpan;
    expect(
        _countStyledDescendantSpans(rootSpan, rootSpan.style), greaterThan(0));
  });

  testWidgets(
      'code blocks render plain text on the first frame, then highlight',
      (tester) async {
    const input = '''
```dart
const value = 42;
return value;
```
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: input),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('const value = 42;'),
    );
    expect(richTextFinder, findsOneWidget);

    var richText = tester.widget<RichText>(richTextFinder);
    var rootSpan = richText.text as TextSpan;
    expect(_countStyledDescendantSpans(rootSpan, rootSpan.style), 0);

    await tester.pump();
    await tester.pump();

    richText = tester.widget<RichText>(richTextFinder);
    rootSpan = richText.text as TextSpan;
    expect(
        _countStyledDescendantSpans(rootSpan, rootSpan.style), greaterThan(0));
  });

  testWidgets('disposing markdown view ignores pending code highlight results',
      (tester) async {
    const input = '''
```dart
const value = 42;
return value;
```
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: input),
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long code blocks can degrade to plain text above the configured line limit',
      (tester) async {
    const input = '''
```dart
final a = 1;
final b = 2;
final c = a + b;
```
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: MarkdownWidget(
              data: input,
              theme: MarkdownThemeData.fallback(context).copyWith(
                codeHighlightMaxLines: 2,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('final c = a + b;'),
    );
    expect(richTextFinder, findsOneWidget);

    final richText = tester.widget<RichText>(richTextFinder);
    final rootSpan = richText.text as TextSpan;
    expect(_countStyledDescendantSpans(rootSpan, rootSpan.style), 0);
  });

  testWidgets('renders inline code with rounded background and padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: 'Inline `code` sample'),
        ),
      ),
    );

    final context = tester.element(find.byType(MarkdownWidget));
    final theme = MarkdownTheme.of(context);
    expect(
      theme.inlineCodePadding,
      const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
    );

    final inlineCodeFinder = _decoratedInlineTextFinder();
    expect(inlineCodeFinder, findsWidgets);

    final inlineCodeRenderBox =
        tester.renderObject<RenderBox>(inlineCodeFinder.first);
    final expectedHeight =
        _tightTextHeight('code', theme.bodyStyle.merge(theme.inlineCodeStyle)) +
            theme.inlineCodePadding.vertical;
    expect(
      inlineCodeRenderBox.size.height,
      closeTo(expectedHeight, 0.001),
    );
  });

  testWidgets('inline code prefers the default Mono font family', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: 'Inline `code` sample'),
        ),
      ),
    );

    final context = tester.element(find.byType(MarkdownWidget));
    final inlineCodeStyle = MarkdownTheme.of(context).inlineCodeStyle;
    expect(inlineCodeStyle.fontFamily, 'Mono');
    expect(
      inlineCodeStyle.fontFamilyFallback,
      containsAllInOrder(const <String>['SF Mono', 'Roboto Mono', 'Menlo']),
    );
  });

  testWidgets('code blocks prefer the default Mono font family',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
```dart
const value = 42;
```
''',
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('const value = 42;'),
    );

    final richText = tester.widget<RichText>(richTextFinder);
    expect(richText.text.style?.fontFamily, 'Mono');
    expect(
      richText.text.style?.fontFamilyFallback,
      containsAllInOrder(const <String>['SF Mono', 'Roboto Mono', 'Menlo']),
    );
    expect(richText.softWrap, isFalse);
  });

  testWidgets('selecting text across inline code does not throw',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: '- before `code` after'),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('before') &&
          widget.text.toPlainText().contains('after'),
    );
    expect(richTextFinder, findsOneWidget);

    final richTextRect = tester.getRect(richTextFinder);
    final gesture = await tester.startGesture(
      richTextRect.centerLeft + const Offset(12, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(richTextRect.centerRight - const Offset(12, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('pretext blocks with inline code paint selection above child',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: 'before `code` after'),
        ),
      ),
    );

    final customPaints = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((widget) => widget.foregroundPainter != null)
        .toList(growable: false);

    expect(customPaints, isNotEmpty);
  });

  test('partial selection on decorated inline uses partial text geometry', () {
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'code',
          style: TextStyle(fontSize: 14, height: 1.2),
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
      maxWidth: 300,
      textScaleFactor: 1,
    );

    final partialRects = layout.selectionRectsForRange(
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    final fullRects = layout.selectionRectsForRange(
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    expect(partialRects, isNotEmpty);
    expect(fullRects, isNotEmpty);
    expect(partialRects.first.width, lessThan(fullRects.first.width));
  });

  test('text offset after decorated inline accounts for inline padding', () {
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'before ',
          style: TextStyle(fontSize: 14, height: 1.2),
        ),
        MarkdownPretextInlineRun(
          text: 'code',
          style: TextStyle(fontSize: 14, height: 1.2),
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
        MarkdownPretextInlineRun(
          text: 'z',
          style: TextStyle(fontSize: 14, height: 1.2),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
      maxWidth: 300,
      textScaleFactor: 1,
    );

    final codeRects = layout.selectionRectsForRange(
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 7,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    expect(codeRects, isNotEmpty);
    final offsetAfterCode = layout.textOffsetAt(
      Offset(codeRects.first.right + 1, layout.lineHeight / 2),
      textDirection: TextDirection.ltr,
    );
    expect(offsetAfterCode, greaterThanOrEqualTo(11));
  });

  test('full selection on decorated inline covers horizontal padding', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'code',
          style: TextStyle(fontSize: 14, height: 1.2),
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: padding,
          ),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
      maxWidth: 300,
      textScaleFactor: 1,
    );

    final fullRects = layout.selectionRectsForRange(
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    final partialRects = layout.selectionRectsForRange(
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 1,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    expect(fullRects, isNotEmpty);
    expect(partialRects, isNotEmpty);
    expect(
      fullRects.first.width - partialRects.first.width,
      greaterThan(padding.horizontal),
    );
  });

  test('non-breakable decorated inline preserves horizontal padding', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'code',
          style: TextStyle(fontSize: 14, height: 1.2),
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: padding,
          ),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
      maxWidth: 300,
      textScaleFactor: 1,
    );

    final decoratedSegments = layout.lines.single.segments
        .where((segment) => segment.decoration != null)
        .toList(growable: false);

    expect(decoratedSegments, hasLength(1));
    expect(decoratedSegments.single.padding.left, padding.left);
    expect(decoratedSegments.single.padding.right, padding.right);
  });

  test('breakable decorated inline preserves explicit newlines', () {
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'ab\ncd',
          style: TextStyle(fontSize: 14, height: 1.2),
          allowCharacterWrap: true,
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
      maxWidth: 300,
      textScaleFactor: 1,
    );

    expect(layout.lines, hasLength(2));
    expect(
        layout.lines.map((line) => line.text).toList(), <String>['ab', 'cd']);
  });

  test('breakable decorated inline wraps across lines', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'abcdefghij',
          style: TextStyle(fontSize: 14, height: 1.2),
          allowCharacterWrap: true,
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: padding,
          ),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
      maxWidth: 44,
      textScaleFactor: 1,
    );

    expect(layout.lines.length, greaterThan(1));
    expect(layout.lines.map((line) => line.text).join(), 'abcdefghij');
    for (final line in layout.lines) {
      final decoratedSegments = line.segments
          .where((segment) => segment.decoration != null)
          .toList(growable: false);
      expect(decoratedSegments, isNotEmpty);
      expect(decoratedSegments.first.padding.left, greaterThan(0));
      expect(decoratedSegments.first.padding.left,
          lessThanOrEqualTo(padding.left));
      expect(decoratedSegments.last.padding.right, greaterThan(0));
      expect(decoratedSegments.last.padding.right,
          lessThanOrEqualTo(padding.right));
      for (final middle in decoratedSegments.skip(1).take(
            decoratedSegments.length > 2 ? decoratedSegments.length - 2 : 0,
          )) {
        expect(middle.padding.left, 0);
        expect(middle.padding.right, 0);
      }
    }
  });

  test('render-span pretext layout keeps per-line heights local', () {
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: <MarkdownPretextInlineRun>[
        const MarkdownPretextInlineRun(
          text: 'alpha beta gamma ',
          style: baseStyle,
        ),
        MarkdownPretextInlineRun(
          text: 'x^2',
          style: baseStyle,
          renderSpan: const WidgetSpan(
            child: SizedBox(width: 36, height: 28),
          ),
          estimatedWidth: 36,
          estimatedLineHeight: 32,
        ),
        const MarkdownPretextInlineRun(
          text: ' delta epsilon zeta eta theta',
          style: baseStyle,
        ),
      ],
      fallbackStyle: baseStyle,
      maxWidth: 96,
      textScaleFactor: 1,
    );

    expect(layout.lines.length, greaterThan(1));
    expect(
      layout.lines.map((line) => line.height).toSet().length,
      greaterThan(1),
    );
  });

  test('direct rich text geometry is used for undecorated or render-span runs',
      () {
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);

    expect(
      markdownPretextCanUseDirectRichTextGeometry(
        const <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(text: 'plain text', style: baseStyle),
        ],
      ),
      isTrue,
    );

    expect(
      markdownPretextCanUseDirectRichTextGeometry(
        <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: 'x^2',
            style: baseStyle,
            renderSpan:
                const WidgetSpan(child: SizedBox(width: 20, height: 16)),
            estimatedWidth: 20,
            estimatedLineHeight: 18,
          ),
        ],
      ),
      isTrue,
    );

    expect(
      markdownPretextCanUseDirectRichTextGeometry(
        <MarkdownPretextInlineRun>[
          const MarkdownPretextInlineRun(
            text: 'prefix ',
            style: baseStyle,
          ),
          const MarkdownPretextInlineRun(
            text: 'inline_code',
            style: baseStyle,
            allowCharacterWrap: true,
            decoration: MarkdownPretextInlineDecoration(
              backgroundColor: Color(0xFFE9EDF2),
              borderRadius: BorderRadius.all(Radius.circular(6)),
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
          ),
          MarkdownPretextInlineRun(
            text: 'x^2',
            style: baseStyle,
            renderSpan:
                const WidgetSpan(child: SizedBox(width: 20, height: 16)),
            estimatedWidth: 20,
            estimatedLineHeight: 18,
          ),
        ],
      ),
      isTrue,
    );

    expect(
      markdownPretextRenderText(
        <MarkdownPretextInlineRun>[
          const MarkdownPretextInlineRun(
            text: 'inline_code',
            style: baseStyle,
            allowCharacterWrap: true,
            decoration: MarkdownPretextInlineDecoration(
              backgroundColor: Color(0xFFE9EDF2),
              borderRadius: BorderRadius.all(Radius.circular(6)),
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
          ),
          MarkdownPretextInlineRun(
            text: 'x^2',
            style: baseStyle,
            renderSpan:
                const WidgetSpan(child: SizedBox(width: 20, height: 16)),
            estimatedWidth: 20,
            estimatedLineHeight: 18,
          ),
        ],
      ),
      '${String.fromCharCode(0xFFFC)}${String.fromCharCodes(
        List<int>.filled('inline_code'.length, 0xFFFC),
      )}',
    );

    expect(
      markdownPretextCanUseDirectRichTextGeometry(
        const <MarkdownPretextInlineRun>[
          MarkdownPretextInlineRun(
            text: 'inline_code',
            style: baseStyle,
            allowCharacterWrap: true,
            decoration: MarkdownPretextInlineDecoration(
              backgroundColor: Color(0xFFE9EDF2),
              borderRadius: BorderRadius.all(Radius.circular(6)),
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
          ),
        ],
      ),
      isFalse,
    );
  });

  testWidgets('table cells keep inline code compact when mixed with math', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '| Value |\n| --- |\n| `code` (x^2) |',
          ),
        ),
      ),
    );

    final tableFinder = find.byType(Table);
    expect(tableFinder, findsOneWidget);

    final cellRichTextFinder = find.descendant(
      of: tableFinder,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains(
                  String.fromCharCodes(const <int>[0xFFFC, 0xFFFC]),
                ),
      ),
    );
    expect(cellRichTextFinder, findsOneWidget);

    final inlineCodeDecorationFinder = find.descendant(
      of: cellRichTextFinder,
      matching: _decoratedInlineTextFinder(),
    );
    expect(inlineCodeDecorationFinder, findsWidgets);
  });

  testWidgets('table cells render inline math without baseline alignment', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '| Formula |\n| --- |\n| value \$x^2\$ |',
          ),
        ),
      ),
    );

    final tableFinder = find.byType(Table);
    expect(tableFinder, findsOneWidget);

    final cellRichText = tester.widget<RichText>(
      find
          .descendant(
            of: tableFinder,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText().contains(
                        String.fromCharCode(0xFFFC),
                      ),
            ),
          )
          .first,
    );
    final widgetSpans = _collectWidgetSpans(cellRichText.text).toList();

    expect(widgetSpans, hasLength(1));
    expect(widgetSpans.single.alignment, PlaceholderAlignment.middle);
    expect(widgetSpans.single.baseline, isNull);
  });

  testWidgets('undecorated runs render as a single direct rich text block', (
    tester,
  ) async {
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);
    const runs = <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(
        text:
            'This plain paragraph is intentionally long so it wraps across multiple lines without inline code.',
        style: baseStyle,
      ),
    ];

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(),
          child: Center(
            child: SizedBox(
              width: 120,
              child: MarkdownPretextTextBlock.rich(
                runs: runs,
                fallbackStyle: baseStyle,
                preferDirectRichText: true,
              ),
            ),
          ),
        ),
      ),
    );

    final blockFinder = find.byType(MarkdownPretextTextBlock);
    expect(
      find.descendant(of: blockFinder, matching: find.byType(Column)),
      findsNothing,
    );
    expect(
      find.descendant(of: blockFinder, matching: find.byType(RichText)),
      findsOneWidget,
    );
  });

  testWidgets('decorated inline code blocks stay on the pretext line layout', (
    tester,
  ) async {
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);
    const runs = <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(text: 'prefix ', style: baseStyle),
      MarkdownPretextInlineRun(
        text: 'inline_code_token',
        style: baseStyle,
        allowCharacterWrap: true,
        decoration: MarkdownPretextInlineDecoration(
          backgroundColor: Color(0xFFE9EDF2),
          borderRadius: BorderRadius.all(Radius.circular(6)),
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
      ),
      MarkdownPretextInlineRun(
        text: ' suffix that forces wrapping.',
        style: baseStyle,
      ),
    ];

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(),
          child: Center(
            child: SizedBox(
              width: 120,
              child: MarkdownPretextTextBlock.rich(
                runs: runs,
                fallbackStyle: baseStyle,
              ),
            ),
          ),
        ),
      ),
    );

    final blockFinder = find.byType(MarkdownPretextTextBlock);
    expect(
      find.descendant(of: blockFinder, matching: find.byType(Column)),
      findsOneWidget,
    );
  });

  test('breakable decorated inline keeps wrapped settle_result visible', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    const runs = <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(
        text: 'used during ',
        style: TextStyle(fontSize: 14, height: 1.2),
      ),
      MarkdownPretextInlineRun(
        text: 'settle_result',
        style: TextStyle(fontSize: 14, height: 1.2),
        allowCharacterWrap: true,
        decoration: MarkdownPretextInlineDecoration(
          backgroundColor: Color(0xFFE9EDF2),
          borderRadius: BorderRadius.all(Radius.circular(6)),
          padding: padding,
        ),
      ),
      MarkdownPretextInlineRun(
        text: ' to skip very small refunds.',
        style: TextStyle(fontSize: 14, height: 1.2),
      ),
    ];

    for (final width in <double>[132, 96, 72, 56]) {
      final layout = computeMarkdownPretextLayoutFromRuns(
        runs: runs,
        fallbackStyle: const TextStyle(fontSize: 14, height: 1.2),
        maxWidth: width,
        textScaleFactor: 1,
      );

      expect(layout.lines.length, greaterThan(1));
      expect(
        layout.plainText,
        'used during settle_result to skip very small refunds.',
      );

      final decoratedSegments = layout.lines
          .expand((line) => line.segments)
          .where((segment) => segment.decoration != null)
          .toList(growable: false);
      expect(decoratedSegments, isNotEmpty);
      expect(
        decoratedSegments.map((segment) => segment.text).join(),
        'settle_result',
      );
      for (final line in layout.lines) {
        final actualWidth = line.segments.fold<double>(
          0,
          (sum, segment) => sum + (segment.right - segment.left),
        );
        expect(actualWidth, lessThanOrEqualTo(width + 0.01));
      }

      for (final line in layout.lines) {
        final lineDecoratedSegments = line.segments
            .where((segment) => segment.decoration != null)
            .toList(growable: false);
        if (lineDecoratedSegments.isEmpty) {
          continue;
        }
        expect(lineDecoratedSegments.first.text, isNotEmpty);
        expect(
            lineDecoratedSegments.first.padding.left, greaterThanOrEqualTo(0));
        expect(
            lineDecoratedSegments.last.padding.right, greaterThanOrEqualTo(0));
        expect(lineDecoratedSegments.last.padding.right,
            lessThanOrEqualTo(padding.right));
      }
    }
  });

  test('multiple wrapped inline code runs preserve all trailing text', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);
    const expected =
        'Introduces a fixed minimum refund threshold (0.1) used during settle_result to skip very small refunds.';
    const runs = <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(
        text: 'Introduces a fixed minimum refund threshold (',
        style: baseStyle,
      ),
      MarkdownPretextInlineRun(
        text: '0.1',
        style: baseStyle,
        allowCharacterWrap: true,
        decoration: MarkdownPretextInlineDecoration(
          backgroundColor: Color(0xFFE9EDF2),
          borderRadius: BorderRadius.all(Radius.circular(6)),
          padding: padding,
        ),
      ),
      MarkdownPretextInlineRun(
        text: ') used during ',
        style: baseStyle,
      ),
      MarkdownPretextInlineRun(
        text: 'settle_result',
        style: baseStyle,
        allowCharacterWrap: true,
        decoration: MarkdownPretextInlineDecoration(
          backgroundColor: Color(0xFFE9EDF2),
          borderRadius: BorderRadius.all(Radius.circular(6)),
          padding: padding,
        ),
      ),
      MarkdownPretextInlineRun(
        text: ' to skip very small refunds.',
        style: baseStyle,
      ),
    ];

    for (final width in <double>[220, 180, 160, 140, 120]) {
      final layout = computeMarkdownPretextLayoutFromRuns(
        runs: runs,
        fallbackStyle: baseStyle,
        maxWidth: width,
        textScaleFactor: 1,
      );

      expect(
        layout.lines.map((line) => line.text).join().replaceAll(' ', ''),
        expected.replaceAll(' ', ''),
      );
      for (final line in layout.lines) {
        final actualWidth = line.segments.fold<double>(
          0,
          (sum, segment) => sum + (segment.right - segment.left),
        );
        expect(actualWidth, lessThanOrEqualTo(width + 0.01));
      }
    }
  });

  test('send_sol_for_rent wrap does not create an extra clipped line', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);
    const expected =
        '宅学长发布了一份InputFragment 余额与手续费校验说明文档，整理了Mixin安卓App账户租金（rent）场景，才会显示send_sol_for_rent提示。';
    const runs = <MarkdownPretextInlineRun>[
      MarkdownPretextInlineRun(
        text:
            '宅学长发布了一份InputFragment 余额与手续费校验说明文档，整理了Mixin安卓App账户租金（rent）场景，才会显示',
        style: baseStyle,
      ),
      MarkdownPretextInlineRun(
        text: 'send_sol_for_rent',
        style: baseStyle,
        allowCharacterWrap: true,
        decoration: MarkdownPretextInlineDecoration(
          backgroundColor: Color(0xFFE9EDF2),
          borderRadius: BorderRadius.all(Radius.circular(6)),
          padding: padding,
        ),
      ),
      MarkdownPretextInlineRun(
        text: '提示。',
        style: baseStyle,
      ),
    ];

    for (final width in <double>[232, 228, 224, 220, 216, 212, 208, 204]) {
      final layout = computeMarkdownPretextLayoutFromRuns(
        runs: runs,
        fallbackStyle: baseStyle,
        maxWidth: width,
        textScaleFactor: 1,
      );

      expect(
        layout.lines.map((line) => line.text).join().replaceAll(' ', ''),
        expected.replaceAll(' ', ''),
        reason: 'width=$width',
      );
      for (final line in layout.lines) {
        final actualWidth = line.segments.fold<double>(
          0,
          (sum, segment) => sum + (segment.right - segment.left),
        );
        expect(actualWidth, lessThanOrEqualTo(width + 0.01));
      }
      final decoratedText = layout.lines
          .expand((line) => line.segments)
          .where((segment) => segment.decoration != null)
          .map((segment) => segment.text)
          .join();
      expect(
        decoratedText,
        'send_sol_for_rent',
        reason: 'width=$width',
      );
    }
  });

  test('trailing inline code does not shrink earlier line wrapping', () {
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    const baseStyle = TextStyle(fontSize: 14, height: 1.2);
    const prefix =
        '宅学长发布了一份InputFragment 余额与手续费校验说明文档，整理了Mixin安卓App钱包转账页面的逻辑，区分了三种场景，重点明确：只有Solana真实账户租金场景，才会显示';
    const suffix = '提示。';
    const width = 232.0;

    final plainLayout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: '$prefix send_sol_for_rent$suffix',
          style: baseStyle,
        ),
      ],
      fallbackStyle: baseStyle,
      maxWidth: width,
      textScaleFactor: 1,
    );

    final codeLayout = computeMarkdownPretextLayoutFromRuns(
      runs: const <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: '$prefix ',
          style: baseStyle,
        ),
        MarkdownPretextInlineRun(
          text: 'send_sol_for_rent',
          style: baseStyle,
          allowCharacterWrap: true,
          decoration: MarkdownPretextInlineDecoration(
            backgroundColor: Color(0xFFE9EDF2),
            borderRadius: BorderRadius.all(Radius.circular(6)),
            padding: padding,
          ),
        ),
        MarkdownPretextInlineRun(
          text: suffix,
          style: baseStyle,
        ),
      ],
      fallbackStyle: baseStyle,
      maxWidth: width,
      textScaleFactor: 1,
    );

    expect(plainLayout.lines, isNotEmpty);
    expect(codeLayout.lines, isNotEmpty);
    expect(
      codeLayout.lines.first.text.replaceAll(' ', ''),
      plainLayout.lines.first.text.replaceAll(' ', ''),
    );
  });

  testWidgets(
      'markdown inline code at paragraph tail does not shift the first line break',
      (tester) async {
    const inlineCodeMarkdown =
        '某人发布了一份**《TEST 某功能校验说明》**文档，整理了某客户端转账页的逻辑，区分了三种场景，分别说明金额校验、可用余额计算、手续费校验规则，重点明确：只有某链真实租金场景，才会显示`rent_tip_token` 提示。';
    late MarkdownThemeData theme;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            theme = MarkdownThemeData.fallback(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    List<String> layoutLinesFromMarkdown(String markdown, double width) {
      final parser = MarkdownDocumentParser();
      final document = parser.parse(markdown);
      final paragraph = document.blocks.single as ParagraphBlock;
      final builder = MarkdownInlineBuilder(
        theme: theme,
        recognizers: <TapGestureRecognizer>[],
      );
      final runs = builder.buildPretextRuns(theme.bodyStyle, paragraph.inlines);
      final layout = computeMarkdownPretextLayoutFromRuns(
        runs: runs,
        fallbackStyle: theme.bodyStyle,
        maxWidth: width,
        textScaleFactor: 1,
      );
      return layout.lines.map((line) => line.text).toList(growable: false);
    }

    for (final width in <double>[500]) {
      final inlineCodeLines =
          layoutLinesFromMarkdown(inlineCodeMarkdown, width);

      expect(inlineCodeLines, isNotEmpty, reason: 'width=$width');
      expect(
        inlineCodeLines.first,
        isNot('某人发布了一份**《TEST'),
        reason: 'width=$width first=${inlineCodeLines.first}',
      );
      expect(
        inlineCodeLines.first,
        contains('某功能'),
        reason: 'width=$width first=${inlineCodeLines.first}',
      );
    }
  });

  testWidgets(
      'widget rendering keeps the first list line stable with trailing inline code',
      (tester) async {
    const inlineCodeMarkdown =
        '1. 某人发布了一份**《TEST 某功能校验说明》**文档，整理了某客户端转账页的逻辑，区分了三种场景，分别说明金额校验、可用余额计算、手续费校验规则，重点明确：只有某链真实租金场景，才会显示`rent_tip_token` 提示。';

    Future<List<String>> renderedLines(String markdown, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: MarkdownWidget(data: markdown),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final blockFinder = find.byType(MarkdownPretextTextBlock).first;
      final blockWidget = tester.widget<MarkdownPretextTextBlock>(blockFinder);
      final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
      final layout = computeMarkdownPretextLayoutFromRuns(
        runs: blockWidget.runs!,
        fallbackStyle: blockWidget.fallbackStyle,
        maxWidth: blockRenderBox.size.width,
        textScaleFactor: 1,
      );
      return layout.lines.map((line) => line.text).toList(growable: false);
    }

    for (final width in <double>[500]) {
      final inlineCodeLines = await renderedLines(inlineCodeMarkdown, width);

      expect(inlineCodeLines, isNotEmpty, reason: 'width=$width');
      expect(
        inlineCodeLines.first,
        isNot('某人发布了一份**《TEST'),
        reason: 'width=$width first=${inlineCodeLines.first}',
      );
      expect(
        inlineCodeLines.first,
        contains('某功能'),
        reason: 'width=$width first=${inlineCodeLines.first}',
      );
    }
  });

  testWidgets('reuses cached unchanged pretext block widgets on append', (
    tester,
  ) async {
    final controller = MarkdownController(data: '# Hello\n\nBody');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(controller: controller),
        ),
      ),
    );

    final beforeWidgets = tester
        .widgetList<MarkdownPretextTextBlock>(
          find.byType(MarkdownPretextTextBlock),
        )
        .toList(growable: false);

    controller.appendChunk('\n\nTail');
    await tester.pumpAndSettle();

    final afterWidgets = tester
        .widgetList<MarkdownPretextTextBlock>(
          find.byType(MarkdownPretextTextBlock),
        )
        .toList(growable: false);

    expect(identical(afterWidgets.first, beforeWidgets.first), isTrue);
  });

  testWidgets('copies the full document with the desktop shortcut', (
    tester,
  ) async {
    String? copiedText;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: '# Hello\n\nWorld'),
        ),
      ),
    );

    await tester.tap(find.text('Hello'));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copiedText, 'Hello\n\nWorld');
  });

  testWidgets('dragging across blocks updates the custom selection', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '# Hello\n\nWorld',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final start = tester.getTopLeft(find.text('Hello')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('World')) - const Offset(1, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Hello\n\nWorld');
  });

  testWidgets('dragging from blank space starts a text selection',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '# Hello\n\nWorld',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final helloTopLeft = tester.getTopLeft(find.text('Hello'));
    final start = helloTopLeft - const Offset(12, -8);
    final end = tester.getBottomRight(find.text('World')) - const Offset(1, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Hello\n\nWorld');
  });

  testWidgets('clicking blank space clears the current selection', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: MarkdownWidget(
              data: '# Hello\n\nWorld',
              selectionController: selectionController,
            ),
          ),
        ),
      ),
    );

    final start = tester.getTopLeft(find.text('Hello')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('World')) - const Offset(1, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);

    await tester.tapAt(
      tester.getBottomRight(find.byType(ListView)) - const Offset(8, 8),
    );
    await tester.pump();

    expect(selectionController.hasSelection, isFalse);
  });

  testWidgets('clicking trailing blank space inside markdown clears selection',
      (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: MarkdownWidget(
              data: '# Hello\n\nWorld',
              selectionController: selectionController,
            ),
          ),
        ),
      ),
    );

    final start = tester.getTopLeft(find.text('Hello')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('World')) - const Offset(1, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);

    final pretextBox = tester
        .renderObject<RenderBox>(find.byType(MarkdownPretextTextBlock).first);
    final trailingBlankTap = pretextBox.localToGlobal(
      Offset(pretextBox.size.width - 4, pretextBox.size.height / 2),
    );
    await tester.tapAt(trailingBlankTap);
    await tester.pump();

    expect(selectionController.hasSelection, isFalse);
  });

  testWidgets('clicking outside markdown clears selection', (tester) async {
    final selectionController = MarkdownSelectionController();
    const outsideKey = Key('outside-target');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Expanded(
                child: MarkdownWidget(
                  data: '# Hello\n\nWorld',
                  selectionController: selectionController,
                ),
              ),
              const Expanded(
                child: ColoredBox(
                  key: outsideKey,
                  color: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final start = tester.getTopLeft(find.text('Hello')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('World')) - const Offset(1, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);

    await tester.tapAt(tester.getCenter(find.byKey(outsideKey)));
    await tester.pump();

    expect(selectionController.hasSelection, isFalse);
  });

  testWidgets('custom selection works without an external controller', (
    tester,
  ) async {
    String? copiedText;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(data: '# Hello\n\nWorld'),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);

    final start = tester.getTopLeft(find.text('Hello')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('World')) - const Offset(1, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copiedText, 'Hello\n\nWorld');
  });

  testWidgets('scrolling without an explicit controller does not throw', (
    tester,
  ) async {
    final buffer = StringBuffer();
    for (var index = 0; index < 40; index++) {
      if (index > 0) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer.write('Paragraph $index');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: MarkdownWidget(data: buffer.toString()),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('drag selection auto-scrolls near the viewport edge',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    final buffer = StringBuffer();
    for (var index = 0; index < 40; index++) {
      if (index > 0) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer.write('Paragraph $index');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: MarkdownWidget(
              data: buffer.toString(),
              selectionController: selectionController,
            ),
          ),
        ),
      ),
    );

    final listFinder = find.byType(ListView);
    final start =
        tester.getTopLeft(find.text('Paragraph 0')) + const Offset(2, 8);
    final edgeTarget = tester.getBottomLeft(listFinder) - const Offset(-4, 6);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(edgeTarget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pumpAndSettle();

    final scrollableState =
        tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollableState.position.pixels, greaterThan(0));
    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, contains('Paragraph 0'));
    expect(selectionController.selectedPlainText, contains('Paragraph'));
  });

  testWidgets('copy and select-all shortcuts use the custom selection', (
    tester,
  ) async {
    String? copiedText;
    final selectionController = MarkdownSelectionController();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '# Hello\n\nWorld',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Hello'));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(selectionController.selectedPlainText, 'Hello\n\nWorld');
    expect(copiedText, 'Hello\n\nWorld');
  });

  testWidgets('dragging inside a code block selects characters only', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
```dart
const value = 42;
return value;
```
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('const value = 42;'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderBox = tester.renderObject<RenderBox>(richTextFinder);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);

    final startOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 6),
      Rect.zero,
    );
    final endOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 11),
      Rect.zero,
    );
    final start = renderBox.localToGlobal(startOffset + const Offset(1, 8));
    final end = renderBox.localToGlobal(endOffset + const Offset(1, 8));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'value');

    final paintFinder = find.ancestor(
      of: richTextFinder,
      matching: find.byType(CustomPaint),
    );
    expect(
      tester.widget<CustomPaint>(paintFinder.first).foregroundPainter,
      isNotNull,
    );
  });

  testWidgets('code block selection geometry tracks rendered text boxes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
```dart
const value = 42;
return value;
```
''',
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('const value = 42;'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockContext = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    final blockOrigin = blockRenderBox.localToGlobal(Offset.zero);

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('const value = 42;'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final richTextRenderBox = tester.renderObject<RenderBox>(richTextFinder);
    final richTextOrigin = richTextRenderBox.localToGlobal(Offset.zero);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: richTextRenderBox.size.width);

    final codeText = richText.text.toPlainText();
    final start = codeText.indexOf('value');
    final end = start + 'value'.length;
    final expectedRect = painter
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .first
        .toRect()
        .shift(richTextOrigin);

    final selectionRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: start,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: end,
        ),
      ),
    );

    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(blockOrigin))
        .toList(growable: false);
    final matchedRect = globalSelectionRects.firstWhere(
      (rect) => rect.overlaps(expectedRect.inflate(1)),
    );

    expect(matchedRect.contains(expectedRect.center), isTrue);
    expect(matchedRect.top, greaterThan(blockOrigin.dy + 8));
    expect(matchedRect.left, greaterThan(blockOrigin.dx + 8));
    expect(matchedRect.left, closeTo(expectedRect.left - 1.5, 2.0));
    expect(matchedRect.top, closeTo(expectedRect.top - 1.5, 2.0));
    expect(matchedRect.right, closeTo(expectedRect.right + 1.5, 2.0));
    expect(matchedRect.bottom, closeTo(expectedRect.bottom + 1.5, 2.0));
  });

  testWidgets('code block selection follows horizontal scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: MarkdownWidget(
              data: '''
```dart
const veryLongValueName = 42;
```
''',
            ),
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('const veryLongValueName = 42;'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockContext = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    const selectionText = 'veryLongValueName';
    final start = block.spec.plainText.indexOf(selectionText);
    final end = start + selectionText.length;
    final range = DocumentRange(
      start: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: start,
      ),
      end: DocumentPosition(
        blockIndex: 0,
        path: const PathInBlock(<int>[0]),
        textOffset: end,
      ),
    );

    final beforeRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      range,
    );

    final scrollable = tester
        .widgetList<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        )
        .firstWhere((widget) => widget.scrollDirection == Axis.horizontal);
    scrollable.controller!.jumpTo(60);
    await tester.pump();

    final afterRects = block.spec.selectionRectResolver!(
      blockContext,
      blockRenderBox.size,
      range,
    );

    expect(beforeRects, isNotEmpty);
    expect(afterRects, isNotEmpty);
    expect(afterRects.first.left, lessThan(beforeRects.first.left));
  });

  testWidgets('dragging inside a list selects list text', (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
- First item
- Second item
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('First item'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderBox = tester.renderObject<RenderBox>(richTextFinder);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);

    final startOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 0),
      Rect.zero,
    );
    final endOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 5),
      Rect.zero,
    );
    final start = renderBox.localToGlobal(startOffset + const Offset(1, 8));
    final end = renderBox.localToGlobal(endOffset + const Offset(1, 8));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'First');
  });

  testWidgets('dragging from an ordered list marker includes the prefix', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '3. ABCDEFG',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final markerFinder = find.text('3.');
    final textFinder = find.text('ABCDEFG');
    final start = tester.getTopLeft(markerFinder) + const Offset(1, 1);
    final end = tester.getTopRight(textFinder) + const Offset(8, 8);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, startsWith('3.'));
  });

  testWidgets('list marker selection aligns with first content line', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
- First item
- Second item
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final listBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('- First item'),
    );
    final listBlock = tester.widget<SelectableMarkdownBlock>(listBlockFinder);
    final listContext = tester.element(listBlockFinder);
    final selectionRects = listBlock.spec.selectionRectResolver!(
      listContext,
      tester.getSize(listBlockFinder),
      const DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 6,
        ),
      ),
    );

    expect(selectionRects, isNotEmpty);
    final firstRect = selectionRects.first;
    expect(firstRect.height, greaterThan(0));
    if (selectionRects.length > 1) {
      final secondRect = selectionRects[1];
      expect((firstRect.top - secondRect.top).abs(), lessThanOrEqualTo(2.0));
      expect(
        (firstRect.bottom - secondRect.bottom).abs(),
        lessThanOrEqualTo(2.0),
      );
      expect(firstRect.right, greaterThanOrEqualTo(secondRect.left));
    }
  });

  testWidgets('list selection merges marker gap with the first content line', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '- First item',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final listBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('- First item'),
    );
    final listBlock = tester.widget<SelectableMarkdownBlock>(listBlockFinder);
    final listContext = tester.element(listBlockFinder);
    final selectionRects = listBlock.spec.selectionRectResolver!(
      listContext,
      tester.getSize(listBlockFinder),
      const DocumentRange(
        start: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 12,
        ),
      ),
    );

    expect(selectionRects, hasLength(1));
  });

  testWidgets('wrapped list selection does not vertically overlap lines', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: MarkdownWidget(
              data:
                  '3. Use the theme button in the app bar to switch the reading surface.',
              selectionController: selectionController,
            ),
          ),
        ),
      ),
    );

    final listBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Use the theme button'),
    );
    final listBlock = tester.widget<SelectableMarkdownBlock>(listBlockFinder);
    final listContext = tester.element(listBlockFinder);
    final selectionRects = listBlock.spec.selectionRectResolver!(
      listContext,
      tester.getSize(listBlockFinder),
      DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: listBlock.spec.plainText.length,
        ),
      ),
    )..sort((a, b) => a.top.compareTo(b.top));

    expect(selectionRects.length, greaterThanOrEqualTo(2));
    for (var index = 0; index < selectionRects.length - 1; index++) {
      expect(
        selectionRects[index].bottom <= selectionRects[index + 1].top + 0.5,
        isTrue,
      );
    }
  });

  testWidgets(
      'wrapped list hit testing keeps content selection in the line gutter', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: MarkdownWidget(
              data:
                  '3. Use the theme button in the app bar to switch the reading surface.',
              selectionController: selectionController,
            ),
          ),
        ),
      ),
    );

    final listBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Use the theme button'),
    );
    final listBlock = tester.widget<SelectableMarkdownBlock>(listBlockFinder);
    final listContext = tester.element(listBlockFinder);
    final listSize = tester.getSize(listBlockFinder);
    final fullSelectionRects = listBlock.spec.selectionRectResolver!(
      listContext,
      listSize,
      DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: listBlock.spec.plainText.length,
        ),
      ),
    )..sort((a, b) => a.top.compareTo(b.top));

    expect(fullSelectionRects.length, greaterThanOrEqualTo(2));
    final secondLineRect = fullSelectionRects[1];
    final resolvedOffset = listBlock.spec.textOffsetResolver!(
      listContext,
      listSize,
      Offset(secondLineRect.left - 2, secondLineRect.center.dy),
    );

    expect(resolvedOffset, greaterThan(3));
  });

  test('pretext selection rects merge overlapping inline style boxes', () {
    final layout = computeMarkdownPretextLayoutFromRuns(
      runs: <MarkdownPretextInlineRun>[
        MarkdownPretextInlineRun(
          text: 'before ',
          style: const TextStyle(fontSize: 16, height: 1.45),
        ),
        MarkdownPretextInlineRun(
          text: 'bold',
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        MarkdownPretextInlineRun(
          text: ' code',
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            fontFamily: 'monospace',
            backgroundColor: Color(0x11000000),
          ),
        ),
        MarkdownPretextInlineRun(
          text: ' after',
          style: const TextStyle(fontSize: 16, height: 1.45),
        ),
      ],
      fallbackStyle: const TextStyle(fontSize: 16, height: 1.45),
      maxWidth: 600,
      textScaleFactor: 1,
    );

    final rects = layout.selectionRectsForRange(
      DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: layout.plainText.length,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    for (var index = 0; index < rects.length; index++) {
      for (var otherIndex = index + 1;
          otherIndex < rects.length;
          otherIndex++) {
        expect(
          _hasMeaningfulHorizontalOverlap(rects[index], rects[otherIndex]),
          isFalse,
        );
      }
    }
  });

  testWidgets(
      'quote renders without raw markdown marker and remains selectable', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
> Quoted line
> Next line
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final richTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Quoted line'),
    );
    final rawMarkdownFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('> Quoted line'),
    );

    expect(rawMarkdownFinder, findsNothing);

    final richText = tester.widget<RichText>(richTextFinder);
    final renderBox = tester.renderObject<RenderBox>(richTextFinder);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);

    final startOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 0),
      Rect.zero,
    );
    final endOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 6),
      Rect.zero,
    );
    final start = renderBox.localToGlobal(startOffset + const Offset(1, 8));
    final end = renderBox.localToGlobal(endOffset + const Offset(1, 8));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Quoted');

    final paintFinder = find.ancestor(
      of: richTextFinder,
      matching: find.byType(CustomPaint),
    );
    expect(
      tester.widget<CustomPaint>(paintFinder.first).foregroundPainter,
      isNotNull,
    );
  });

  testWidgets('nested quotes with headings remain selectable', (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
> # Heading
>
> Intro line
>
> > Nested line
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final headingFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('Heading'),
    );
    final nestedFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Nested line'),
    );

    final start = tester.getTopLeft(headingFinder.first) + const Offset(2, 10);
    final end = tester.getTopRight(nestedFinder.first) + const Offset(-2, 10);
    final quoteFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Heading') &&
          widget.spec.plainText.contains('Nested line'),
    );
    final quoteWidget = tester.widget<SelectableMarkdownBlock>(quoteFinder);
    final quoteElement = tester.element(quoteFinder);
    final quoteRenderBox = tester.renderObject<RenderBox>(quoteFinder);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final selectionRange = selectionController.normalizedRange!;
    final selectionRects = quoteWidget.spec.selectionRectResolver!.call(
      quoteElement,
      quoteRenderBox.size,
      selectionRange,
    );
    final quoteOrigin = quoteRenderBox.localToGlobal(Offset.zero);
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(quoteOrigin))
        .toList(growable: false);
    final headingRenderBox =
        tester.renderObject<RenderBox>(headingFinder.first);
    final headingRect =
        headingRenderBox.localToGlobal(Offset.zero) & headingRenderBox.size;
    final nestedRenderBox = tester.renderObject<RenderBox>(nestedFinder.first);
    final nestedRect =
        nestedRenderBox.localToGlobal(Offset.zero) & nestedRenderBox.size;

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, contains('Heading'));
    expect(selectionController.selectedPlainText, contains('Nested line'));
    expect(selectionController.selectedPlainText, isNot(contains('>')));
    expect(globalSelectionRects, hasLength(3));
    expect(
      globalSelectionRects.first.overlaps(headingRect.deflate(1)),
      isTrue,
    );
    expect(
      globalSelectionRects.last.overlaps(nestedRect.deflate(1)),
      isTrue,
    );
    expect(
        globalSelectionRects.first.center.dy, lessThan(nestedRect.center.dy));
    expect(globalSelectionRects.last.center.dy,
        greaterThan(headingRect.center.dy));
  });

  testWidgets(
      'quoted code blocks merge adjacent syntax-highlight selection boxes', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
> ```python
> for i in range(3):
>     print(i)
> ```
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final quoteFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('for i in range(3):'),
    );
    final quoteWidget = tester.widget<SelectableMarkdownBlock>(quoteFinder);
    final quoteElement = tester.element(quoteFinder);
    final quoteRenderBox = tester.renderObject<RenderBox>(quoteFinder);
    final lineTextFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('for i in range(3):'),
    );
    final lineRenderBox = tester.renderObject<RenderBox>(lineTextFinder.first);
    final lineRect =
        lineRenderBox.localToGlobal(Offset.zero) & lineRenderBox.size;

    final selectionRects = quoteWidget.spec.selectionRectResolver!.call(
      quoteElement,
      quoteRenderBox.size,
      DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: quoteWidget.spec.plainText.length,
        ),
      ),
    );
    final quoteOrigin = quoteRenderBox.localToGlobal(Offset.zero);
    final globalRects = selectionRects
        .map((rect) => rect.shift(quoteOrigin))
        .where(
          (rect) =>
              rect.bottom > lineRect.top + 1 && rect.top < lineRect.bottom - 1,
        )
        .toList(growable: false);

    for (var index = 0; index < globalRects.length; index++) {
      for (var otherIndex = index + 1;
          otherIndex < globalRects.length;
          otherIndex++) {
        expect(
          _hasMeaningfulHorizontalOverlap(
            globalRects[index],
            globalRects[otherIndex],
          ),
          isFalse,
        );
      }
    }
  });

  testWidgets(
      'quote gap below a list keeps downward selection anchored at the list end',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
> - First item
> - Second item
>
> After block
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final secondFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Second item'),
    );
    final afterFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('After block'),
    );
    final quoteFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Second item') &&
          widget.spec.plainText.contains('After block'),
    );
    final quoteWidget = tester.widget<SelectableMarkdownBlock>(quoteFinder);
    final quoteElement = tester.element(quoteFinder);
    final quoteRenderBox = tester.renderObject<RenderBox>(quoteFinder);
    final secondRenderBox = tester.renderObject<RenderBox>(secondFinder.first);
    final secondRect =
        secondRenderBox.localToGlobal(Offset.zero) & secondRenderBox.size;
    final afterRenderBox = tester.renderObject<RenderBox>(afterFinder.first);
    final afterRect =
        afterRenderBox.localToGlobal(Offset.zero) & afterRenderBox.size;
    final secondItemPoint = Offset(
      secondRect.right - 2,
      secondRect.center.dy,
    );
    final gapPoint = Offset(
      secondRect.center.dx,
      (secondRect.bottom + afterRect.top) / 2,
    );
    final secondItemOffset = quoteWidget.spec.textOffsetResolver!(
      quoteElement,
      quoteRenderBox.size,
      quoteRenderBox.globalToLocal(secondItemPoint),
    );
    final gapOffset = quoteWidget.spec.textOffsetResolver!(
      quoteElement,
      quoteRenderBox.size,
      quoteRenderBox.globalToLocal(gapPoint),
    );
    final afterOffset = quoteWidget.spec.plainText.indexOf('After block');

    expect(secondItemOffset, isNotNull);
    expect(gapOffset, isNotNull);

    final resolvedSecondItemOffset = secondItemOffset!;
    final resolvedGapOffset = gapOffset!;
    expect(resolvedSecondItemOffset, greaterThan(0));
    expect(resolvedGapOffset, greaterThanOrEqualTo(resolvedSecondItemOffset));
    expect(resolvedGapOffset, lessThanOrEqualTo(afterOffset));
  });

  testWidgets('nested lists keep selection backgrounds aligned to item text', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
- Parent item
  - Nested child
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final parentFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Parent item'),
    );
    final nestedFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Nested child'),
    );

    final start = tester.getTopLeft(parentFinder.first) + const Offset(2, 10);
    final end = tester.getTopRight(nestedFinder.first) + const Offset(-2, 10);
    final listFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Parent item') &&
          widget.spec.plainText.contains('Nested child'),
    );
    final listWidget = tester.widget<SelectableMarkdownBlock>(listFinder);
    final listElement = tester.element(listFinder);
    final listRenderBox = tester.renderObject<RenderBox>(listFinder);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final selectionRange = selectionController.normalizedRange!;
    final selectionRects = listWidget.spec.selectionRectResolver!.call(
      listElement,
      listRenderBox.size,
      selectionRange,
    );
    final listOrigin = listRenderBox.localToGlobal(Offset.zero);
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(listOrigin))
        .toList(growable: false);
    final parentRenderBox = tester.renderObject<RenderBox>(parentFinder.first);
    final parentRect =
        parentRenderBox.localToGlobal(Offset.zero) & parentRenderBox.size;
    final nestedRenderBox = tester.renderObject<RenderBox>(nestedFinder.first);
    final nestedRect =
        nestedRenderBox.localToGlobal(Offset.zero) & nestedRenderBox.size;

    bool hasAlignedRect(Rect textRect) {
      return globalSelectionRects.any(
        (rect) =>
            rect.bottom > textRect.top &&
            rect.top < textRect.bottom &&
            rect.right > textRect.left &&
            rect.left < textRect.right,
      );
    }

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, contains('Parent item'));
    expect(selectionController.selectedPlainText, contains('Nested'));
    expect(hasAlignedRect(parentRect), isTrue);
    expect(hasAlignedRect(nestedRect), isTrue);
  });

  testWidgets('dragging inside an image caption selects caption text', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '![Caption text](missing-image.png?w=400&h=200)',
            selectionController: selectionController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final captionFinder = find.text('Caption text');
    final start = tester.getTopLeft(captionFinder) + const Offset(1, 8);
    final end = tester.getTopRight(captionFinder) + const Offset(-1, 8);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Caption text');
  });

  testWidgets(
      'dragging inside an image caption with unknown size selects caption text',
      (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '![Caption text](missing-image.png)',
            selectionController: selectionController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final captionFinder = find.text('Caption text');
    expect(captionFinder, findsOneWidget);

    final start = tester.getTopLeft(captionFinder) + const Offset(1, 4);
    final end = tester.getTopRight(captionFinder) + const Offset(-1, 4);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Caption text');
  });

  testWidgets('custom imageBuilder blocks participate in selection', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '![Custom caption](missing-image.png?w=400&h=200)',
            selectionController: selectionController,
            imageBuilder: (context, block, theme) {
              return Container(
                key: const ValueKey('custom-image'),
                width: 120,
                height: 48,
                color: Colors.blue,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final imageFinder = find.byKey(const ValueKey('custom-image'));
    final start = tester.getTopLeft(imageFinder) + const Offset(2, 12);
    final end = tester.getTopRight(imageFinder) + const Offset(-2, 12);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Custom caption');
  });

  testWidgets('dragging across table cells copies TSV selection',
      (tester) async {
    String? copiedText;
    final selectionController = MarkdownSelectionController();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final arguments = methodCall.arguments as Map<Object?, Object?>;
        copiedText = arguments['text'] as String?;
      }
      return null;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
| Name | Value |
| --- | --- |
| row | 42 |
| next | 7 |
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final start =
        tester.getRect(find.text('Name')).centerLeft + const Offset(-1, 0);
    final end =
        tester.getRect(find.text('42')).centerRight + const Offset(1, 0);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Name\tValue\nrow\t42');

    await selectionController.copySelectionToClipboard();
    await tester.pump();

    expect(copiedText, 'Name\tValue\nrow\t42');
  });

  testWidgets('triple click inside a table selects only the active cell', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
| Name | Value |
| --- | --- |
| row | 42 |
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.text('42'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '42');
  });

  testWidgets(
      'triple click inside a table cell with inline math selects the whole cell',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'''
| Feature | Description | Status |
| :--- | :---: | ---: |
| **Math** | Full LaTeX parsing & rendering (\( \alpha^2 \)) | ✅ |
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.textContaining('LaTeX'));

    await _tripleTapAt(tester, target);

    expect(selectionController.hasSelection, isTrue);
    expect(
      selectionController.selectedPlainText,
      contains('Full LaTeX parsing & rendering'),
    );
    expect(selectionController.selectedPlainText, contains(r'\alpha^2'));
    expect(selectionController.selectedPlainText, isNot(contains('\t')));
    expect(selectionController.selectedPlainText, isNot(contains('\n')));
  });

  testWidgets(
      'table block refreshes cached selection visuals when the selection range changes',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
| Name | Value |
| --- | --- |
| row | 42 |
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final tableBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText == 'Name\tValue\nrow\t42',
    );
    expect(tableBlockFinder, findsOneWidget);

    selectionController.setSelection(
      const DocumentSelection(
        base: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        extent: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 4,
        ),
      ),
    );
    await tester.pump();

    var tableBlock = tester.widget<SelectableMarkdownBlock>(tableBlockFinder);
    expect(tableBlock.selectionRange, isNotNull);
    expect(tableBlock.selectionRange!.start.textOffset, 0);
    expect(tableBlock.selectionRange!.end.textOffset, 4);

    selectionController.setSelection(
      const DocumentSelection(
        base: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 15,
        ),
        extent: DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 17,
        ),
      ),
    );
    await tester.pump();

    tableBlock = tester.widget<SelectableMarkdownBlock>(tableBlockFinder);
    expect(tableBlock.selectionRange, isNotNull);
    expect(tableBlock.selectionRange!.start.textOffset, 15);
    expect(tableBlock.selectionRange!.end.textOffset, 17);
  });

  testWidgets('triple click inside wrapped paragraph selects the current line',
      (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              child: MarkdownWidget(
                data: 'alpha  \nbeta  \ngamma',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final paragraphFinder = find.textContaining('alpha', findRichText: true);
    final rect = tester.getRect(paragraphFinder);
    final target = Offset(rect.center.dx, rect.top + rect.height / 2);

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'beta');
  });

  testWidgets(
      'triple click on wrapped kbd paragraph selects only the first visual line',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 170,
              child: MarkdownWidget(
                data:
                    'Press <kbd>Ctrl</kbd> + <kbd>C</kbd> to copy the current selection quickly.',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains(
              'Press Ctrl + C to copy the current selection quickly.'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockElement = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);

    final fullRects = block.spec.selectionRectResolver!(
      blockElement,
      blockRenderBox.size,
      DocumentRange(
        start: const DocumentPosition(
          blockIndex: 0,
          path: PathInBlock(<int>[0]),
          textOffset: 0,
        ),
        end: DocumentPosition(
          blockIndex: 0,
          path: const PathInBlock(<int>[0]),
          textOffset: block.spec.plainText.length,
        ),
      ),
    )..sort((a, b) {
        final topCompare = a.top.compareTo(b.top);
        if (topCompare != 0) {
          return topCompare;
        }
        return a.left.compareTo(b.left);
      });

    expect(fullRects.length, greaterThanOrEqualTo(2));

    bool sameVisualLine(Rect a, Rect b) {
      return (a.top - b.top).abs() <= 1.0 && (a.bottom - b.bottom).abs() <= 1.0;
    }

    final firstLineRects = fullRects
        .where((rect) => sameVisualLine(rect, fullRects.first))
        .toList(growable: false);
    final secondLineAnchor =
        fullRects.firstWhere((rect) => !sameVisualLine(rect, fullRects.first));
    final secondLineRects = fullRects
        .where((rect) => sameVisualLine(rect, secondLineAnchor))
        .toList(growable: false);
    final secondLineTop =
        secondLineRects.map((rect) => rect.top).reduce(math.min);
    final secondLineStartOffset = block.spec.textOffsetResolver!(
      blockElement,
      blockRenderBox.size,
      Offset(secondLineRects.first.left + 1, secondLineRects.first.center.dy),
    );

    final target = blockRenderBox.localToGlobal(firstLineRects.first.center);

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText.length,
        lessThan(block.spec.plainText.length));

    final selectionRange = selectionController.normalizedRange!;
    expect(secondLineStartOffset, isNotNull);
    expect(
      selectionRange.end.textOffset,
      lessThanOrEqualTo(secondLineStartOffset!),
    );

    final selectionRects = block.spec.selectionRectResolver!(
      blockElement,
      blockRenderBox.size,
      selectionRange,
    );
    expect(selectionRects, isNotEmpty);
    for (final rect in selectionRects) {
      expect(rect.bottom, lessThanOrEqualTo(secondLineTop + 0.5));
    }
  });

  testWidgets(
      'double click on copy and triple click on second line work for wrapped kbd sentence',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    const markdown =
        'You can also use HTML tags like `<kbd>` depending on your parser config: Press <kbd>Ctrl</kbd> + <kbd>C</kbd> to copy.';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final baseTheme = MarkdownThemeData.fallback(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 1280,
                  child: MarkdownWidget(
                    data: markdown,
                    padding: EdgeInsets.zero,
                    selectionController: selectionController,
                    theme: baseTheme.copyWith(
                      maxContentWidth: 1400,
                      bodyStyle: baseTheme.bodyStyle.copyWith(
                        fontSize: 16,
                        height: 1.25,
                      ),
                      inlineCodeStyle: baseTheme.inlineCodeStyle.copyWith(
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains(
            'You can also use HTML tags like <kbd> depending on your parser config: Press Ctrl + C to copy.',
          ),
    );
    expect(blockFinder, findsOneWidget);

    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final blockElement = tester.element(blockFinder);
    final blockRenderBox = tester.renderObject<RenderBox>(blockFinder);
    final pretextFinder = find.descendant(
      of: blockFinder,
      matching: find.byType(MarkdownPretextTextBlock),
    );
    expect(pretextFinder, findsOneWidget);
    final columnFinder = find.descendant(
      of: pretextFinder,
      matching: find.byType(Column),
    );
    expect(columnFinder, findsOneWidget);
    final lineBoxes = tester
        .renderObjectList<RenderBox>(
          find.descendant(of: columnFinder, matching: find.byType(SizedBox)),
        )
        .toList(growable: false);
    expect(lineBoxes, hasLength(2));

    final copyStart = block.spec.plainText.lastIndexOf('copy');
    final firstLineGlobalRect =
        lineBoxes.first.localToGlobal(Offset.zero) & lineBoxes.first.size;
    final secondLineGlobalRect =
        lineBoxes[1].localToGlobal(Offset.zero) & lineBoxes[1].size;
    final firstLineBottom =
        blockRenderBox.globalToLocal(firstLineGlobalRect.bottomLeft).dy;
    final secondLineRect = Rect.fromPoints(
      blockRenderBox.globalToLocal(secondLineGlobalRect.topLeft),
      blockRenderBox.globalToLocal(secondLineGlobalRect.bottomRight),
    );
    final copyEnd = copyStart + 'copy'.length;
    Offset? copyLocalTarget;
    final sampleWidth = math.max(secondLineGlobalRect.width - 4, 1.0);
    for (var step = 0; step <= 200; step++) {
      final ratio = step / 200;
      final sampleGlobal = Offset(
        secondLineGlobalRect.right - 2 - sampleWidth * ratio,
        secondLineGlobalRect.center.dy,
      );
      final sample = blockRenderBox.globalToLocal(sampleGlobal);
      final resolvedOffset = block.spec.textOffsetResolver!(
        blockElement,
        blockRenderBox.size,
        sample,
      );
      if (resolvedOffset != null &&
          resolvedOffset >= copyStart &&
          resolvedOffset <= copyEnd) {
        copyLocalTarget = sample;
        break;
      }
    }
    expect(copyLocalTarget, isNotNull,
        reason:
            'Expected to resolve a hit target for copy on the second rendered line.');
    final copyTarget = blockRenderBox.localToGlobal(copyLocalTarget!);

    await _doubleTapAt(tester, copyTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'copy');
    final wordSelection = selectionController.normalizedRange!;
    expect(wordSelection.start.textOffset, copyStart);
    expect(wordSelection.end.textOffset, copyStart + 'copy'.length);

    selectionController.clear();
    await tester.pump();

    final secondLineStart = block.spec.textOffsetResolver!(
      blockElement,
      blockRenderBox.size,
      Offset(secondLineRect.left + 1, secondLineRect.center.dy),
    );
    final secondLineEnd = block.spec.textOffsetResolver!(
      blockElement,
      blockRenderBox.size,
      Offset(secondLineRect.right - 1, secondLineRect.center.dy),
    );
    expect(secondLineStart, isNotNull);
    expect(secondLineEnd, isNotNull);
    final secondLineStartOffset = secondLineStart!;
    final secondLineEndOffset = secondLineEnd!;
    expect(secondLineStartOffset, greaterThan(0));
    expect(secondLineEndOffset, greaterThan(secondLineStartOffset));
    final expectedSecondLine = block.spec.plainText
        .substring(secondLineStartOffset, secondLineEndOffset)
        .trimRight();
    final tripleTarget = blockRenderBox.localToGlobal(
      Offset(secondLineRect.center.dx, secondLineRect.center.dy),
    );

    await _tripleTapAt(tester, tripleTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, expectedSecondLine);
    final lineSelection = selectionController.normalizedRange!;
    expect(
      lineSelection.start.textOffset,
      greaterThanOrEqualTo(secondLineStartOffset),
    );
    expect(
      lineSelection.end.textOffset,
      lessThanOrEqualTo(secondLineEndOffset),
    );

    final selectionRects = block.spec.selectionRectResolver!(
      blockElement,
      blockRenderBox.size,
      selectionController.normalizedRange!,
    );
    expect(selectionRects, isNotEmpty);
    for (final rect in selectionRects) {
      expect(rect.top, greaterThanOrEqualTo(firstLineBottom - 0.5));
    }
  });

  testWidgets('triple click inside code block with empty lines stays on line',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
```python
def test_edge_case():
    # Notice the selection corners on the empty lines below:
    
    
    print("Empty lines inside code blocks shouldn't break corner heuristics!")
```
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('def test_edge_case():') &&
          widget.spec.plainText.contains(
            'print("Empty lines inside code blocks shouldn\'t break corner heuristics!")',
          ),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final defStart = block.spec.plainText.indexOf('def test_edge_case():');
    final defRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: defStart,
        end: defStart + 'def test_edge_case():'.length,
      ),
    );
    final defTarget = defRect.center;
    await _tripleTapAt(tester, defTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'def test_edge_case():');

    selectionController.clear();
    await tester.pump();

    final printStart = block.spec.plainText.indexOf('print("Empty lines');
    final printRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: printStart,
        end: printStart + 'print("Empty lines'.length,
      ),
    );
    final printTarget = printRect.center;
    await _tripleTapAt(tester, printTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(
      selectionController.selectedPlainText,
      '    print("Empty lines inside code blocks shouldn\'t break corner heuristics!")',
    );
  });

  testWidgets('triple click inside a code block does not throw',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
```dart
const value = 42;
return value;
```
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.textContaining('const value'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(selectionController.hasSelection, isTrue);
  });

  testWidgets('triple click inside a rich list item selects the current item',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
* *Italicized text*
* **Bold emphasis**
* ***Bold and italic***
* ~~Strikethrough~~
* `inline code snippets`
* Link to [Flutter](https://flutter.dev), and an auto-link: <https://github.com>
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.text('Bold emphasis'));

    await _tripleTapAt(tester, target);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '- Bold emphasis');
  });

  testWidgets(
      'double click on blank area after a rich list line selects that line',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              child: MarkdownWidget(
                data: '''
* *Italicized text*
* **Bold emphasis**
* ***Bold and italic***
* ~~Strikethrough~~
* `inline code snippets`
* Link to [Flutter](https://flutter.dev), and an auto-link: <https://github.com>
''',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final targetRect = tester.getRect(find.text('Bold emphasis'));
    final documentRect = tester.getRect(find.byType(Scaffold));
    final target = Offset(
      math.min(targetRect.right + 8, documentRect.right - 12),
      targetRect.center.dy,
    );

    await _doubleTapAt(tester, target);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '- Bold emphasis');
  });

  testWidgets(
      'triple click on a parent list item does not include its nested sublist',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
* Outer item
  * Inner item
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.text('Outer item'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '- Outer item');
  });

  testWidgets(
      'triple click inside a list item code block selects the code block only',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
* Parent item

      const child = 42;
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.textContaining('const child'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'const child = 42;');
  });

  testWidgets(
      'triple click on ordered list lead line selects the current visual line with marker',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              child: MarkdownWidget(
                data: r'''
### Lists containing advanced blocks

1.  **Code implementation:**
    Here is a quick way to compute a sum in JavaScript:
    
    ```javascript
    function sum(a, b) {
      return a + b;
    }
    console.log(sum(5, 10)); // 15
    ```

2.  **Mathematical definitions:**
    And here is the sum expressed mathematically:
    
    $$
    \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
    $$
    
    > Blockquotes can also live gracefully inside list items. The selection background will adapt to the indentation perfectly.
''',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Code implementation:') &&
          widget.spec.plainText.contains('Mathematical definitions:'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final leadStart = block.spec.plainText.indexOf('Code implementation:');
    final leadRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: leadStart,
        end: leadStart + 'Code implementation:'.length,
      ),
    );
    final target = leadRect.center;

    await _tripleTapAt(tester, target);

    expect(selectionController.hasSelection, isTrue);
    final selectionRange = selectionController.normalizedRange!;
    expect(selectionRange.start.path.segments, const <int>[0, 0]);
    expect(selectionRange.end.path.segments, const <int>[0, 1]);
    expect(selectionController.selectedPlainText, '1. Code implementation:');
  });

  testWidgets(
      'triple click on ordered list continuation sentence selects that full line',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1800, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 1500,
              child: MarkdownWidget(
                data: r'''
### Lists containing advanced blocks

1.  **Code implementation:**
    Here is a quick way to compute a sum in JavaScript:
    
    ```javascript
    function sum(a, b) {
      return a + b;
    }
    console.log(sum(5, 10)); // 15
    ```

2.  **Mathematical definitions:**
    And here is the sum expressed mathematically:
    
    $$
    \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
    $$
    
    > Blockquotes can also live gracefully inside list items. The selection background will adapt to the indentation perfectly.
''',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Code implementation:') &&
          widget.spec.plainText.contains(
            'Here is a quick way to compute a sum in JavaScript:',
          ),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final start = block.spec.plainText.indexOf(
      'Here is a quick way to compute a sum in JavaScript:',
    );
    final sentenceRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: start,
        end: start +
            'Here is a quick way to compute a sum in JavaScript:'.length,
      ),
    );
    final target = sentenceRect.center;

    await _tripleTapAt(tester, target);

    expect(selectionController.hasSelection, isTrue);
    final selectionRange = selectionController.normalizedRange!;
    expect(selectionRange.start.path.segments, const <int>[0, 1]);
    expect(selectionRange.end.path.segments, const <int>[0, 1]);
    expect(
      selectionController.selectedPlainText,
      'Here is a quick way to compute a sum in JavaScript:',
    );
  });

  testWidgets(
      'double click on ordered list continuation text selects the tapped word',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: MarkdownWidget(
                data: '''
1. **Code implementation:**
    Here is a quick way to compute a sum in JavaScript:

    ```javascript
    function sum(a, b) {
      return a + b;
    }
    console.log(sum(5, 10)); // 15
    ```
''',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final sentenceFinder =
        find.textContaining('Here is a quick way', findRichText: true);
    final richText = tester.widget<RichText>(sentenceFinder.first);
    final renderBox = tester.renderObject<RenderBox>(sentenceFinder.first);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);
    final sentenceText = richText.text.toPlainText();
    final quickStart = sentenceText.indexOf('quick');
    final quickEnd = quickStart + 'quick'.length;
    final quickStartOffset = painter.getOffsetForCaret(
      TextPosition(offset: quickStart),
      Rect.zero,
    );
    final quickEndOffset = painter.getOffsetForCaret(
      TextPosition(offset: quickEnd),
      Rect.zero,
    );
    final target = renderBox.localToGlobal(
      Offset(
        (quickStartOffset.dx + quickEndOffset.dx) / 2,
        quickStartOffset.dy + painter.preferredLineHeight / 2,
      ),
    );

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    final selectionRange = selectionController.normalizedRange!;
    expect(selectionRange.start.path.segments, const <int>[0, 1]);
    expect(selectionRange.end.path.segments, const <int>[0, 1]);
    expect(selectionController.selectedPlainText, 'quick');
  });

  testWidgets(
      'triple click on ordered list continuation text selects the current visual line',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: MarkdownWidget(
                data: '''
1. **Code implementation:**
    Here is a quick way to compute a sum in JavaScript:

    ```javascript
    function sum(a, b) {
      return a + b;
    }
    console.log(sum(5, 10)); // 15
    ```
''',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final sentenceFinder =
        find.textContaining('Here is a quick way', findRichText: true);
    final richText = tester.widget<RichText>(sentenceFinder.first);
    final renderBox = tester.renderObject<RenderBox>(sentenceFinder.first);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);
    final sentenceText = richText.text.toPlainText();
    final quickStart = sentenceText.indexOf('quick');
    final quickEnd = quickStart + 'quick'.length;
    final expectedLineBoundary = painter.getLineBoundary(
      TextPosition(offset: quickStart),
    );
    final expectedLine = sentenceText.substring(
      expectedLineBoundary.start,
      expectedLineBoundary.end,
    );
    final quickStartOffset = painter.getOffsetForCaret(
      TextPosition(offset: quickStart),
      Rect.zero,
    );
    final quickEndOffset = painter.getOffsetForCaret(
      TextPosition(offset: quickEnd),
      Rect.zero,
    );
    final target = renderBox.localToGlobal(
      Offset(
        (quickStartOffset.dx + quickEndOffset.dx) / 2,
        quickStartOffset.dy + painter.preferredLineHeight / 2,
      ),
    );

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    final selectionRange = selectionController.normalizedRange!;
    expect(selectionRange.start.path.segments, const <int>[0, 1]);
    expect(selectionRange.end.path.segments, const <int>[0, 1]);
    expect(selectionController.selectedPlainText, expectedLine);
  });

  testWidgets(
      'triple click on fenced code inside ordered list selects the current code line',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: MarkdownWidget(
                data: '''
1. **Code implementation:**
    Here is a quick way to compute a sum in JavaScript:

    ```javascript
    function sum(a, b) {
      return a + b;
    }
    console.log(sum(5, 10)); // 15
    ```
''',
                selectionController: selectionController,
              ),
            ),
          ),
        ),
      ),
    );

    final codeFinder = find.textContaining('function sum', findRichText: true);
    final codeRect = tester.getRect(codeFinder);
    final target = Offset(
      codeRect.left + 120,
      codeRect.top + codeRect.height * 0.42,
    );

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '  return a + b;');

    // Verify selection background rects are within the selected code line.
    final listFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Code implementation'),
    );
    final listWidget = tester.widget<SelectableMarkdownBlock>(listFinder);
    final listElement = tester.element(listFinder);
    final listRenderBox = tester.renderObject<RenderBox>(listFinder);
    final selectionRange = selectionController.normalizedRange!;
    final selectionRects = listWidget.spec.selectionRectResolver!.call(
      listElement,
      listRenderBox.size,
      selectionRange,
    );
    expect(selectionRects, isNotEmpty);

    final listOrigin = listRenderBox.localToGlobal(Offset.zero);
    final globalSelectionRects = selectionRects
        .map((rect) => rect.shift(listOrigin))
        .toList(growable: false);

    // The selection rects must overlap the "return a + b" line vertically.
    final codeRenderBox = tester.renderObject<RenderBox>(codeFinder);
    final codeTextRect =
        codeRenderBox.localToGlobal(Offset.zero) & codeRenderBox.size;

    // Compute the vertical band of the "return a + b;" line by using
    // proportional line height within the code block text widget.
    // The code block has 4 lines; "return a + b;" is the second line.
    final lineHeight = codeTextRect.height / 4;
    final returnLineTop = codeTextRect.top + lineHeight;
    final returnLineBottom = codeTextRect.top + lineHeight * 2;

    for (final rect in globalSelectionRects) {
      expect(
        rect.top >= returnLineTop - 2 && rect.bottom <= returnLineBottom + 2,
        isTrue,
        reason: 'Selection rect $rect should be within the "return a + b;" '
            'line band ($returnLineTop..$returnLineBottom), '
            'but extends outside it.',
      );
    }
  });

  testWidgets('triple click inside a quote selects the current quoted block', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
> First quoted paragraph
>
> Second quoted paragraph
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.text('Second quoted paragraph'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    final selectionRange = selectionController.normalizedRange!;
    expect(selectionRange.start.path.segments, const <int>[1]);
    expect(selectionRange.end.path.segments, const <int>[1]);
    expect(selectionController.selectedPlainText, 'Second quoted paragraph');
  });

  testWidgets('triple click inside a nested list selects the innermost item', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
* Outer item
  * Inner item
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.text('Inner item'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    final selectionRange = selectionController.normalizedRange!;
    expect(selectionRange.start.path.segments, const <int>[0, 2, 0, 0]);
    expect(selectionRange.end.path.segments, const <int>[0, 2, 0, 1]);
    expect(selectionController.selectedPlainText, '  - Inner item');
  });

  testWidgets('nested list line clicks stay on Fruit and Banana rows', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
*   **Fruit**
    *   Apple
    *   Banana
        *   Cavendish
        *   Plantain
*   **Vegetables**
    1.  Carrot
    2.  Broccoli
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final blockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Fruit') &&
          widget.spec.plainText.contains('Vegetables'),
    );
    final block = tester.widget<SelectableMarkdownBlock>(blockFinder);
    final fruitStart = block.spec.plainText.indexOf('Fruit');
    final fruitRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: fruitStart,
        end: fruitStart + 'Fruit'.length,
      ),
    );
    final fruitTarget = fruitRect.center;
    await _tripleTapAt(tester, fruitTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '- Fruit');

    selectionController.clear();
    await tester.pump();

    final appleStart = block.spec.plainText.indexOf('Apple');
    final appleRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: appleStart,
        end: appleStart + 'Apple'.length,
      ),
    );
    final blockRect = tester.getRect(blockFinder);
    final appleBlankTarget = Offset(blockRect.right - 24, appleRect.center.dy);

    await _doubleTapAt(tester, appleBlankTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '  - Apple');

    final appleSelectionRects = block.spec.selectionRectResolver!(
      tester.element(blockFinder),
      tester.getSize(blockFinder),
      selectionController.normalizedRange!,
    );
    final blockOrigin = tester.getTopLeft(blockFinder);
    final globalAppleSelectionRects = appleSelectionRects
        .map((rect) => rect.shift(blockOrigin))
        .toList(growable: false);
    expect(globalAppleSelectionRects, isNotEmpty);
    expect(
      globalAppleSelectionRects.any(
        (rect) =>
            rect.bottom > appleRect.top + 1 && rect.top < appleRect.bottom - 1,
      ),
      isTrue,
    );
    for (final rect in globalAppleSelectionRects) {
      expect(rect.top, lessThan(appleRect.bottom + 1));
      expect(rect.bottom, greaterThan(appleRect.top - 1));
    }

    selectionController.clear();
    await tester.pump();

    final bananaStart = block.spec.plainText.indexOf('Banana');
    final bananaRect = _mergedRect(
      _globalSelectionRectsForBlock(
        tester,
        blockFinder,
        start: bananaStart,
        end: bananaStart + 'Banana'.length,
      ),
    );
    final bananaTextTarget = bananaRect.center;
    final bananaBlankTarget =
        Offset(bananaRect.right + 2, bananaRect.center.dy);

    await _tripleTapAt(tester, bananaTextTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '  - Banana');

    selectionController.clear();
    await tester.pump();

    await _doubleTapAt(tester, bananaBlankTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '  - Banana');

    selectionController.clear();
    await tester.pump();

    await _tripleTapAt(tester, bananaBlankTarget);

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, '  - Banana');
  });

  testWidgets('triple click inside a nested quote selects the innermost quote',
      (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
> Outer quote
> > Inner quote
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final target = tester.getCenter(find.text('Inner quote'));

    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();
    await tester.tapAt(target);
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Inner quote');
  });

  testWidgets(
      'selection auto-scroll falls back to ancestor scrollables for shrink-wrapped markdown widgets',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    final outerScrollController = ScrollController();
    const targetLabel = 'Target message paragraph 1';

    String buildMessage(String label) => '''
$label

$label continued with more content for drag selection.

- bullet a
- bullet b
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: ListView(
              controller: outerScrollController,
              children: List<Widget>.generate(6, (index) {
                final label = index == 1 ? targetLabel : 'Message ${index + 1}';
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: MarkdownWidget(
                    data: buildMessage(label),
                    selectionController:
                        index == 1 ? selectionController : null,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    final outerListFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.controller == outerScrollController,
    );
    final start = tester.getCenter(find.text(targetLabel));
    final viewport = tester.getRect(outerListFinder);
    final end = Offset(start.dx, viewport.bottom + 80);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(outerScrollController.offset, greaterThan(0));
    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, contains(targetLabel));

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
      'ancestor auto-scroll stops when the current shrink-wrapped markdown is already fully visible',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    final outerScrollController = ScrollController();
    const targetLabel = 'Fully visible target';

    String buildMessage(String label) => '''
$label

$label continued.
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: ListView(
              controller: outerScrollController,
              children: List<Widget>.generate(10, (index) {
                final label = index == 1 ? targetLabel : 'Message ${index + 1}';
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: MarkdownWidget(
                    data: buildMessage(label),
                    selectionController:
                        index == 1 ? selectionController : null,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    final markdownFinder = find.ancestor(
      of: find.text(targetLabel),
      matching: find.byType(MarkdownWidget),
    );
    final markdownRect = tester.getRect(markdownFinder);
    final outerListFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.controller == outerScrollController,
    );
    final viewport = tester.getRect(outerListFinder);
    expect(markdownRect.bottom, lessThan(viewport.bottom));

    final start = tester.getCenter(find.text(targetLabel));
    final end = Offset(start.dx, viewport.bottom - 8);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(outerScrollController.offset, 0);
    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, contains(targetLabel));

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
      'ancestor auto-scroll stays idle for a fully visible chat-style markdown bubble',
      (tester) async {
    final outerScrollController = ScrollController();
    final selectionController = MarkdownSelectionController();

    Widget buildAssistantBubble(String text,
        {MarkdownSelectionController? controller}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.terminal_rounded)),
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: MarkdownWidget(
                  data: text,
                  selectionController: controller,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: ListView.builder(
              controller: outerScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: 8,
              itemBuilder: (context, index) {
                if (index == 1) {
                  return buildAssistantBubble(
                    'Visible bubble\n\nSecond paragraph.\n\n- bullet a\n- bullet b',
                    controller: selectionController,
                  );
                }
                return buildAssistantBubble('Message ${index + 1}');
              },
            ),
          ),
        ),
      ),
    );

    final outerListFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.controller == outerScrollController,
    );
    final markdownFinder = find.ancestor(
      of: find.text('Visible bubble'),
      matching: find.byType(MarkdownWidget),
    );
    final markdownRect = tester.getRect(markdownFinder);
    final viewportRect = tester.getRect(outerListFinder);
    expect(markdownRect.bottom, lessThan(viewportRect.bottom));

    final start = tester.getCenter(find.text('Visible bubble'));
    final end = Offset(start.dx, viewportRect.bottom - 6);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(outerScrollController.offset, 0);
    expect(selectionController.hasSelection, isTrue);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('selection auto-scroll ignores pointer moves after unmount', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
Line 1

Line 2
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final start = tester.getCenter(find.text('Line 1'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await gesture.moveTo(start + const Offset(0, 120));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('dragging into a table selects the table block content', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
Intro

| Name | Value |
| --- | --- |
| row | 42 |
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final start = tester.getTopLeft(find.text('Intro')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('42'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(
      selectionController.selectedPlainText,
      'Intro\n\nName\tValue\nrow\t42',
    );
  });

  testWidgets('dragging into a table only selects through the hovered cell', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
Intro

| Name | Value |
| --- | --- |
| row | 42 |
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final start = tester.getTopLeft(find.text('Intro')) + const Offset(1, 8);
    final end = tester.getBottomRight(find.text('Name'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Intro\n\nName');
  });

  testWidgets(
      'reverse dragging from following heading into a table keeps table selection rects visible',
      (tester) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: r'''
## 4. Complex Tables

Tables support varying alignments, complex cell contents, and inline styles.

| Feature | Description | Status |
| :--- | :---: | ---: |
| **Parsing** | Fast incremental markdown parsing | ✅ |
| **Selection** | Seamless multi-block text selection | ✅ |
| **Math** | Full LaTeX parsing & rendering (\( \alpha^2 \)) | ✅ |
| **Code** | Syntax highlighting with *re_highlight* | 🚀 Built |

## 5. Media & Links
''',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    final start = tester.getCenter(find.textContaining('Media & Links')) +
        const Offset(0, 4);
    final end = tester.getCenter(find.text('Feature'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasSelection, isTrue);
    expect(
      selectionController.selectedPlainText,
      contains('Description\tStatus'),
    );
    expect(
      selectionController.selectedPlainText,
      contains('Code\tSyntax highlighting with re_highlight\t🚀 Built'),
    );

    final tableBlockFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock &&
          widget.spec.plainText.contains('Feature\tDescription\tStatus'),
    );
    expect(tableBlockFinder, findsOneWidget);

    final tableBlock = tester.widget<SelectableMarkdownBlock>(tableBlockFinder);
    final selectionRange = selectionController.normalizedRange!;
    final blockRange = DocumentRange(
      start: DocumentPosition(
        blockIndex: tableBlock.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: selectionRange.start.blockIndex == tableBlock.blockIndex
            ? selectionRange.start.textOffset
            : 0,
      ),
      end: DocumentPosition(
        blockIndex: tableBlock.blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: selectionRange.end.blockIndex == tableBlock.blockIndex
            ? selectionRange.end.textOffset
            : tableBlock.spec.plainText.length,
      ),
    );

    final renderBox = tester.renderObject<RenderBox>(tableBlockFinder);
    final element = tester.element(tableBlockFinder);
    final selectionRects = tableBlock.spec.selectionRectResolver!(
      element,
      renderBox.size,
      blockRange,
    );
    expect(selectionRects, isNotEmpty);
  });

  testWidgets('footnote backreference markers are not rendered',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '''
Reference[^note]

[^note]: Footnote body
''',
          ),
        ),
      ),
    );

    expect(find.textContaining('Footnote body'), findsOneWidget);
    expect(find.text('↩'), findsNothing);
  });

  test('default image renderer falls back to local files', () async {
    final file = File(
      '${Directory.systemTemp.path}/mixin_markdown_widget_test_image.png',
    );
    await file.writeAsBytes(<int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      13,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      248,
      255,
      255,
      63,
      0,
      5,
      254,
      2,
      254,
      167,
      13,
      163,
      96,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    expect(resolveMarkdownLocalImageProvider(file.path), isA<FileImage>());
  });
}

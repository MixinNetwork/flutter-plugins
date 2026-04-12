import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/local_image_provider_io.dart';
import 'package:mixin_markdown_widget/src/render/pretext_text_block.dart';
import 'package:mixin_markdown_widget/src/render/selectable_block.dart';

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

  test('selection controller serializes table-cell selections as TSV', () {
    final controller = MarkdownController(
      data: '''
| Name | Value |
| --- | --- |
| row | 42 |
| next | 7 |
''',
    );
    final selectionController = MarkdownSelectionController()
      ..attachDocument(controller.document)
      ..setTableCellSelection(
        const TableCellSelection(
          blockIndex: 0,
          base: TableCellPosition(rowIndex: 1, columnIndex: 0),
          extent: TableCellPosition(rowIndex: 2, columnIndex: 1),
        ),
      );

    expect(selectionController.hasTableSelection, isTrue);
    expect(selectionController.selectedPlainText, 'row\t42\nnext\t7');
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

  testWidgets('renders math with flutter_math_fork and skips pretext', (
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
    expect(find.byType(MarkdownPretextTextBlock), findsNothing);
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

    final decoratedBoxes = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((widget) {
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == theme.inlineCodeBackgroundColor &&
          decoration.borderRadius == theme.inlineCodeBorderRadius;
    }).toList(growable: false);

    expect(decoratedBoxes, hasLength(1));

    final paddingFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Padding && widget.padding == theme.inlineCodePadding,
    );
    expect(paddingFinder, findsWidgets);
    expect(find.text('code'), findsOneWidget);
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

    final codeText = tester.widget<Text>(find.text('code'));
    expect(codeText.style?.fontFamily, 'Mono');
    expect(
      codeText.style?.fontFamilyFallback,
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
    final decoratedSegments = layout.lines
        .expand((line) => line.segments)
        .where((segment) => segment.decoration != null)
        .toList(growable: false);

    expect(decoratedSegments, isNotEmpty);
    expect(
      decoratedSegments.every((segment) => segment.padding == padding),
      isTrue,
    );
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
    expect(globalSelectionRects.first.top, closeTo(headingRect.top, 0.5));
    expect(globalSelectionRects.first.bottom, closeTo(headingRect.bottom, 0.5));
    expect(globalSelectionRects.last.top, closeTo(nestedRect.top, 0.5));
    expect(globalSelectionRects.last.bottom, closeTo(nestedRect.bottom, 0.5));
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
            data: '![Caption text](missing-image.png)',
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

  testWidgets('custom imageBuilder blocks participate in selection', (
    tester,
  ) async {
    final selectionController = MarkdownSelectionController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '![Custom caption](missing-image.png)',
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

    final start = tester.getCenter(find.text('Name'));
    final end = tester.getCenter(find.text('42'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: start);
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(selectionController.hasTableSelection, isTrue);
    expect(selectionController.selectedPlainText, 'Name\tValue\nrow\t42');

    await selectionController.copySelectionToClipboard();
    await tester.pump();

    expect(copiedText, 'Name\tValue\nrow\t42');
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
    final end = tester.getCenter(find.text('42'));
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
        selectionController.selectedPlainText, 'Intro\n\nName\tValue\nrow\t42');
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
    final end = tester.getCenter(find.text('Name'));
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

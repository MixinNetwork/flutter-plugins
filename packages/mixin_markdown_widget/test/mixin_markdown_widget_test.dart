import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

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
          widget.text.toPlainText().contains('• First item'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderBox = tester.renderObject<RenderBox>(richTextFinder);
    final painter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: renderBox.size.width);

    final startOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 2),
      Rect.zero,
    );
    final endOffset = painter.getOffsetForCaret(
      const TextPosition(offset: 7),
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
    expect(selectionController.selectedPlainText, isNotEmpty);
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
}

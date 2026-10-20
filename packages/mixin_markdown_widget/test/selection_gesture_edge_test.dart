// Pointer edge cases of the custom markdown selection.
//
// Each test drives real mouse gestures and pins the resulting selection as
// `base -> extent | "selected text"`, where a position is written as
// `block[path]@displayedOffset`.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/selectable_block.dart';

// Synthetic pointer events default to a zero timestamp, which would chain
// unrelated clicks into multi-clicks. Every interaction advances this clock.
Duration _clock = Duration.zero;

Duration _advance([Duration step = const Duration(seconds: 1)]) {
  return _clock += step;
}

Future<MarkdownSelectionController> _pump(
  WidgetTester tester,
  String data, {
  double height = 600,
  ScrollController? scrollController,
  MarkdownTapLinkCallback? onTapLink,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = MarkdownSelectionController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: height,
            child: MarkdownWidget(
              data: data,
              selectionController: controller,
              scrollController: scrollController,
              onTapLink: onTapLink,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Future<void> _click(WidgetTester tester, Offset at, {int count = 1}) async {
  var timeStamp = _advance();
  for (var index = 0; index < count; index++) {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: at, timeStamp: timeStamp);
    await gesture.down(at, timeStamp: timeStamp);
    await tester.pump();
    await gesture.up(timeStamp: timeStamp);
    await tester.pump();
    await gesture.removePointer(timeStamp: timeStamp);
    timeStamp = _advance(const Duration(milliseconds: 50));
  }
}

Future<void> _drag(
  WidgetTester tester,
  Offset from,
  Offset Function() to, {
  Future<void> Function()? beforeEnd,
}) async {
  final timeStamp = _advance();
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: from, timeStamp: timeStamp);
  await gesture.down(from, timeStamp: timeStamp);
  await tester.pump();
  await gesture.moveTo(from + const Offset(24, 0), timeStamp: timeStamp);
  await tester.pump();
  if (beforeEnd != null) {
    await beforeEnd();
  }
  await gesture.moveTo(to(), timeStamp: timeStamp);
  await tester.pump();
  await gesture.up(timeStamp: timeStamp);
  await tester.pump();
  await gesture.removePointer(timeStamp: timeStamp);
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  );
}

/// Global center of the [charIndex]th character of [text], measured on the
/// rendered paragraph that contains it.
Offset _charCenter(WidgetTester tester, String text, int charIndex) {
  final finder = _richTextContaining(text).first;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final plain = paragraph.text.toPlainText();
  final offset = plain.indexOf(text) + charIndex;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + 1),
  );
  expect(boxes, isNotEmpty, reason: 'no box for "$text"[$charIndex]');
  return paragraph.localToGlobal(boxes.first.toRect().center);
}

/// A global point on the right half of the [charIndex]th character of [text].
Offset _charRightHalf(WidgetTester tester, String text, int charIndex) {
  final finder = _richTextContaining(text).first;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final plain = paragraph.text.toPlainText();
  final offset = plain.indexOf(text) + charIndex;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: offset, extentOffset: offset + 1),
  );
  expect(boxes, isNotEmpty, reason: 'no box for "$text"[$charIndex]');
  final box = boxes.first.toRect();
  return paragraph.localToGlobal(Offset(box.right - 1, box.center.dy));
}

/// Records the text written to the clipboard; the getter returns the last.
String? Function() _captureClipboard() {
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
  return () => copiedText;
}

Future<void> _copy(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Global rect of the rendered characters of [text].
Rect _textRect(WidgetTester tester, String text) {
  final finder = _richTextContaining(text).first;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final plain = paragraph.text.toPlainText();
  final start = plain.indexOf(text);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + text.length),
  );
  expect(boxes, isNotEmpty, reason: 'no boxes for "$text"');
  var rect = boxes.first.toRect();
  for (final box in boxes.skip(1)) {
    rect = rect.expandToInclude(box.toRect());
  }
  return rect.shift(paragraph.localToGlobal(Offset.zero));
}

Rect _blockRect(WidgetTester tester, int index) {
  return tester.getRect(
    find.byWidgetPredicate(
      (widget) =>
          widget is SelectableMarkdownBlock && widget.blockIndex == index,
    ),
  );
}

String _describePosition(DocumentPosition position) {
  return '${position.blockIndex}${position.path.segments}'
      '@${position.textOffset}';
}

String _describe(MarkdownSelectionController controller) {
  final selection = controller.selection;
  if (selection == null) {
    return 'none';
  }
  final text = controller.selectedPlainText.replaceAll('\n', r'\n');
  return '${_describePosition(selection.base)} -> '
      '${_describePosition(selection.extent)} | "$text"';
}

void _expectSelection(
  MarkdownSelectionController controller,
  String expected,
) {
  expect(_describe(controller), expected);
}

void main() {
  group('gaps between child blocks', () {
    const quote = '> First paragraph\n>\n> Second paragraph';
    const list = '- First item\n\n  Second paragraph\n- Next item';

    for (final entry in <String, List<String>>{
      quote: <String>[
        '0[0]@0 -> 0[0]@8 | "First pa"',
        '0[0]@0 -> 0[0]@8 | "First pa"',
        '0[0]@0 -> 0[1]@25 | "First paragraph\\n\\nSecond p"'
      ],
      list: <String>[
        '0[0, 1]@2 -> 0[0, 1]@7 | "First"',
        '0[0, 1]@2 -> 0[0, 1]@7 | "First"',
        '0[0, 1]@2 -> 0[0, 2]@20 | "First item\\n  Secon"'
      ],
    }.entries) {
      final label = entry.key == quote ? 'quote' : 'list';
      final pointsInGap = <String, double Function(Rect, Rect)>{
        'just below the first child': (first, second) => first.bottom + 1,
        'at the gap midpoint': (first, second) =>
            (first.bottom + second.top) / 2,
        'just above the second child': (first, second) => second.top - 1,
      };
      var index = 0;
      for (final point in pointsInGap.entries) {
        final expected = entry.value[index++];
        testWidgets('$label: drag ending ${point.key}', (tester) async {
          final controller = await _pump(tester, entry.key);
          final first = _textRect(
            tester,
            entry.key == quote ? 'First paragraph' : 'First item',
          );
          final second = _textRect(tester, 'Second paragraph');
          await _drag(
            tester,
            first.centerLeft + const Offset(2, 0),
            () => Offset(first.center.dx, point.value(first, second)),
          );
          _expectSelection(controller, expected);
        });
      }
    }

    testWidgets('list: drag ending between two items', (tester) async {
      final controller = await _pump(tester, '- Alpha item\n- Beta item');
      final first = _textRect(tester, 'Alpha item');
      final second = _textRect(tester, 'Beta item');
      await _drag(
        tester,
        first.centerLeft + const Offset(2, 0),
        () => Offset(first.center.dx, (first.bottom + second.top) / 2),
      );
      _expectSelection(controller, '0[0, 1]@2 -> 0[1, 0]@12 | "Alpha item"');
    });
  });

  group('list markers', () {
    const data = '1. Alpha item\n2. Beta item';

    Offset markerOf(WidgetTester tester, String itemText) {
      final text = _textRect(tester, itemText);
      final block = _blockRect(tester, 0);
      return Offset((block.left + text.left) / 2, text.center.dy);
    }

    testWidgets('drag starting on a list marker', (tester) async {
      final controller = await _pump(tester, data);
      final end = _textRect(tester, 'Beta item');
      await _drag(
        tester,
        markerOf(tester, 'Beta item'),
        () => end.centerRight - const Offset(2, 0),
      );
      _expectSelection(controller, '0[1, 0]@14 -> 0[1, 1]@26 | "2. Beta item"');
    });

    testWidgets('drag ending on a list marker', (tester) async {
      final controller = await _pump(tester, data);
      final start = _textRect(tester, 'Alpha item');
      await _drag(
        tester,
        start.centerLeft + const Offset(2, 0),
        () => markerOf(tester, 'Beta item'),
      );
      _expectSelection(controller, '0[0, 1]@3 -> 0[1, 0]@14 | "Alpha item\\n"');
    });

    testWidgets('double click on a list marker', (tester) async {
      final controller = await _pump(tester, data);
      await _click(tester, markerOf(tester, 'Beta item'), count: 2);
      _expectSelection(controller, '0[1, 0]@14 -> 0[1, 0]@15 | "2"');
    });

    testWidgets('triple click on a list marker', (tester) async {
      final controller = await _pump(tester, data);
      await _click(tester, markerOf(tester, 'Beta item'), count: 3);
      _expectSelection(controller, '0[1, 0]@14 -> 0[1, 1]@26 | "2. Beta item"');
    });
  });

  group('pointer to the right of a line end', () {
    testWidgets('wrapped paragraph', (tester) async {
      final controller = await _pump(
        tester,
        'The quick brown fox jumps over the lazy dog while the selection '
        'geometry spans several wrapped lines of plain paragraph text.',
      );
      final block = _blockRect(tester, 0);
      final start = _charCenter(tester, 'The quick', 0);
      // The second rendered line spans y = 21..42 inside the block.
      await _drag(
        tester,
        start,
        () => Offset(block.right - 2, block.top + 31),
      );
      _expectSelection(controller,
          '0[0]@1 -> 0[0]@40 | "he quick brown fox jumps over the lazy "');
    });

    testWidgets('short list item', (tester) async {
      final controller = await _pump(tester, '- short\n- other item');
      final block = _blockRect(tester, 0);
      final start = _charCenter(tester, 'short', 0);
      await _drag(
        tester,
        start,
        () => Offset(block.right - 2, start.dy),
      );
      _expectSelection(controller, '0[0, 1]@3 -> 0[1, 0]@7 | "hort"');
    });

    testWidgets('table cell', (tester) async {
      final controller = await _pump(
        tester,
        '| Name | Value |\n| --- | --- |\n| ab | 42 |',
      );
      final start = _charCenter(tester, 'Name', 0);
      final cell = _textRect(tester, 'ab');
      await _drag(
        tester,
        start,
        () => Offset(cell.right + 8, cell.center.dy),
      );
      _expectSelection(
          controller, '0[0, 0]@1 -> 0[1, 1]@13 | "ame\tValue\\nab"');
    });
  });

  group('drag across top-level blocks', () {
    const data = 'Intro paragraph\n\n'
        '- one\n- two three\n\n'
        '> quoted text\n\n'
        '| alpha | beta |\n| - | - |\n| gamma | delta |';

    testWidgets('from a paragraph into a list item', (tester) async {
      final controller = await _pump(tester, data);
      await _drag(
        tester,
        _charCenter(tester, 'Intro', 1),
        () => _charCenter(tester, 'two three', 5),
      );
      _expectSelection(controller,
          '0[0]@2 -> 1[1, 1]@14 | "tro paragraph\\n\\n- one\\n- two th"');
    });

    testWidgets('from a quote into a table cell', (tester) async {
      final controller = await _pump(tester, data);
      await _drag(
        tester,
        _charCenter(tester, 'quoted', 2),
        () => _textRect(tester, 'delta').center,
      );
      _expectSelection(controller,
          '2[0]@3 -> 3[1, 1]@20 | "ted text\\n\\nalpha\tbeta\\ngamma\tdel"');
    });

    testWidgets('backwards from a table cell into a list item', (
      tester,
    ) async {
      final controller = await _pump(tester, data);
      await _drag(
        tester,
        _textRect(tester, 'gamma').center,
        () => _charCenter(tester, 'one', 1),
      );
      _expectSelection(controller,
          '3[1, 0]@14 -> 1[0, 1]@4 | "e\\n- two three\\n\\nquoted text\\n\\nalpha\tbeta\\ngam"');
    });

    testWidgets('ending in blank space below the document', (tester) async {
      final controller = await _pump(tester, data);
      await _drag(
        tester,
        _charCenter(tester, 'Intro', 0),
        () => const Offset(120, 560),
      );
      _expectSelection(controller,
          '0[0]@1 -> 3[1, 1]@22 | "ntro paragraph\\n\\n- one\\n- two three\\n\\nquoted text\\n\\nalpha\tbeta\\ngamma\tdelta"');
    });
  });

  group('double and triple click in nested blocks', () {
    const nestedList = '- Fruit\n  - Apple pie\n    - Green apple';
    const nestedQuote = '> # Title\n>\n> > inner quote words here';
    const table = '| Name | Value |\n| --- | --- |\n| row one | 42 |';

    final targets = <String, (String, String, int)>{
      'nested list': (nestedList, 'Apple pie', 7),
      'deep nested list': (nestedList, 'Green apple', 2),
      'nested quote': (nestedQuote, 'inner quote', 8),
      'quote heading': (nestedQuote, 'Title', 1),
      'table cell': (table, 'row one', 5),
    };
    final expected = <String, (String, String)>{
      'nested list': (
        '0[0, 2, 0, 1]@20 -> 0[0, 2, 0, 1]@23 | "pie"',
        '0[0, 2, 0, 0]@10 -> 0[0, 2, 0, 1]@23 | "  - Apple pie"'
      ),
      'deep nested list': (
        '0[0, 2, 0, 2, 0, 1]@36 -> 0[0, 2, 0, 2, 0, 1]@41 | "Green"',
        '0[0, 2, 0, 2, 0, 0]@30 -> 0[0, 2, 0, 2, 0, 1]@47 | "    - Green apple"'
      ),
      'nested quote': (
        '0[1, 0]@13 -> 0[1, 0]@18 | "quote"',
        '0[1, 0]@7 -> 0[1, 0]@25 | "inner quote words "'
      ),
      'quote heading': (
        '0[0]@0 -> 0[0]@5 | "Title"',
        '0[0]@0 -> 0[0]@5 | "Title"'
      ),
      'table cell': (
        '0[1, 0]@15 -> 0[1, 0]@18 | "one"',
        '0[1, 0]@11 -> 0[1, 0]@18 | "row one"'
      ),
    };

    for (final entry in targets.entries) {
      final (data, text, charIndex) = entry.value;
      testWidgets('double click in ${entry.key}', (tester) async {
        final controller = await _pump(tester, data);
        await _click(tester, _charCenter(tester, text, charIndex), count: 2);
        _expectSelection(controller, expected[entry.key]!.$1);
      });

      testWidgets('triple click in ${entry.key}', (tester) async {
        final controller = await _pump(tester, data);
        await _click(tester, _charCenter(tester, text, charIndex), count: 3);
        _expectSelection(controller, expected[entry.key]!.$2);
      });
    }
  });

  group('double click on the right half of the last character of a leaf', () {
    // The end offset of a leaf is also the start of the next one; the click
    // must select the word under the pointer, not the next leaf's word.
    const sparseTable = '| Alpha |       | Charlie |\n'
        '| ----- | ----- | ------- |\n'
        '|       | Bravo | z       |';

    testWidgets('table cell before an empty cell copies its word', (
      tester,
    ) async {
      final copiedText = _captureClipboard();
      final controller = await _pump(tester, sparseTable);
      await _click(tester, _charRightHalf(tester, 'Alpha', 4), count: 2);
      _expectSelection(controller, '0[0, 0]@0 -> 0[0, 0]@5 | "Alpha"');
      await _copy(tester);
      expect(copiedText(), 'Alpha');
    });

    final targets = <String, (String, String, int, String)>{
      'last cell of a table row': (
        sparseTable,
        'Charlie',
        6,
        '0[0, 2]@6 -> 0[0, 2]@13 | "Charlie"',
      ),
      'table cell after an empty cell': (
        sparseTable,
        'Bravo',
        4,
        '0[1, 1]@14 -> 0[1, 1]@19 | "Bravo"',
      ),
      'table cell before a filled cell': (
        '| Alpha | Bravo |\n| --- | --- |\n| x | y |',
        'Alpha',
        4,
        '0[0, 0]@0 -> 0[0, 0]@5 | "Alpha"',
      ),
      'quote paragraph': (
        '> First\n>\n> Second',
        'First',
        4,
        '0[0]@0 -> 0[0]@5 | "First"',
      ),
      'list item': (
        '- one\n- two',
        'one',
        2,
        '0[0, 1]@2 -> 0[0, 1]@5 | "one"',
      ),
      'list item before a nested list': (
        '- one\n  - two',
        'one',
        2,
        '0[0, 1]@2 -> 0[0, 1]@5 | "one"',
      ),
      'details summary': (
        '<details><summary>Sum</summary>\n\nBody text\n\n</details>',
        'Sum',
        2,
        '0[0]@0 -> 0[0]@3 | "Sum"',
      ),
    };
    for (final entry in targets.entries) {
      final (data, text, charIndex, expected) = entry.value;
      testWidgets(entry.key, (tester) async {
        final controller = await _pump(tester, data);
        await _click(
          tester,
          _charRightHalf(tester, text, charIndex),
          count: 2,
        );
        _expectSelection(controller, expected);
      });
    }

    testWidgets('left half of the first character of the next cell', (
      tester,
    ) async {
      final controller = await _pump(tester, sparseTable);
      final charlie = _textRect(tester, 'Charlie');
      await _click(tester, Offset(charlie.left + 1, charlie.center.dy),
          count: 2);
      _expectSelection(controller, '0[0, 2]@6 -> 0[0, 2]@13 | "Charlie"');
    });
  });

  group('link taps with selection enabled', () {
    final cases = <String, String>{
      'list': '- see [Link](https://list.example) here',
      'quote': '> see [Link](https://quote.example) here',
      'table': '| head |\n| --- |\n| see [Link](https://table.example) |',
    };
    for (final entry in cases.entries) {
      testWidgets('tapping a link inside a ${entry.key}', (tester) async {
        final tapped = <String>[];
        final controller = await _pump(
          tester,
          entry.value,
          onTapLink: (destination, title, label) => tapped.add(destination),
        );
        await _click(tester, _charCenter(tester, 'Link', 1));
        expect(tapped, <String>['https://${entry.key}.example']);
        expect(controller.hasSelection, isFalse);
      });
    }
  });

  testWidgets(
      'copying a drag selection that spans a block scrolled out of a ListView',
      (tester) async {
    final copiedText = _captureClipboard();
    final paragraphs = List<String>.generate(30, (index) => 'Paragraph $index');
    final expectedCopiedText = <String>[
      paragraphs.first.substring(3),
      ...paragraphs.sublist(1, 24),
      paragraphs[24].substring(0, 7),
    ].join('\n\n');
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final controller = await _pump(
      tester,
      paragraphs.join('\n\n'),
      height: 240,
      scrollController: scrollController,
    );

    await _drag(
      tester,
      _charCenter(tester, 'Paragraph 0', 2),
      () => _charCenter(tester, 'Paragraph 24', 6),
      beforeEnd: () async {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();
        expect(_richTextContaining('Paragraph 0'), findsNothing);
      },
    );
    _expectSelection(controller,
        '0[0]@3 -> 24[0]@7 | "${expectedCopiedText.replaceAll('\n', r'\n')}"');

    await _copy(tester);
    expect(copiedText(), expectedCopiedText);
  });
}

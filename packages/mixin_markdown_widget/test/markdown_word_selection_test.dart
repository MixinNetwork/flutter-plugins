import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/selectable_block.dart';

/// The separator-only word rule that ASCII text keeps.
({int start, int end}) _asciiWordRangeAt(String text, int offset) {
  const separators = r'.,;:!?()[]{}<>/\"' "'`|-+=*&";
  bool isWordCharacter(String character) =>
      character.trim().isNotEmpty && !separators.contains(character);
  var start = offset;
  var end = offset;
  while (start > 0 && isWordCharacter(text[start - 1])) {
    start -= 1;
  }
  while (end < text.length && isWordCharacter(text[end])) {
    end += 1;
  }
  return (start: start, end: end);
}

String _wordAt(String text, int offset) {
  final range = markdownWordRangeAt(text, offset);
  return text.substring(range.start, range.end);
}

Future<void> _doubleTapCharacter(
  WidgetTester tester, {
  required String containing,
  required String character,
}) async {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText().contains(containing),
  );
  final richText = tester.widget<RichText>(finder.first);
  final renderBox = tester.renderObject<RenderBox>(finder.first);
  final text = richText.text.toPlainText();
  final offset = text.indexOf(character);
  final painter = TextPainter(
    text: richText.text,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: renderBox.size.width);
  final box = painter
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .first
      .toRect();
  painter.dispose();
  final target = renderBox.localToGlobal(box.center);
  await tester.tapAt(target);
  await tester.pump();
  await tester.tapAt(target);
  await tester.pump();
}

/// Test pointer events carry no timestamps, so taps count as one series
/// until one lands far away.
Future<void> _resetTapCount(WidgetTester tester) async {
  await tester.tapAt(const Offset(780, 580));
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
}

void main() {
  testWidgets('ASCII text keeps the separator word rule', (tester) async {
    const text = "foo_bar baz-qux (x.y) #tag don't a+b café_au "
        'path/to/file.dart';
    for (var offset = 0; offset <= text.length; offset += 1) {
      final ascii = _asciiWordRangeAt(text, offset);
      if (text.substring(ascii.start, ascii.end).contains('é')) {
        continue;
      }
      expect(markdownWordRangeAt(text, offset), ascii, reason: '$offset');
    }
  });

  testWidgets('Chinese punctuation ends a word', (tester) async {
    const text = '你好，世界！再见。';
    for (final (offset, punctuation) in <(int, String)>[
      (0, '，'),
      (1, '，'),
      (3, '！'),
      (4, '！'),
      (6, '。'),
    ]) {
      final word = _wordAt(text, offset);
      expect(word, isNotEmpty);
      expect(word, isNot(contains(punctuation)));
      expect(word, contains(text[offset]));
    }
    // Right before a punctuation mark, as after an ASCII word.
    expect(_wordAt(text, 2), isNot(contains('，')));
    expect('你好', contains(_wordAt(text, 2)));
  });

  testWidgets('Chinese text breaks at dictionary words', (tester) async {
    const text = '我们使用Flutter开发桌面应用';
    for (final word in ['我们', '使用', 'Flutter', '开发', '桌面', '应用']) {
      final start = text.indexOf(word);
      for (var offset = start; offset < start + word.length; offset += 1) {
        expect(_wordAt(text, offset), word, reason: '$offset');
      }
      // The pointer on the right half of the word's last character.
      final end = start + word.length;
      final range = markdownWordRangeAt(text, end, upstream: true);
      expect(text.substring(range.start, range.end), word);
    }
  });

  testWidgets('double click selects a word in a Chinese paragraph',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    addTearDown(selectionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '我们使用Flutter开发桌面应用，效果很好。',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    await _doubleTapCharacter(
      tester,
      containing: '我们使用',
      character: 'F',
    );
    expect(selectionController.selectedPlainText, 'Flutter');

    await _resetTapCount(tester);
    await _doubleTapCharacter(
      tester,
      containing: '我们使用',
      character: '效',
    );
    expect(selectionController.selectedPlainText, '效果');

    await _resetTapCount(tester);
    await _doubleTapCharacter(
      tester,
      containing: '我们使用',
      character: '桌',
    );
    expect(selectionController.selectedPlainText, '桌面');
  });

  testWidgets('double click selects a word in Chinese list text',
      (tester) async {
    final selectionController = MarkdownSelectionController();
    addTearDown(selectionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWidget(
            data: '- 第一项：使用Flutter开发\n- 第二项',
            selectionController: selectionController,
          ),
        ),
      ),
    );

    await _doubleTapCharacter(
      tester,
      containing: '第一项',
      character: 'F',
    );
    expect(selectionController.selectedPlainText, 'Flutter');

    await _resetTapCount(tester);
    await _doubleTapCharacter(
      tester,
      containing: '第一项',
      character: '项',
    );
    expect(selectionController.selectedPlainText, isNot(contains('：')));
    expect(selectionController.selectedPlainText, contains('项'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:word_segmenter/word_segmenter.dart';

List<String> segmentsOf(String text) => [
      for (final range in wordBoundaries(text)!) range.textInside(text),
    ];

void main() {
  test('segments cover the text contiguously', () {
    for (final text in [
      'Hello, world!  foo-bar 1.5',
      '我们今天讨论一下流式输出，然后再看。',
      '👍🏽 ok 😀',
      'Flutter 桌面端 Markdown',
    ]) {
      final ranges = wordBoundaries(text)!;
      expect(ranges.first.start, 0, reason: text);
      expect(ranges.last.end, text.length, reason: text);
      for (var i = 0; i < ranges.length; i++) {
        expect(ranges[i].isCollapsed, isFalse, reason: text);
        if (i > 0) {
          expect(ranges[i].start, ranges[i - 1].end, reason: text);
        }
      }
    }
  });

  test('splits words, spaces and punctuation', () {
    expect(segmentsOf('Hello, world!'), ['Hello', ',', ' ', 'world', '!']);
  });

  test('splits Chinese into dictionary words', () {
    expect(
      segmentsOf('我们今天讨论一下'),
      containsAllInOrder(['我们', '今天', '讨论']),
    );
  });

  test('keeps emoji sequences together', () {
    expect(segmentsOf('👍🏽 ok'), ['👍🏽', ' ', 'ok']);
  });

  test('empty text has no segments', () {
    expect(wordBoundaries(''), isEmpty);
  });
}

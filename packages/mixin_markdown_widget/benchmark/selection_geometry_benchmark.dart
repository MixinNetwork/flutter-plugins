import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

void main() {
  testWidgets('selection geometry benchmark', (tester) async {
    final scenarios = <_BenchmarkScenario>[
      const _BenchmarkScenario(name: 'medium', sections: 30),
      const _BenchmarkScenario(name: 'large', sections: 90),
    ];
    const serializer = MarkdownPlainTextSerializer();

    stdout.writeln('mixin_markdown_widget selection geometry benchmark');

    for (final scenario in scenarios) {
      final data = _buildComplexMarkdown(sections: scenario.sections);
      final controller = MarkdownController(data: data);
      final selectionController = MarkdownSelectionController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownWidget(
              controller: controller,
              selectionController: selectionController,
            ),
          ),
        ),
      );
      await tester.pump();

      final ranges = _buildSelectionRanges(
        controller.document,
        serializer: serializer,
      );
      expect(ranges, isNotEmpty);

      for (final range in ranges.take(12)) {
        selectionController.setSelection(range);
        await tester.pump();
      }
      selectionController.clear();
      await tester.pump();

      final buildStopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownWidget(
              controller: controller,
              selectionController: selectionController,
            ),
          ),
        ),
      );
      await tester.pump();
      buildStopwatch.stop();

      final selectionIterations = ranges.length * 3;
      final selectionStopwatch = Stopwatch()..start();
      for (var index = 0; index < selectionIterations; index++) {
        selectionController.setSelection(ranges[index % ranges.length]);
        await tester.pump();
      }
      selectionController.clear();
      await tester.pump();
      selectionStopwatch.stop();

      final buildMicros = buildStopwatch.elapsedMicroseconds;
      final selectionMicros = selectionStopwatch.elapsedMicroseconds;
      final selectionAvgMicros = selectionIterations == 0
          ? 0.0
          : selectionMicros / selectionIterations;

      stdout.writeln('scenario: ${scenario.name}');
      stdout.writeln('sections: ${scenario.sections}');
      stdout.writeln('document blocks: ${controller.document.blocks.length}');
      stdout.writeln('selection samples: ${ranges.length}');
      stdout.writeln('initial build: ${buildStopwatch.elapsedMilliseconds} ms');
      stdout.writeln(
        'selection updates: ${selectionStopwatch.elapsedMilliseconds} ms total',
      );
      stdout.writeln(
        'selection avg: ${selectionAvgMicros.toStringAsFixed(1)} us/update',
      );
      if (buildMicros > 0) {
        stdout.writeln(
          'selection/build ratio: ${(selectionMicros / buildMicros).toStringAsFixed(2)}x',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

List<DocumentSelection> _buildSelectionRanges(
  MarkdownDocument document, {
  required MarkdownPlainTextSerializer serializer,
}) {
  final ranges = <DocumentSelection>[];
  final blockLengths = <int>[];
  for (final block in document.blocks) {
    blockLengths.add(serializer.serializeBlockText(block).length);
  }

  for (var index = 0; index < blockLengths.length; index++) {
    final length = blockLengths[index];
    if (length <= 2) {
      continue;
    }
    final startOffset = length > 24 ? 4 : 0;
    final endOffset = length > 56 ? 48 : length;
    if (endOffset > startOffset) {
      ranges.add(
        DocumentSelection(
          base: DocumentPosition(
            blockIndex: index,
            path: const PathInBlock(<int>[0]),
            textOffset: startOffset,
          ),
          extent: DocumentPosition(
            blockIndex: index,
            path: const PathInBlock(<int>[0]),
            textOffset: endOffset,
          ),
        ),
      );
    }

    if (index + 1 >= blockLengths.length) {
      continue;
    }
    final nextLength = blockLengths[index + 1];
    if (nextLength <= 2) {
      continue;
    }
    final crossStart = length > 12 ? length - 8 : 0;
    final crossEnd = nextLength > 12 ? 8 : nextLength;
    if (crossEnd <= 0) {
      continue;
    }
    ranges.add(
      DocumentSelection(
        base: DocumentPosition(
          blockIndex: index,
          path: const PathInBlock(<int>[0]),
          textOffset: crossStart,
        ),
        extent: DocumentPosition(
          blockIndex: index + 1,
          path: const PathInBlock(<int>[0]),
          textOffset: crossEnd,
        ),
      ),
    );
  }

  return ranges;
}

String _buildComplexMarkdown({required int sections}) {
  final buffer = StringBuffer('# Selection Geometry Benchmark\n');
  for (var index = 0; index < sections; index++) {
    buffer
      ..write('\n\n## Section $index')
      ..write(
        '\n\nThis paragraph mixes **bold**, _emphasis_, [links](https://example.com/$index), '
        'math like \$a_${index % 7}^2 + b_${index % 5}^2 = c^2\$, and some repeated prose to '
        'force wrapping across multiple lines in desktop-width layouts.',
      )
      ..write(
        '\n\nA follow-up paragraph adds `inline_code_$index`, ~~strikethrough~~, emoji :smile:, '
        'and enough extra words to keep selection geometry busy while dragging across rows.',
      )
      ..write(
          '\n\n> Quote line one for section $index with **highlighted** context.')
      ..write(
          '\n> Quote line two includes \$x_${index % 9}\$ and [nested links](https://quote.example/$index).')
      ..write('\n\n- Bullet one with detail for section $index')
      ..write(
          '\n- Bullet two with `token_$index` and more copy to wrap across the viewport width')
      ..write(
          '\n  - Nested child with extra words and \$y_${index % 11}\$ inline math')
      ..write('\n\nTerm $index')
      ..write(
          '\n: Definition paragraph with **rich text** and a trailing sentence for wrapping.')
      ..write('\n\n| Col A | Col B | Col C |')
      ..write('\n| --- | --- | --- |')
      ..write(
          '\n| row $index | value ${index * 3} | note with [ref](https://table.example/$index) |')
      ..write(
          '\n| row ${index + 1} | value ${index * 5} | another wrapped cell for coverage |')
      ..write('\n\n```dart')
      ..write('\nString label$index = "section_$index";')
      ..write('\nint compute$index(int input) => input * ${index + 3};')
      ..write('\n```');
  }
  return buffer.toString();
}

class _BenchmarkScenario {
  const _BenchmarkScenario({
    required this.name,
    required this.sections,
  });

  final String name;
  final int sections;
}

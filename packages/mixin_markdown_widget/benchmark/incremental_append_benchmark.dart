import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/src/parser/markdown_document_parser.dart';

void main() {
  test('incremental append benchmark', () {
    const parser = MarkdownDocumentParser();
    const scenarios = <_BenchmarkScenario>[
      _BenchmarkScenario(
        name: 'baseline',
        iterations: 400,
        initialBlockRepeats: 120,
      ),
      _BenchmarkScenario(
        name: 'large-prefix',
        iterations: 200,
        initialBlockRepeats: 600,
      ),
    ];

    stdout.writeln('mixin_markdown_widget incremental append benchmark');
    for (final scenario in scenarios) {
      final initialSource = _buildInitialMarkdown(
        repetitions: scenario.initialBlockRepeats,
      );
      final chunks = List<String>.generate(
        scenario.iterations,
        (index) =>
            '\n\n## Chunk $index\n\nParagraph ${index + 1} with **bold** and `code`.',
        growable: false,
      );

      _warmUp(parser, initialSource, chunks.take(24).toList(growable: false));

      final fullElapsed = _benchmarkFullParse(parser, initialSource, chunks);
      final incrementalElapsed =
          _benchmarkIncrementalParse(parser, initialSource, chunks);

      stdout.writeln('scenario: ${scenario.name}');
      stdout.writeln('iterations: ${scenario.iterations}');
      stdout.writeln('initial blocks: ${scenario.initialBlockRepeats}');
      stdout.writeln('full parse elapsed: ${fullElapsed.inMilliseconds} ms');
      stdout.writeln(
        'incremental parse elapsed: ${incrementalElapsed.inMilliseconds} ms',
      );
      if (incrementalElapsed.inMicroseconds > 0) {
        final speedup =
            fullElapsed.inMicroseconds / incrementalElapsed.inMicroseconds;
        stdout.writeln('speedup: ${speedup.toStringAsFixed(2)}x');
      }
    }
  });
}

void _warmUp(
  MarkdownDocumentParser parser,
  String initialSource,
  List<String> chunks,
) {
  _benchmarkFullParse(parser, initialSource, chunks);
  _benchmarkIncrementalParse(parser, initialSource, chunks);
}

Duration _benchmarkFullParse(
  MarkdownDocumentParser parser,
  String initialSource,
  List<String> chunks,
) {
  var source = initialSource;
  final stopwatch = Stopwatch()..start();
  for (final chunk in chunks) {
    source += chunk;
    parser.parse(source);
  }
  stopwatch.stop();
  return stopwatch.elapsed;
}

Duration _benchmarkIncrementalParse(
  MarkdownDocumentParser parser,
  String initialSource,
  List<String> chunks,
) {
  var document = parser.parse(initialSource);
  final stopwatch = Stopwatch()..start();
  for (final chunk in chunks) {
    document = parser.parseAppendingChunk(
      chunk,
      previousDocument: document,
    );
  }
  stopwatch.stop();
  return stopwatch.elapsed;
}

String _buildInitialMarkdown({required int repetitions}) {
  final buffer = StringBuffer('# Benchmark\n');
  for (var index = 0; index < repetitions; index++) {
    buffer
      ..write('\n\nParagraph $index with a [link](https://example.com/$index).')
      ..write('\n\n- First item\n- Second item')
      ..write('\n\n```dart\nprint($index);\n```');
  }
  return buffer.toString();
}

class _BenchmarkScenario {
  const _BenchmarkScenario({
    required this.name,
    required this.iterations,
    required this.initialBlockRepeats,
  });

  final String name;
  final int iterations;
  final int initialBlockRepeats;
}

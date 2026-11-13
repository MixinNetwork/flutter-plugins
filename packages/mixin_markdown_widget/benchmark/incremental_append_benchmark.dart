import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/src/parser/markdown_document_parser.dart';
import 'package:mixin_markdown_widget/src/widgets/markdown_controller.dart';

void main() {
  test('incremental append benchmark', () {
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
        _buildAppendChunk,
        growable: false,
      );

      _warmUp(initialSource, chunks.take(24).toList(growable: false));

      final fullResult = _benchmarkFullParse(initialSource, chunks);
      final incrementalResult = _benchmarkIncrementalParse(
        initialSource,
        chunks,
      );

      stdout.writeln('scenario: ${scenario.name}');
      stdout.writeln('iterations: ${scenario.iterations}');
      stdout.writeln('initial blocks: ${scenario.initialBlockRepeats}');
      stdout.writeln(
        'full parse elapsed: ${fullResult.elapsed.inMilliseconds} ms',
      );
      stdout.writeln('full parser timing: ${fullResult.timing.describe()}');
      stdout.writeln(
        'incremental parse elapsed: '
        '${incrementalResult.elapsed.inMilliseconds} ms',
      );
      stdout.writeln(
        'incremental parser timing: ${incrementalResult.timing.describe()}',
      );
      if (incrementalResult.elapsed.inMicroseconds > 0) {
        final speedup =
            fullResult.elapsed.inMicroseconds /
            incrementalResult.elapsed.inMicroseconds;
        stdout.writeln('speedup: ${speedup.toStringAsFixed(2)}x');
      }
    }
  });
}

void _warmUp(String initialSource, List<String> chunks) {
  _benchmarkFullParse(initialSource, chunks);
  _benchmarkIncrementalParse(initialSource, chunks);
}

_BenchmarkResult _benchmarkFullParse(
  String initialSource,
  List<String> chunks,
) {
  final timing = _TimingSummary();
  final parser = MarkdownDocumentParser(onTiming: timing.add);
  final controller = MarkdownController(data: initialSource, parser: parser);
  timing.reset();
  var source = initialSource;
  final stopwatch = Stopwatch()..start();
  for (final chunk in chunks) {
    source += chunk;
    controller.setData(source);
  }
  stopwatch.stop();
  controller.dispose();
  return _BenchmarkResult(elapsed: stopwatch.elapsed, timing: timing);
}

_BenchmarkResult _benchmarkIncrementalParse(
  String initialSource,
  List<String> chunks,
) {
  final timing = _TimingSummary();
  final parser = MarkdownDocumentParser(onTiming: timing.add);
  final controller = MarkdownController(data: initialSource, parser: parser);
  timing.reset();
  final stopwatch = Stopwatch()..start();
  for (final chunk in chunks) {
    controller.appendChunk(chunk);
  }
  stopwatch.stop();
  controller.dispose();
  return _BenchmarkResult(elapsed: stopwatch.elapsed, timing: timing);
}

String _buildInitialMarkdown({required int repetitions}) {
  final buffer = StringBuffer('# Benchmark\n');
  for (var index = 0; index < repetitions; index++) {
    buffer
      ..write('\n\n## Baseline Section $index')
      ..write(
        '\n\nParagraph $index mixes **bold**, _emphasis_, ~~strike~~, '
        '[links](https://example.com/$index), `inline_code_$index`, '
        r'\( a_i^2 + b_i^2 = c_i^2 \), and plain prose that should wrap '
        'across multiple visual lines in realistic desktop layouts.',
      )
      ..write(
        '\n\n- Hot path with `parse_$index`, `scan_$index`, '
        '`normalize_$index`, `layout_$index`, `paint_$index`, '
        '`select_$index`, `copy_$index`, and `commit_$index` all in one line',
      )
      ..write(
        '\n- [x] Completed task with [trace](https://trace.example/$index)',
      )
      ..write('\n- [ ] Pending task with nested context')
      ..write(
        '\n  1. Ordered child with `child_${index}_a` and '
        r'\( \Delta t < 16ms \)',
      )
      ..write('\n  2. Ordered child with **rich text** and more wrapping text')
      ..write(
        '\n\n> Quote $index starts with `quoted_token_$index` and a link.',
      )
      ..write(
        '\n> > Nested quote keeps **strong text**, _emphasis_, and '
        r'\( q_{n+1}=q_n+r \).',
      )
      ..write('\n\nTerm $index')
      ..write(
        '\n: Definition includes ==mark==, H~2~O, 2^10^, '
        '<kbd>Cmd</kbd>+<kbd>K</kbd>, and https://example.com/plain/$index.',
      )
      ..write('\n\n| Metric | Value | Notes |')
      ..write('\n| :--- | ---: | :--- |')
      ..write(
        '\n| parse | ${index * 3 + 7} | `MarkdownDocumentParser` '
        'with [range](https://range.example/$index) |',
      )
      ..write(
        '\n| render | ${index * 5 + 11} | wraps `inline` code and '
        r'\( \sqrt{x^2+y^2} \) math |',
      )
      ..write('\n\n```dart')
      ..write('\nfinal tokens$index = <String>[')
      ..write('\n  for (var i = 0; i < 8; i++) "token_\$i",')
      ..write('\n];')
      ..write('\nint compute$index(int input) => input * ${index + 3};')
      ..write('\n```')
      ..write(
        '\n\n![Benchmark image $index](missing-image-$index.png?w=640&h=240)',
      )
      ..write(
        '\n\n[^baseline-$index]: Footnote with `footnote_$index`, '
        '[reference](https://footnote.example/$index), and extra detail.',
      );
  }
  return buffer.toString();
}

String _buildAppendChunk(int index) {
  switch (index % 6) {
    case 0:
      return '\n\n## Chunk $index: dense inline content\n\n'
          'A streaming paragraph contains **bold_$index**, _emphasis_$index, '
          '~~strike_$index~~, [link](https://stream.example/$index), '
          '`code_a_$index`, `code_b_$index`, `code_c_$index`, '
          r'\( \alpha_i + \beta_i = \gamma_i \), '
          'plain URL https://plain.example/$index, and enough natural text to '
          'force multiple wrapping decisions while the unstable tail grows.';
    case 1:
      return '\n\n## Chunk $index: list pressure\n\n'
          '- One list row with `a_$index`, `b_$index`, `c_$index`, '
          '`d_$index`, `e_$index`, `f_$index`, `g_$index`, `h_$index`, '
          '`i_$index`, `j_$index`, `k_$index`, and `l_$index` inline code spans\n'
          '- [x] Task item with **strong** content and [audit](https://audit.example/$index)\n'
          '- [ ] Task item with nested ordered children\n'
          '  1. Child `child_${index}_one` with wrapped prose and '
          r'\( latency < 50ms \)'
          '\n'
          '  2. Child `child_${index}_two` with more detail';
    case 2:
      return '\n\n## Chunk $index: blockquote stack\n\n'
          '> Parent quote carries `quote_$index` and [link](https://quote.example/$index).\n'
          '> > Nested quote has **bold**, _emphasis_, and '
          r'\( \sum_{i=0}^{n} i = n(n+1)/2 \).'
          '\n'
          '> > > Deep quote ends with `deep_token_$index` and trailing prose.';
    case 3:
      return '\n\n## Chunk $index: table matrix\n\n'
          '| Field | Parser State | Render State | Notes |\n'
          '| :--- | :---: | :---: | :--- |\n'
          '| header | `scan_$index` | `layout_$index` | [docs](https://docs.example/$index) |\n'
          '| body | `normalize_$index` | `paint_$index` | '
          r'\( x_{i+1}=x_i+\Delta \)'
          ' plus wrapped text |\n'
          '| tail | `reuse_$index` | `select_$index` | many inline spans in a cell |';
    case 4:
      return '\n\n## Chunk $index: definitions and footnotes\n\n'
          'Term $index\n'
          ': Definition uses ==highlight==, H~2~O, 2^10^, <kbd>Esc</kbd>, '
          '`definition_$index`, and a footnote reference.[^chunk-$index]\n\n'
          '[^chunk-$index]: Footnote body with [link](https://note.example/$index), '
          '`note_code_$index`, and a second sentence to keep it non-trivial.';
    default:
      return '\n\n## Chunk $index: media and code\n\n'
          '[![Linked image $index](missing-linked-$index.png?w=800&h=320)]'
          '(https://image.example/$index)\n\n'
          '```dart\n'
          'final frame$index = <String, Object?>{\n'
          '  "index": $index,\n'
          '  "tokens": ["alpha", "beta", "gamma", "delta"],\n'
          '};\n'
          'String render$index() => frame$index.entries.join(",");\n'
          '```';
  }
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

class _BenchmarkResult {
  const _BenchmarkResult({required this.elapsed, required this.timing});

  final Duration elapsed;
  final _TimingSummary timing;
}

class _TimingSummary {
  int count = 0;
  int totalMicros = 0;
  int markdownParseLinesMicros = 0;
  int buildBlocksMicros = 0;
  int scanRangesMicros = 0;
  int applyRangesMicros = 0;
  int normalizeInlineMicros = 0;
  int nextIdMicros = 0;
  int totalParseLineCount = 0;
  int maxParseLineCount = 0;

  void reset() {
    count = 0;
    totalMicros = 0;
    markdownParseLinesMicros = 0;
    buildBlocksMicros = 0;
    scanRangesMicros = 0;
    applyRangesMicros = 0;
    normalizeInlineMicros = 0;
    nextIdMicros = 0;
    totalParseLineCount = 0;
    maxParseLineCount = 0;
  }

  void add(MarkdownParserTiming timing) {
    count += 1;
    totalMicros += timing.totalMicros;
    markdownParseLinesMicros += timing.markdownParseLinesMicros;
    buildBlocksMicros += timing.buildBlocksMicros;
    scanRangesMicros += timing.scanRangesMicros;
    applyRangesMicros += timing.applyRangesMicros;
    normalizeInlineMicros += timing.normalizeInlineMicros;
    nextIdMicros += timing.nextIdMicros;
    totalParseLineCount += timing.parseLineCount;
    if (timing.parseLineCount > maxParseLineCount) {
      maxParseLineCount = timing.parseLineCount;
    }
  }

  String describe() {
    if (totalMicros == 0) {
      return 'no parser samples';
    }
    String part(String name, int micros) {
      final percent = micros * 100 / totalMicros;
      final millis = micros / 1000;
      return '$name=${millis.toStringAsFixed(1)}ms '
          '(${percent.toStringAsFixed(1)}%)';
    }

    return [
      'samples=$count',
      'avgLines=${(totalParseLineCount / count).toStringAsFixed(1)}',
      'maxLines=$maxParseLineCount',
      part('markdown', markdownParseLinesMicros),
      part('build', buildBlocksMicros),
      part('scanRanges', scanRangesMicros),
      part('applyRanges', applyRangesMicros),
      part('normalizeInline', normalizeInlineMicros),
      part('nextId', nextIdMicros),
      'parserTotal=${(totalMicros / 1000).toStringAsFixed(1)}ms',
    ].join(', ');
  }
}

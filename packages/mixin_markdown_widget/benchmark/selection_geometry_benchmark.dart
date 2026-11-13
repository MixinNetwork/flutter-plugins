import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
        '\n\nSingle-line code pressure: `alpha_$index` `beta_$index` `gamma_$index` '
        '`delta_$index` `epsilon_$index` `zeta_$index` `eta_$index` '
        '`theta_$index` `iota_$index` `kappa_$index` `lambda_$index` '
        '`mu_$index` `nu_$index` `xi_$index` `omicron_$index` `pi_$index`.',
      )
      ..write(
        '\n\n> Quote line one for section $index with **highlighted** context.',
      )
      ..write(
        '\n> Quote line two includes \$x_${index % 9}\$ and [nested links](https://quote.example/$index).',
      )
      ..write(
        '\n> > Nested quote line keeps `nested_quote_$index`, '
        '**bold**, _emphasis_, and more text for geometry traversal.',
      )
      ..write(
        '\n> > > Deep quote line with '
        r'\( \sum_{i=0}^{n} i = n(n+1)/2 \)'
        ' and `deep_$index`.',
      )
      ..write('\n\n- Bullet one with detail for section $index')
      ..write(
        '\n- Bullet two with `token_$index` and more copy to wrap across the viewport width',
      )
      ..write(
        '\n- Bullet three contains many inline code spans: '
        '`a_$index`, `b_$index`, `c_$index`, `d_$index`, `e_$index`, '
        '`f_$index`, `g_$index`, `h_$index`, `i_$index`, `j_$index`, '
        '`k_$index`, and `l_$index` in one visual row candidate',
      )
      ..write('\n- [x] Checked task with [audit](https://tasks.example/$index)')
      ..write('\n- [ ] Pending task with **rich** text and `pending_$index`')
      ..write(
        '\n  - Nested child with extra words and \$y_${index % 11}\$ inline math',
      )
      ..write('\n  1. Ordered nested child with `ordered_${index}_a`')
      ..write(
        '\n  2. Ordered nested child with `ordered_${index}_b` '
        'and enough text to wrap onto another line',
      )
      ..write('\n\nTerm $index')
      ..write(
        '\n: Definition paragraph with **rich text**, ==mark==, H~2~O, '
        '2^10^, <kbd>Cmd</kbd>+<kbd>K</kbd>, and a trailing sentence for wrapping.',
      )
      ..write(
        '\n\n![Selection image $index](missing-selection-$index.png?w=640&h=260)',
      )
      ..write('\n\n| Col A | Col B | Col C |')
      ..write('\n| --- | --- | --- |')
      ..write(
        '\n| row $index | value ${index * 3} | note with [ref](https://table.example/$index) |',
      )
      ..write(
        '\n| row ${index + 1} | value ${index * 5} | another wrapped cell for coverage |',
      )
      ..write(
        '\n| row ${index + 2} | `cell_${index}_a` `cell_${index}_b` `cell_${index}_c` | '
        r'\( \sqrt{x^2+y^2} \)'
        ' mixed with **bold** and _emphasis_ |',
      )
      ..write('\n\n| Wide A | Wide B | Wide C | Wide D | Wide E |')
      ..write('\n| :--- | ---: | :---: | :--- | :--- |')
      ..write(
        '\n| `parse_$index` | ${index * 7} | ✅ | '
        '[trace](https://wide.example/$index) | long text that should push horizontal table logic |',
      )
      ..write(
        '\n| `layout_$index` | ${index * 11} | ⚠️ | '
        r'\( x_{i+1}=x_i+\Delta \)'
        ' | `a` `b` `c` `d` `e` in cell |',
      )
      ..write('\n\n```dart')
      ..write('\nString label$index = "section_$index";')
      ..write('\nint compute$index(int input) => input * ${index + 3};')
      ..write('\n```')
      ..write(
        '\n\n[^selection-$index]: Footnote body with `note_$index`, '
        '[source](https://footnote.example/$index), and text that selection can traverse.',
      );
  }
  return buffer.toString();
}

class _BenchmarkScenario {
  const _BenchmarkScenario({required this.name, required this.sections});

  final String name;
  final int sections;
}

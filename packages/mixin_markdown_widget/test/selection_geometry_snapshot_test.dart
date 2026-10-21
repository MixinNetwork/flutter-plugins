// Rect snapshots of the selection highlight that each block paints.
//
// The values are literal block-local rects recorded from the renderer and
// compared within [_tolerance]. They pin the painted geometry so that the
// selection layout can be restructured without visual drift. To re-record
// after an intentional geometry change, run:
//
//   flutter test test/selection_geometry_snapshot_test.dart \
//     --dart-define=RECORD_SELECTION_SNAPSHOTS=true
//
// and paste the printed literals back into [_cases].

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/selectable_block.dart';

const bool _record = bool.fromEnvironment('RECORD_SELECTION_SNAPSHOTS');
const double _tolerance = 0.5;

const SelectableBlockSelectionPaintOrder _behind =
    SelectableBlockSelectionPaintOrder.behindChild;
const SelectableBlockSelectionPaintOrder _above =
    SelectableBlockSelectionPaintOrder.aboveChild;

class _BlockPaint {
  const _BlockPaint({
    required this.order,
    required this.rects,
    this.clip,
  });

  final SelectableBlockSelectionPaintOrder order;
  final Rect? clip;
  final List<Rect> rects;
}

class _Case {
  const _Case(
    this.name,
    this.data, {
    required this.startBlock,
    required this.startOffset,
    required this.endBlock,
    required this.endOffset,
    required this.expected,
    this.horizontalScroll,
  });

  final String name;
  final String data;
  final int startBlock;
  final int startOffset;
  final int endBlock;
  final int endOffset;

  /// Scrolls the first horizontal scrollable inside block 0 before selecting.
  final double? horizontalScroll;
  final Map<int, _BlockPaint> expected;
}

const List<_Case> _cases = <_Case>[
  _Case(
    'multi-line paragraph',
    'The quick brown fox jumps over the lazy dog while the selection '
        'geometry spans several wrapped lines of plain paragraph text.',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 123,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _behind,
        rects: <Rect>[
          Rect.fromLTRB(29.13, -0.45, 306.63, 20.55),
          Rect.fromLTRB(-1.38, 20.55, 306.63, 41.55),
          Rect.fromLTRB(-1.38, 41.55, 215.13, 62.55),
          Rect.fromLTRB(-1.38, 62.55, 291.38, 83.55),
          Rect.fromLTRB(-1.38, 83.55, 337.13, 104.55),
          Rect.fromLTRB(-1.38, 104.55, 230.38, 125.55),
          Rect.fromLTRB(-1.38, 125.55, 199.88, 146.55),
        ],
      ),
    },
  ),
  _Case(
    'selection across list items with marker prefix rects',
    '1. First item text\n'
        '2. Second item with more words to wrap around the line\n'
        '3. Third',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 80,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(0.00, -0.45, 254.38, 20.55),
          Rect.fromLTRB(0.00, 46.55, 284.88, 67.55),
          Rect.fromLTRB(22.63, 67.55, 315.38, 88.55),
          Rect.fromLTRB(22.63, 88.55, 254.38, 109.55),
          Rect.fromLTRB(0.00, 112.55, 71.38, 133.55),
        ],
      ),
    },
  ),
  _Case(
    'nested list',
    '- Fruit\n  - Apple\n    - Green\n  - Banana\n- Veg',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 54,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(18.63, -0.45, 97.88, 20.55),
          Rect.fromLTRB(20.00, 23.55, 117.88, 44.55),
          Rect.fromLTRB(40.00, 47.55, 137.88, 68.55),
          Rect.fromLTRB(20.00, 72.55, 133.13, 93.55),
          Rect.fromLTRB(0.00, 97.55, 36.88, 118.55),
        ],
      ),
    },
  ),
  _Case(
    'nested quote with heading',
    '> # Quoted Title\n>\n'
        '> > Nested quote paragraph with enough text to wrap around.\n>\n'
        '> Tail para',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 78,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(86.50, 6.08, 269.50, 50.08),
          Rect.fromLTRB(14.50, 50.08, 197.50, 94.08),
          Rect.fromLTRB(30.63, 121.12, 231.88, 142.12),
          Rect.fromLTRB(30.63, 142.12, 262.38, 163.12),
          Rect.fromLTRB(30.63, 163.12, 262.38, 184.12),
          Rect.fromLTRB(30.63, 184.12, 216.63, 205.12),
          Rect.fromLTRB(14.63, 219.69, 124.38, 240.69),
        ],
      ),
    },
  ),
  _Case(
    'details',
    '<details open>\n<summary>Summary line</summary>\n\n'
        'Body paragraph\n\n- item one\n- item two\n\n</details>',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 49,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(53.13, 1.55, 208.63, 22.55),
          Rect.fromLTRB(-1.38, 34.63, 215.13, 55.63),
          Rect.fromLTRB(0.00, 58.63, 143.63, 79.63),
          Rect.fromLTRB(0.00, 83.63, 113.13, 104.63),
        ],
      ),
    },
  ),
  _Case(
    'definition list',
    'Term\n: Definition text that wraps around the available width',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 58,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _behind,
        rects: <Rect>[
          Rect.fromLTRB(29.13, -0.45, 62.63, 20.55),
          Rect.fromLTRB(-1.38, 20.55, 276.13, 41.55),
          Rect.fromLTRB(-1.38, 41.55, 337.13, 62.55),
          Rect.fromLTRB(-1.38, 62.55, 199.88, 83.55),
        ],
      ),
    },
  ),
  _Case(
    'footnotes',
    'See[^1] and[^2].\n\n[^1]: First note.\n[^2]: Second note text.',
    startBlock: 0,
    startOffset: 2,
    endBlock: 1,
    endOffset: 35,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _behind,
        rects: <Rect>[
          Rect.fromLTRB(29.13, -0.45, 148.73, 20.55),
        ],
      ),
      1: _BlockPaint(
        order: _behind,
        rects: <Rect>[
          Rect.fromLTRB(0.00, 11.55, 208.63, 32.55),
          Rect.fromLTRB(0.00, 58.55, 269.63, 79.55),
        ],
      ),
    },
  ),
  _Case(
    'table cells across rows',
    '| Name | Value |\n| --- | --- |\n| row | 42 |\n| next | 7 |',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 22,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(41.13, 9.55, 74.63, 30.55),
          Rect.fromLTRB(173.63, 9.55, 252.88, 30.55),
          Rect.fromLTRB(10.63, 50.55, 59.38, 71.55),
          Rect.fromLTRB(173.63, 50.55, 207.13, 71.55),
          Rect.fromLTRB(10.63, 91.55, 74.63, 112.55),
        ],
      ),
    },
  ),
  _Case(
    'quote with a horizontally scrolled table',
    '> | Alpha column | Beta column | Gamma column | Delta column | '
        'Epsilon column |\n'
        '> | --- | --- | --- | --- | --- |\n'
        '> | a1 value | b1 value | c1 value | d1 value | e1 value |\n'
        '> | a2 value | b2 value | c2 value | d2 value | e2 value |',
    startBlock: 0,
    startOffset: 10,
    endBlock: 0,
    endOffset: 143,
    horizontalScroll: 80,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(16.00, 36.55, 41.13, 57.55),
          Rect.fromLTRB(90.63, 15.55, 169.88, 36.55),
          Rect.fromLTRB(90.63, 36.55, 185.13, 57.55),
          Rect.fromLTRB(224.63, 15.55, 312.00, 36.55),
          Rect.fromLTRB(224.63, 36.55, 312.00, 57.55),
          Rect.fromLTRB(16.00, 98.55, 25.88, 119.55),
          Rect.fromLTRB(90.63, 77.55, 139.38, 98.55),
          Rect.fromLTRB(90.63, 98.55, 169.88, 119.55),
          Rect.fromLTRB(224.63, 77.55, 273.38, 98.55),
          Rect.fromLTRB(224.63, 98.55, 303.88, 119.55),
          Rect.fromLTRB(16.00, 160.55, 25.88, 181.55),
          Rect.fromLTRB(90.63, 139.55, 139.38, 160.55),
          Rect.fromLTRB(90.63, 160.55, 169.88, 181.55),
          Rect.fromLTRB(224.63, 139.55, 273.38, 160.55),
          Rect.fromLTRB(224.63, 160.55, 303.88, 181.55),
        ],
      ),
    },
  ),
  _Case(
    'horizontally scrolled code block',
    '```dart\n'
        'final veryLongIdentifierName = '
        'computeSomethingLong(alpha, beta, gamma, delta);\n'
        'short();\n'
        'anotherVeryLongLine = makeTheLineScrollHorizontallyPastTheViewport();\n'
        '```',
    startBlock: 0,
    startOffset: 10,
    endBlock: 0,
    endOffset: 146,
    horizontalScroll: 80,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        clip: Rect.fromLTRB(16.00, 16.00, 268.00, 79.00),
        rects: <Rect>[
          Rect.fromLTRB(87.13, 15.55, 1142.38, 36.55),
          Rect.fromLTRB(-65.38, 36.55, 59.63, 57.55),
          Rect.fromLTRB(-65.38, 57.55, 806.88, 78.55),
        ],
      ),
    },
  ),
  _Case(
    'inline code and math inside a paragraph',
    r'Alpha `code span` beta $x^2$ gamma',
    startBlock: 0,
    startOffset: 2,
    endBlock: 0,
    endOffset: 28,
    expected: <int, _BlockPaint>{
      0: _BlockPaint(
        order: _above,
        rects: <Rect>[
          Rect.fromLTRB(29.13, 1.03, 331.88, 20.78),
          Rect.fromLTRB(-1.38, 20.78, 92.88, 38.78),
        ],
      ),
    },
  ),
];

Future<MarkdownSelectionController> _pump(
  WidgetTester tester,
  String data,
) async {
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
            height: 600,
            child: MarkdownWidget(
              data: data,
              selectionController: controller,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

SelectableMarkdownBlockState _blockState(WidgetTester tester, int index) {
  return tester
      .stateList<SelectableMarkdownBlockState>(
        find.byType(SelectableMarkdownBlock),
      )
      .firstWhere((state) => state.widget.blockIndex == index);
}

DocumentPosition _position(
  WidgetTester tester,
  int blockIndex,
  int displayedOffset,
) {
  final structure =
      _blockState(tester, blockIndex).widget.spec.selectionStructure;
  return structure?.positionForDisplayedOffset(
        blockIndex: blockIndex,
        displayedOffset: displayedOffset,
      ) ??
      DocumentPosition(
        blockIndex: blockIndex,
        path: const PathInBlock(<int>[0]),
        textOffset: displayedOffset,
      );
}

/// Mirrors what the block's selection painter receives: the block-clamped
/// range, the resolved rects, and the clip rect.
_BlockPaint? _paintedSelection(
  WidgetTester tester,
  SelectableMarkdownBlockState state,
) {
  final widget = state.widget;
  final range = widget.selectionRange;
  if (range == null) {
    return null;
  }
  final index = widget.blockIndex;
  if (index < range.start.blockIndex || index > range.end.blockIndex) {
    return null;
  }
  final start = index == range.start.blockIndex ? range.start.textOffset : 0;
  final end = index == range.end.blockIndex
      ? range.end.textOffset
      : widget.spec.plainText.length;
  if (start >= end) {
    return null;
  }
  final size = (state.context.findRenderObject()! as RenderBox).size;
  final rects = widget.spec.selectionRectResolver?.call(
    state.context,
    size,
    DocumentRange(
      start: DocumentPosition(
        blockIndex: index,
        path: const PathInBlock(<int>[0]),
        textOffset: start,
      ),
      end: DocumentPosition(
        blockIndex: index,
        path: const PathInBlock(<int>[0]),
        textOffset: end,
      ),
    ),
  );
  return _BlockPaint(
    order: widget.spec.selectionPaintOrder,
    clip: widget.spec.selectionClipRectResolver?.call(state.context, size),
    rects: rects ?? const <Rect>[],
  );
}

String _rectLiteral(Rect rect) {
  String f(double value) => value.toStringAsFixed(2);
  return 'Rect.fromLTRB(${f(rect.left)}, ${f(rect.top)}, '
      '${f(rect.right)}, ${f(rect.bottom)})';
}

void _expectRect(Rect actual, Rect expected, String reason) {
  final matches = (actual.left - expected.left).abs() <= _tolerance &&
      (actual.top - expected.top).abs() <= _tolerance &&
      (actual.right - expected.right).abs() <= _tolerance &&
      (actual.bottom - expected.bottom).abs() <= _tolerance;
  expect(
    matches,
    isTrue,
    reason: '$reason: expected ${_rectLiteral(expected)}, '
        'got ${_rectLiteral(actual)}',
  );
}

void main() {
  for (final testCase in _cases) {
    testWidgets('selection geometry snapshot: ${testCase.name}', (
      tester,
    ) async {
      final controller = await _pump(tester, testCase.data);

      final scroll = testCase.horizontalScroll;
      if (scroll != null) {
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SelectableMarkdownBlock).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(scrollable.position.axis, Axis.horizontal);
        scrollable.position.jumpTo(scroll);
        await tester.pump();
      }

      controller.setSelection(
        DocumentSelection(
          base: _position(tester, testCase.startBlock, testCase.startOffset),
          extent: _position(tester, testCase.endBlock, testCase.endOffset),
        ),
      );
      await tester.pump();

      final actual = <int, _BlockPaint>{};
      for (final state in tester.stateList<SelectableMarkdownBlockState>(
        find.byType(SelectableMarkdownBlock),
      )) {
        final paint = _paintedSelection(tester, state);
        if (paint != null) {
          actual[state.widget.blockIndex] = paint;
        }
      }

      if (_record) {
        final buffer = StringBuffer('// ${testCase.name}\n')
          ..writeln('expected: <int, _BlockPaint>{');
        for (final entry in actual.entries) {
          final paint = entry.value;
          buffer
            ..writeln('  ${entry.key}: _BlockPaint(')
            ..writeln(
              '    order: ${paint.order == _above ? '_above' : '_behind'},',
            );
          if (paint.clip != null) {
            buffer.writeln('    clip: ${_rectLiteral(paint.clip!)},');
          }
          buffer.writeln('    rects: <Rect>[');
          for (final rect in paint.rects) {
            buffer.writeln('      ${_rectLiteral(rect)},');
          }
          buffer
            ..writeln('    ],')
            ..writeln('  ),');
        }
        buffer.writeln('},');
        // ignore: avoid_print
        print(buffer);
        return;
      }

      expect(actual.keys, testCase.expected.keys);
      for (final entry in testCase.expected.entries) {
        final expected = entry.value;
        final paint = actual[entry.key]!;
        final reason = '${testCase.name} block ${entry.key}';
        expect(paint.order, expected.order, reason: '$reason paint order');
        if (expected.clip == null) {
          expect(paint.clip, isNull, reason: '$reason clip');
        } else {
          expect(paint.clip, isNotNull, reason: '$reason clip');
          _expectRect(paint.clip!, expected.clip!, '$reason clip');
        }
        expect(
          paint.rects.length,
          expected.rects.length,
          reason: '$reason rect count: '
              '${paint.rects.map(_rectLiteral).join(', ')}',
        );
        for (var i = 0; i < expected.rects.length; i++) {
          _expectRect(paint.rects[i], expected.rects[i], '$reason rect $i');
        }
      }
    });
  }

  testWidgets(
      'horizontally scrolled code block paints selection in the foreground',
      (tester) async {
    final controller = await _pump(
      tester,
      '```dart\nfinal value = computeSomethingLongEnoughToScroll(alpha);\n```',
    );
    controller.setSelection(
      DocumentSelection(
        base: _position(tester, 0, 0),
        extent: _position(tester, 0, 10),
      ),
    );
    await tester.pump();

    final paint = find.descendant(
      of: find.byType(SelectableMarkdownBlock),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.foregroundPainter != null,
      ),
    );
    expect(paint, findsOneWidget);
    expect(tester.widget<CustomPaint>(paint).painter, isNull);
  });
}

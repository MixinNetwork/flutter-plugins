import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/code_syntax_highlighter.dart';
import 'package:mixin_markdown_widget/src/render/pretext_text_block.dart';

const _keywordColor = Color(0xFFFF0000);

class _FakeHighlighter extends MarkdownCodeSyntaxHighlighter {
  final List<String> requests = <String>[];
  final List<Completer<MarkdownCodeHighlightPresentation>> _pending =
      <Completer<MarkdownCodeHighlightPresentation>>[];

  @override
  MarkdownCodeHighlightPresentation? cachedPresentation({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) =>
      null;

  @override
  Future<MarkdownCodeHighlightPresentation> buildPresentationAsync({
    required String source,
    required TextStyle baseStyle,
    required MarkdownThemeData theme,
    String? language,
  }) {
    requests.add(source);
    final completer = Completer<MarkdownCodeHighlightPresentation>();
    _pending.add(completer);
    return completer.future;
  }

  /// Finishes the oldest running highlight with every character colored.
  void finishNext(TextStyle baseStyle) {
    final source = requests[requests.length - _pending.length];
    final style = baseStyle.copyWith(color: _keywordColor);
    _pending.removeAt(0).complete(
          MarkdownCodeHighlightPresentation(
            span: TextSpan(
              style: baseStyle,
              children: <InlineSpan>[TextSpan(text: source, style: style)],
            ),
            runs: <MarkdownPretextInlineRun>[
              MarkdownPretextInlineRun(text: source, style: style),
            ],
            isHighlighted: true,
          ),
        );
  }
}

void main() {
  late MarkdownThemeData theme;

  Future<void> pumpTheme(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            theme = MarkdownThemeData.fallback(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  testWidgets(
      'a growing code block keeps its highlighted prefix as the placeholder',
      (tester) async {
    await pumpTheme(tester);
    final highlighter = _FakeHighlighter();
    final cache = MarkdownCodeHighlightCache(highlighter: highlighter);
    addTearDown(cache.dispose);
    final baseStyle = theme.codeBlockStyle;

    MarkdownCodeHighlightPresentation resolve(String source) => cache.resolve(
          blockId: 'code',
          source: source,
          baseStyle: baseStyle,
          theme: theme,
          language: 'dart',
        );

    expect(resolve('a = 1;').isHighlighted, isFalse);
    highlighter.finishNext(baseStyle);
    await tester.pump();
    expect(resolve('a = 1;').isHighlighted, isTrue);

    final placeholder = resolve('a = 1;\nb = 2;');
    expect(placeholder.isHighlighted, isFalse);
    expect(placeholder.span.toPlainText(), 'a = 1;\nb = 2;');
    expect(
      placeholder.runs.map((run) => (run.text, run.style.color)).toList(),
      <(String, Color?)>[
        ('a = 1;', _keywordColor),
        ('\nb = 2;', baseStyle.color),
      ],
    );
  });

  testWidgets('a growing code block runs one highlight at a time',
      (tester) async {
    await pumpTheme(tester);
    final highlighter = _FakeHighlighter();
    final cache = MarkdownCodeHighlightCache(highlighter: highlighter);
    addTearDown(cache.dispose);
    final baseStyle = theme.codeBlockStyle;
    var notifications = 0;
    cache.addListener(() => notifications += 1);

    MarkdownCodeHighlightPresentation resolve(String source) => cache.resolve(
          blockId: 'code',
          source: source,
          baseStyle: baseStyle,
          theme: theme,
          language: 'dart',
        );

    resolve('a');
    resolve('a = 1;');
    resolve('a = 1;\nb');
    resolve('a = 1;\nb = 2;');
    expect(highlighter.requests, <String>['a']);

    // The first run ends: the latest source runs next, not every chunk.
    highlighter.finishNext(baseStyle);
    await tester.pump();
    expect(highlighter.requests, <String>['a', 'a = 1;\nb = 2;']);
    expect(notifications, 1);
    final partial = resolve('a = 1;\nb = 2;');
    expect(partial.isHighlighted, isFalse);
    expect(partial.runs.first.text, 'a');
    expect(partial.runs.first.style.color, _keywordColor);
    expect(partial.span.toPlainText(), 'a = 1;\nb = 2;');

    highlighter.finishNext(baseStyle);
    await tester.pump();
    expect(highlighter.requests, hasLength(2));
    expect(notifications, 2);
    final done = resolve('a = 1;\nb = 2;');
    expect(done.isHighlighted, isTrue);
    expect(done.runs.single.text, 'a = 1;\nb = 2;');
  });

  testWidgets('a code block that is not extended falls back to plain text',
      (tester) async {
    await pumpTheme(tester);
    final highlighter = _FakeHighlighter();
    final cache = MarkdownCodeHighlightCache(highlighter: highlighter);
    addTearDown(cache.dispose);
    final baseStyle = theme.codeBlockStyle;

    cache.resolve(
      blockId: 'code',
      source: 'a = 1;',
      baseStyle: baseStyle,
      theme: theme,
      language: 'dart',
    );
    highlighter.finishNext(baseStyle);
    await tester.pump();

    final edited = cache.resolve(
      blockId: 'code',
      source: 'b = 1;',
      baseStyle: baseStyle,
      theme: theme,
      language: 'dart',
    );
    expect(edited.isHighlighted, isFalse);
    expect(edited.runs.single.text, 'b = 1;');
    expect(edited.runs.single.style.color, baseStyle.color);
  });
}

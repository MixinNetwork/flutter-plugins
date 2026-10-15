import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:mixin_markdown_widget/src/render/code_syntax_highlighter.dart';

void main() {
  testWidgets('prepared highlights show in the first frame of a code block',
      (tester) async {
    late MarkdownThemeData theme;
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

    // Sources unique to this test: the segment cache is shared.
    const top = 'final preparedTop = 1;';
    const nested = 'final preparedNested = 2;';
    const long = 'final preparedLong = 3;\nfinal second = 4;';
    final document = MarkdownController.parseDocument('''
```dart
$top
```

> - item
>
>   ```dart
>   $nested
>   ```

```dart
$long
```
''');

    final highlights =
        MarkdownController.highlightCodeBlocks(document, maxLines: 1);
    expect(highlights.map((highlight) => highlight['source']), [top, nested]);

    MarkdownController.cacheCodeHighlights(highlights);
    final cache = MarkdownCodeHighlightCache(
      highlighter: const MarkdownCodeSyntaxHighlighter(),
    );
    addTearDown(cache.dispose);
    for (final source in [top, nested]) {
      final presentation = cache.resolve(
        blockId: source,
        source: source,
        baseStyle: theme.codeBlockStyle,
        theme: theme,
        language: 'dart',
      );
      expect(presentation.isHighlighted, isTrue, reason: source);
    }
    // Over the line limit: not prepared, so it starts plain.
    expect(
      cache
          .resolve(
            blockId: long,
            source: long,
            baseStyle: theme.codeBlockStyle,
            theme: theme,
            language: 'dart',
          )
          .isHighlighted,
      isFalse,
    );
    await tester.pumpAndSettle();
  });
}

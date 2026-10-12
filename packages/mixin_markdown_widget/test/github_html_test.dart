import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/src/render/markdown_block_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

const reviewFixture = '''
[**#42 Update sample feature**](https://example.com/sample/project/pull/42)

> [**comment**](https://example.com/sample/project/pull/42#issuecomment-100)
> <!-- review-summary -->
> <!-- review-state {"headSha":"0123456789abcdef","repository":"sample/project"} -->
> ## Review Summary
>
> | Review | Status | Commit |
> | --- | --- | --- |
> | **Code Review** | Running since <relative-time datetime="2030-01-02T03:04:05Z">2030-01-02T03:04:05Z</relative-time> | `0123456` |
> | **Security Review** | Completed <relative-time datetime="2030-01-02T03:05:06Z">2030-01-02T03:05:06Z</relative-time> | `0123456` |
>
> <details> <summary>About reviews</summary>
> <br/>
>
> [Review settings](https://example.com/settings/reviews). Reviews run when you
> - Open a pull request
> - Comment "@review-bot review".
>
> </details>
''';

String plainText(String source) {
  final controller = MarkdownController(data: source);
  addTearDown(controller.dispose);
  return controller.plainText;
}

void main() {
  test('GitHub review fixture hides metadata and preserves rich blocks', () {
    final text = plainText(reviewFixture);
    expect(text, isNot(contains('<!--')));
    expect(text, isNot(contains('headSha')));
    expect(text, isNot(contains('relative-time')));
    expect(text, contains('Running since 2030-01-02T03:04:05Z'));
    expect(text, contains('Completed 2030-01-02T03:05:06Z'));
    expect(text, isNot(contains('<br')));
    final document = const MarkdownDocumentParser().parse(reviewFixture);
    final quote = document.blocks.last as QuoteBlock;
    expect(quote.children.whereType<TableBlock>(), hasLength(1));
    final details = quote.children.whereType<DetailsBlock>().single;
    expect(details.initiallyExpanded, isFalse);
    expect((details.children.first as ParagraphBlock).inlines.single,
        isA<HardBreakInline>());
    expect(details.children.whereType<ListBlock>().single.items, hasLength(2));
  });

  test('GitHub comments preserve source ranges and append semantics', () {
    const source = '<!-- hidden -->\n\n# One\n\nTwo';
    final controller = MarkdownController(data: source);
    addTearDown(controller.dispose);
    final two = controller.document.blocks.last;
    expect(two.sourceRange, isNotNull);
    expect(
        source.substring(two.sourceRange!.start, two.sourceRange!.end), 'Two');
    controller.appendChunk(' more');
    expect(controller.plainText, 'One\n\nTwo more');

    controller.setData('# One\n\n<!-- hidden\n\n');
    controller.appendChunk('still hidden\n-->\n\nVisible');
    expect(controller.plainText, 'One\n\nVisible');

    controller.setData('# One\n\nTwo\n\n<!-- hidden -->');
    controller.appendChunk('\n\nThree');
    expect(controller.plainText, 'One\n\nTwo\n\nThree');
  });

  test('GitHub review streaming matches full parsing at every chunk', () {
    final controller = MarkdownController();
    addTearDown(controller.dispose);
    for (var end = 1; end <= reviewFixture.length; end += 1) {
      controller.appendChunk(reviewFixture.substring(end - 1, end));
      final reference =
          MarkdownController(data: reviewFixture.substring(0, end));
      expect(controller.plainText, reference.plainText, reason: 'offset $end');
      reference.dispose();
    }
  });

  testWidgets('GitHub review table and details render without HTML source',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MarkdownWidget(data: reviewFixture)),
    ));
    expect(find.textContaining('<!--'), findsNothing);
    expect(find.textContaining('<relative-time'), findsNothing);
    expect(find.textContaining('<br'), findsNothing);
    expect(find.byType(MarkdownTableBlockView), findsOneWidget);
    expect(find.byType(MarkdownListBlockView), findsNothing);
    await tester.ensureVisible(find.byIcon(Icons.chevron_right_rounded));
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownListBlockView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('GitHub time elements preserve fallback content in inline contexts', () {
    for (final tag in ['relative-time', 'local-time', 'time']) {
      expect(plainText('Updated <$tag datetime="2030-01-02">**Jan 2**</$tag>.'),
          'Updated Jan 2.');
    }
  });

  test('GitHub HTML comments are hidden in blocks and inline content', () {
    expect(plainText('Before<!-- hidden -->after'), 'Beforeafter');
    expect(plainText('<!-- hidden\n\n# secret\n-->\n\nVisible'), 'Visible');
    expect(plainText('<!-- first -->\n<!-- second -->\n# Visible'), 'Visible');
    expect(plainText('- Before<!-- hidden -->after'), '- Beforeafter');
    expect(plainText('Before<!-- unfinished'), 'Before<!-- unfinished');
    expect(plainText('<!-- unfinished\nsecret'), isEmpty);
  });

  test('GitHub HTML examples in code and escaped text stay literal', () {
    expect(plainText('`<!-- visible -->`'), '<!-- visible -->');
    expect(plainText('```html\n<!-- visible -->\n<br/>\n```'),
        contains('<!-- visible -->\n<br/>'));
    expect(plainText(r'\<!-- visible -->'), '<!-- visible -->');
    expect(plainText('&lt;!-- visible --&gt;'), '<!-- visible -->');
  });

  test('GitHub HTML break spellings work inline and as standalone blocks', () {
    for (final tag in ['<br>', '<br/>', '<br />', '<BR/>']) {
      expect(plainText('Before${tag}After'), 'Before\nAfter');
      final document = const MarkdownDocumentParser().parse('$tag\n\nAfter');
      expect((document.blocks.first as ParagraphBlock).inlines.single,
          isA<HardBreakInline>());
      expect(
          plainText(
              '<details><summary>More</summary>\n$tag\n\nAfter\n</details>'),
          isNot(contains('<br')));
    }
  });
}

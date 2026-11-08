import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

List<String> _blockIds(List<BlockNode> blocks) {
  final ids = <String>[];
  void visit(BlockNode block) {
    ids.add(block.id);
    switch (block) {
      case QuoteBlock(:final children) || DetailsBlock(:final children):
        children.forEach(visit);
      case ListBlock(:final items) || FootnoteListBlock(:final items):
        for (final item in items) {
          item.children.forEach(visit);
        }
      default:
    }
  }

  blocks.forEach(visit);
  return ids;
}

void main() {
  group('appendChunk block ids', () {
    test('a streamed paragraph keeps its id', () {
      final controller = MarkdownController(data: '# Title\n\nStreaming');
      final heading = controller.document.blocks.first;
      final id = controller.document.blocks.last.id;

      for (final chunk in <String>[' text', ' keeps', ' growing.']) {
        controller.appendChunk(chunk);
        expect(controller.document.blocks, hasLength(2));
        expect(identical(controller.document.blocks.first, heading), isTrue);
        expect(controller.document.blocks.last.id, id);
      }
      expect(
        controller.plainText,
        contains('Streaming text keeps growing.'),
      );
    });

    test('a streamed fenced code block keeps its id after it closes', () {
      final controller = MarkdownController(
        data: 'Intro\n\n```dart\nfinal a = 1;',
      );
      final id = controller.document.blocks.last.id;

      for (final chunk in <String>[
        '\nfinal b = 2;',
        '\nfinal c = 3;',
        '\n```'
      ]) {
        controller.appendChunk(chunk);
        final code = controller.document.blocks.last as CodeBlock;
        expect(code.id, id);
      }
      expect(
        (controller.document.blocks.last as CodeBlock).code,
        'final a = 1;\nfinal b = 2;\nfinal c = 3;',
      );

      controller.appendChunk('\n\nAfter');
      expect(controller.document.blocks, hasLength(3));
      expect(controller.document.blocks[1].id, id);
      expect(controller.document.blocks.last, isA<ParagraphBlock>());
      expect(controller.document.blocks.last.id, isNot(id));
    });

    test('a streamed list keeps its id and the ids of its items', () {
      final controller = MarkdownController(data: 'Intro\n\n- first item');
      final list = controller.document.blocks.last as ListBlock;
      final firstItemIds = _blockIds(list.items.first.children);

      controller.appendChunk(' grows');
      controller.appendChunk('\n- second');
      controller.appendChunk(' item');

      final streamed = controller.document.blocks.last as ListBlock;
      expect(streamed.id, list.id);
      expect(streamed.items, hasLength(2));
      expect(_blockIds(streamed.items.first.children), firstItemIds);

      final secondItemIds = _blockIds(streamed.items.last.children);
      controller.appendChunk(' too');
      final grown = controller.document.blocks.last as ListBlock;
      expect(grown.id, list.id);
      expect(_blockIds(grown.items.last.children), secondItemIds);
    });

    test('streamed ids stay unique in the document', () {
      final controller = MarkdownController(data: '# Title\n\nOne');
      for (final chunk in <String>[
        ' more',
        '\n\n- a',
        '\n- b',
        '\n\n> quote',
        ' text',
        '\n\nTwo',
        '\n\n```\ncode',
        '\n```',
      ]) {
        controller.appendChunk(chunk);
        final ids = _blockIds(controller.document.blocks);
        expect(ids.toSet(), hasLength(ids.length), reason: chunk);
      }
    });

    test('setData still derives ids from the content', () {
      final controller = MarkdownController(data: '# Title\n\nStreaming');
      controller.appendChunk(' text');
      final streamedId = controller.document.blocks.last.id;

      controller.setData('# Title\n\nStreaming text, replaced');
      final parsed = const MarkdownDocumentParser()
          .parse('# Title\n\nStreaming text, replaced');
      expect(
        _blockIds(controller.document.blocks),
        _blockIds(parsed.blocks),
      );
      expect(controller.document.blocks.last.id, isNot(streamedId));
    });
  });

  group('updateData', () {
    test('appends the new suffix while streaming', () {
      final controller = MarkdownController(data: '# Title\n\nIntro');
      final heading = controller.document.blocks.first;
      final paragraphId = controller.document.blocks.last.id;
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.updateData('# Title\n\nIntro text', streaming: true);

      expect(notifications, 1);
      expect(controller.data, '# Title\n\nIntro text');
      expect(identical(controller.document.blocks.first, heading), isTrue);
      expect(controller.document.blocks.last.id, paragraphId);
      expect(controller.streamingState.hasDraft, isTrue);
    });

    test('commits the stream when streaming ends, notifying once', () {
      final controller = MarkdownController(data: 'Intro');
      controller.updateData('Intro text', streaming: true);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.updateData('Intro text, done.');

      expect(notifications, 1);
      expect(controller.data, 'Intro text, done.');
      expect(controller.streamingState.hasDraft, isFalse);
      expect(controller.streamingState.committedBlocks, hasLength(1));
    });

    test('commits unchanged data and then does nothing', () {
      final controller = MarkdownController(data: 'Intro');
      controller.updateData('Intro text', streaming: true);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.updateData('Intro text');
      expect(notifications, 1);
      expect(controller.streamingState.hasDraft, isFalse);

      controller.updateData('Intro text');
      controller.updateData('Intro text', streaming: true);
      expect(notifications, 1);
    });

    test('parses in full when the data does not extend the current data', () {
      final controller = MarkdownController(data: '# Title\n\nIntro');
      final heading = controller.document.blocks.first;
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.updateData('# Other\n\nIntro', streaming: true);

      expect(notifications, 1);
      expect(controller.data, '# Other\n\nIntro');
      expect(identical(controller.document.blocks.first, heading), isFalse);
      expect(controller.streamingState.hasDraft, isFalse);
    });

    test('matches setData for the final text', () {
      const finalText = '# Title\n\nIntro text\n\n- a\n- b\n\n```dart\nx\n```';
      final streamed = MarkdownController();
      for (var end = 1; end <= finalText.length; end += 3) {
        streamed.updateData(finalText.substring(0, end), streaming: true);
      }
      streamed.updateData(finalText);
      final full = MarkdownController(data: finalText);

      expect(streamed.data, full.data);
      expect(streamed.plainText, full.plainText);
      expect(
        streamed.document.blocks.map((block) => block.runtimeType).toList(),
        full.document.blocks.map((block) => block.runtimeType).toList(),
      );
    });

    test('normalizes CRLF data and does not append across a pending CR', () {
      final controller = MarkdownController(data: 'Line');
      controller.updateData('Line\r\nNext', streaming: true);
      expect(controller.data, 'Line\nNext');

      final pendingCr = MarkdownController(data: 'Line');
      pendingCr.appendChunk('\r');
      expect(pendingCr.data, 'Line\n');
      // The appended '\n' must not be taken as the LF of the pending CR.
      pendingCr.updateData('Line\n\nNext');
      expect(pendingCr.data, 'Line\n\nNext');
      expect(pendingCr.document.blocks, hasLength(2));
    });
  });
}

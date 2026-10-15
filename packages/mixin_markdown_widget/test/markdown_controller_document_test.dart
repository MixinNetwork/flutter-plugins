import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

void main() {
  const data = '# Title\n\nSome **bold** text with `code`.\n\n> quote\n\n'
      '| a | b |\n| - | - |\n| 1 | 2 |\n';

  test('a document parsed in an isolate matches a controller parse', () async {
    final document = await Isolate.run(
      () => MarkdownController.parseDocument(data),
    );
    final parsed = MarkdownController(data: data);
    final given = MarkdownController(data: data, document: document);

    expect(identical(given.document, document), isTrue);
    expect(given.version, parsed.version);
    expect(given.plainText, parsed.plainText);
    expect(
      given.document.blocks.map((block) => block.runtimeType).toList(),
      parsed.document.blocks.map((block) => block.runtimeType).toList(),
    );
  });
}

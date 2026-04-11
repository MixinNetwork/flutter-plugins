# mixin_markdown_widget

`mixin_markdown_widget` is a desktop-first Flutter Markdown reader package. It focuses on a high-quality reading surface, configurable theming, block-based rendering, and controller APIs that can already support streamed updates.

## Features

- `MarkdownWidget` for direct string input or controller-driven rendering
- `MarkdownController` with `setData`, `replaceAll`, `appendChunk`, and `clear`
- `MarkdownSelectionController` for model-driven selection, select-all, and copy-selection flows
- Plain-text serialization and clipboard export through `MarkdownController.plainText` and `copyPlainTextToClipboard()`
- `MarkdownThemeData` and `MarkdownTheme` for document-level styling
- Built-in rendering for headings, paragraphs, quotes, ordered/unordered/task lists, definition lists, footnotes, code blocks, tables, images, and thematic breaks
- Syntax-highlighted code blocks with character-level custom selection
- Table cell drag selection with TSV/plain-text copy output
- Custom desktop selection with text-level hit testing and highlight coverage across paragraphs, headings, lists, quotes, captions, and code blocks
- Double-click word selection, triple-click block selection, and selection-aware copy flows
- Right-click menu support for `Copy`, `Select all`, `Copy all`, and `Clear selection`
- Copy button for code blocks
- `Ctrl/Cmd+C` to copy the current custom selection, `Ctrl/Cmd+A` to select all, and `Ctrl/Cmd+Shift+C` to copy the full document as predictable plain text
- Append-only incremental reparsing for `appendChunk`, with stable prefix block reuse
- `pretext`-backed inline rendering for headings, paragraphs, list item text, quote text, and table cells, including rich inline emphasis/link/code runs
- Extended markdown syntax support for heading IDs, autolinks, emoji shortcodes, footnotes, task lists, definition lists, strikethrough, highlight, subscript, and superscript
- Common inline HTML tag support for `em`, `strong`, `del`, `mark`, `sub`, `sup`, `code`, and `br`
- Unified custom selection behavior even when no external `MarkdownSelectionController` is supplied
- Custom `imageBuilder` output can participate in selection/copy flows using the image caption text

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = MarkdownThemeData.fallback(context);
    return MarkdownWidget(
      data: '# Hello\n\nThis is **Markdown**.',
      theme: baseTheme.copyWith(
        maxContentWidth: 840,
        codeBlockBackgroundColor: const Color(0xFFF5F7FB),
      ),
    );
  }
}
```

For streaming or incremental updates, keep a controller and append chunks as they arrive:

```dart
final controller = MarkdownController(data: '# Streamed output');
final selectionController = MarkdownSelectionController();

controller.appendChunk('\n\nNew content arrived.');
controller.commitStream();
selectionController.attachDocument(controller.document);
selectionController.selectAll();
```

## Current scope

This implementation now includes syntax-highlighted code blocks, character-level code selection, table cell range selection with TSV copy semantics, a document-level plain-text serializer, a model-level selection controller, custom pointer hit testing, and controller-managed draft/committed streaming state. `appendChunk` reparses only the unstable trailing block instead of the full document, unchanged cacheable blocks are reused across document updates, and inline text in headings, paragraphs, list item bodies, quote bodies, and table cells now shares the same `pretext`-backed inline rendering path even with rich inline formatting. In addition to the original CommonMark-style blocks, the package now covers task lists, definition lists, footnotes, heading IDs, autolinks, emoji shortcodes, highlight, subscript, superscript, and a small safe subset of inline HTML tags.

Run `flutter test benchmark/incremental_append_benchmark.dart` from this package to compare full reparsing against append-only incremental parsing.

See `/example` for a runnable desktop demo.

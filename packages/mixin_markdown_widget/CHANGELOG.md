# Changelog

## 0.3.0

**BREAKING CHANGE**

* remove `MarkdownDocument.sourceText` from the public document model
* add `MixinSelectionArea` and shared selection scope for composite selections
* improve composite selection across quotes, lists, tables, and mixed selectable widgets
* improve inline code wrapping and decorated inline selection geometry
* improve incremental append parsing, footnote handling, and local image fallback
* add debug logging support and expand example and regression coverage

## 0.2.1

* [mixin_markdown_widget] enhance Markdown rendering [#476](https://github.com/MixinNetwork/flutter-plugins/pull/476)

## 0.2.0

**BREAKING CHANGE**

* [mixin_markdown_widget]: improve text wrapping and boundary handling for decorated inline elements
* mixin_markdown_widget: improve block spacing logic and adjust theme defaults
* [mixin_markdown_widget]: improve code highlight cache with presentation signature
* [mixin_markdown_widget]: add horizontal scrolling support for wide tables and code blocks
* feat: enhance Markdown widget with new themes
* feat: add nested scrollable repaint listeners and viewport clipping for selection rects
* feat: add pub.dev metadata for mixin_markdown_widget

## 0.1.0

- Initial implementation

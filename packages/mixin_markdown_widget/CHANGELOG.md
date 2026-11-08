# Changelog

## 0.4.0

### Breaking changes

- `MarkdownContextMenuBuilder` is now `Widget Function(BuildContext, MarkdownContextMenuDetails)`. The details carry the menu `anchors`, the default `buttonItems`, the `selectionController`, the `linkDestination` under the pointer, and `hide`. `contextMenuBuilder` now defaults to `defaultMarkdownContextMenuBuilder`, and passing `null` shows no menu. See the README for an example. ([#551](https://github.com/MixinNetwork/flutter-plugins/pull/551))
- Remove `MarkdownContextMenu`. Use `defaultMarkdownContextMenuBuilder` or build the menu from `MarkdownContextMenuDetails.buttonItems`. ([#551](https://github.com/MixinNetwork/flutter-plugins/pull/551))
- Deprecate `showCopyAllInContextMenu` on `MarkdownWidget` and `MixinSelectionArea`. Filter `MarkdownContextMenuDetails.buttonItems` in `contextMenuBuilder` instead. ([#551](https://github.com/MixinNetwork/flutter-plugins/pull/551))

### Right-click menu

- Right clicking keeps a selection under the pointer. Elsewhere, macOS and iOS select the word under the pointer and other platforms clear the selection. ([#551](https://github.com/MixinNetwork/flutter-plugins/pull/551))
- Show Copy only when text is selected, add Copy link over links, and remove Clear selection. ([#551](https://github.com/MixinNetwork/flutter-plugins/pull/551))
- Close the menu on Escape, scrolling, and any click. `MarkdownWidget` and `MixinSelectionArea` now share the same menu behavior. ([#551](https://github.com/MixinNetwork/flutter-plugins/pull/551))

### Selection

- Double clicking Chinese and other non-ASCII text selects a dictionary word through [`word_segmenter`](https://pub.dev/packages/word_segmenter), and CJK punctuation ends a word. ASCII text keeps its rule. ([#543](https://github.com/MixinNetwork/flutter-plugins/pull/543), [#550](https://github.com/MixinNetwork/flutter-plugins/pull/550))
- Fix double clicking the end of a table cell, quote paragraph, list item, or details summary selecting the word of the next cell or block. ([#544](https://github.com/MixinNetwork/flutter-plugins/pull/544))
- Fix `MixinSelectionArea` around a `MarkdownWidget` rebuilding on every frame. ([#552](https://github.com/MixinNetwork/flutter-plugins/pull/552))

### Streaming

- Add `MarkdownController.updateData`, which appends when the new text extends the current data and parses in full otherwise. ([#543](https://github.com/MixinNetwork/flutter-plugins/pull/543))
- Keep the streamed tail block and its nested blocks mounted across `appendChunk`, so their state, code block scroll position, and caches survive each chunk. ([#543](https://github.com/MixinNetwork/flutter-plugins/pull/543))
- Show the last highlight of a growing code block instead of flashing plain text, and run at most one highlight per block at a time. ([#543](https://github.com/MixinNetwork/flutter-plugins/pull/543))
- Fix link taps in cached list and quote rows using disposed recognizers, and keep the row cache when `onTapLink` is a new closure on each rebuild. ([#543](https://github.com/MixinNetwork/flutter-plugins/pull/543))
- Deprecate the misspelled `MarkownWidget` alias and `MarkdownDocumentParser.parseAppending`, which ignores its previous document. ([#543](https://github.com/MixinNetwork/flutter-plugins/pull/543))

## 0.3.3

* Add `MarkdownController.parseDocument` and a `document` argument to `MarkdownController`, so an app can parse a document in an isolate before the widget builds.
* Add `MarkdownController.highlightCodeBlocks` and `MarkdownController.cacheCodeHighlights`, so an app can highlight the code blocks of a parsed document in an isolate.
* Show cached code highlights in the first frame, instead of plain code followed by a rebuild of the document.
* Measure pretext text less: share width, line height, and tight text metrics measurements, measure each segment once per run, and merge plain fragments of a line.

## 0.3.2

* Hide HTML comments and GitHub review metadata in rendered and copied Markdown while preserving literal comments in code and escaped text.
* Preserve fallback text inside `relative-time`, `local-time`, and `time` HTML elements.
* Support self-closing HTML line breaks such as `<br/>`, including inside expandable details.
* Preserve source ranges and incremental streaming behavior around hidden HTML comments.
* Fix local images using absolute Windows paths being mistaken for URI schemes.

## 0.3.1

* mixin_markdown_widget: fix contextual inline styling

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

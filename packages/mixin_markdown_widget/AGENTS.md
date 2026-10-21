# AGENTS

## Scope

This file captures package-specific guidance for the `mixin_markdown_widget` library subtree. Use it when changing anything under `packages/mixin_markdown_widget/lib/` and keep it aligned with the package's actual architecture.

## What This Package Is

`mixin_markdown_widget` is a desktop-first Flutter Markdown reader library with:

- block-based document parsing and rendering
- controller-driven updates, including append-style streaming
- a custom model-level selection engine instead of Flutter's default text selection stack
- predictable plain-text serialization for copy/export flows
- pretext-backed inline text rendering for much of the document surface

The public entrypoint is [packages/mixin_markdown_widget/lib/mixin_markdown_widget.dart](packages/mixin_markdown_widget/lib/mixin_markdown_widget.dart).

## Important Source Areas

- `src/widgets/markdown_widget.dart`: top-level widget API, fallback controller ownership, theme wiring, and document/selection attachment.
- `src/widgets/markdown_controller.dart`: document ownership, `setData`, `replaceAll`, `appendChunk`, `commitStream`, and plain-text copy helpers.
- `src/core/document.dart`: internal document model (`BlockNode`, `InlineNode`, selections, image block metadata).
- `src/parser/markdown_document_parser.dart`: Markdown AST to internal model conversion, including append-only incremental reparsing.
- `src/render/markdown_document_view.dart`: main state orchestrator and coordinator. Connects blocks, selections, gestures, and UI builders together without doing heavy layout math.
- `src/render/builder/`: contains `markdown_block_builder.dart` and `markdown_inline_builder.dart` which convert `BlockNode` and `InlineNode` respectively into actual visual `Widget`s or `TextSpan`s.
- `src/render/selection/`: contains `markdown_selectable_leaf.dart` (selectable text leaves, structural slots, and the per-block leaf registry), `markdown_selection_geometry.dart` (the one container algorithm for quotes, details, lists, footnotes, and tables), `markdown_block_keys_registry.dart` (top-level block keys, scroll controllers, viewport keys), `markdown_descriptor_extractor.dart` (rendered text and spans for definition lists, captions, and container text spans), and `markdown_selection_gesture_detector.dart` (drags, auto-scroll).
- `src/render/shortcuts/`: keyboard action Intents (like `SelectAllMarkdownIntent`) and their bindings.
- `src/selection/selection_host.dart`: shared by `MarkdownDocumentView` and `MixinSelectionArea`. Owns focus, tap-outside clearing, and the right-click menu (selection on right click, default button items, closing on Escape, scrolling, and clicks).
- `src/render/markdown_block_widgets.dart`: shared block UI widgets for lists, quotes, tables, code blocks, and other visual shells.
- `src/render/pretext_text_block.dart`: pretext-backed inline layout and line geometry used by text leaves.
- `src/selection/selection_controller.dart`: authoritative selection state. Clamping and select-all delegate to `MarkdownPlainTextSerializer`.
- `src/selection/structured_block_selection.dart`: the structured selection model of each block (leaves, display/export text), cached per `BlockNode`.
- `src/clipboard/plain_text_serializer.dart`: canonical plain-text export semantics for whole documents, ranges, lists, quotes, footnotes, and tables.

## Non-Negotiable Invariants

### Widget/controller contract

- `MarkdownWidget` requires exactly one of `data` or `controller`.
- When `selectable == true`, `MarkdownWidget` creates and uses an internal fallback `MarkdownSelectionController` if the caller does not provide one.
- Selection behavior is intentionally custom. Do not silently replace it with Flutter `SelectionArea` or stock rich-text selection behavior.

### Public API discipline

- Keep exported APIs flowing through the top-level library file.
- If a new public type or helper is meant for callers, update the top-level export surface instead of leaving it reachable only through `src/` imports.

### Incremental parsing and identity

- `MarkdownController.appendChunk()` depends on append-only reparsing of the unstable tail instead of reparsing the whole document.
- Stable prefix blocks and IDs matter for rebuild reuse and streaming behavior. Avoid parser changes that churn unchanged blocks unnecessarily.

### Selection architecture

- Selection is model-based: `DocumentPosition`, `DocumentSelection`, and `DocumentRange` must stay coherent with what is rendered.
- `MarkdownPlainTextSerializer` defines copy semantics and selection bounds. The selection controller clamps and selects all through it, so a serializer subclass changes both consistently. If rendering or selection behavior changes, make sure serializer output still matches the logical selection.
- A table is selected as text: cells joined with `\t` and rows with `\n`. Each non-empty cell is a leaf at path `[row, column]`; there is no separate table-cell selection type.
- `StructuredBlockSelection.forBlock` is cached per `BlockNode` and is the single source of block text for the serializer, clamping, select-all, and container geometry. Do not rebuild block text elsewhere.
- Composite blocks such as lists, quotes, tables, and footnotes now use a structured selection index: `DocumentPosition.path` identifies the semantic leaf while `textOffset` stays in block display-text space. Do not flatten these selections back to `PathInBlock([0])` just to make offset math easier.
- Range-copy serialization should use the structured visible-text space when selection offsets come from rendered interaction, and full-document export/select-all should come from the same structured model's export leaves.
- Structured blocks now also carry export-text leaves. Full-block export and `selectAll` should use those structured export leaves while keeping selection offsets in visible text space; do not depend on serialized-length mismatches to trigger fallback behavior.
- Leaf-local and block display offsets are converted exactly once, through the `StructuredBlockSelectionLeaf` of the leaf (`displayedOffsetForLocalOffset` / `localOffsetForDisplayedOffset`). Containers never re-convert per nesting level.
- Double-click word selection and triple-click selection-unit resolution must stay aligned with the same offset mapping semantics used by drag selection.

### Pretext-backed text rules

- Headings, paragraphs, list item text, quote text, and table cell text share pretext-backed inline rendering in important paths.
- Pretext selection rectangles must use the rendered line box height (`lineHeight`) for top/bottom edges, not glyph box heights from `TextPainter`, or selection backgrounds will look vertically short.
- If selection looks horizontally correct but vertically off, inspect `pretext_text_block.dart` first.
- Pretext selection units should prefer the clicked visual line when local pointer geometry is available; if only a text offset is available, fall back to explicit newline boundaries of the leaf text.

### Selection geometry: leaves and containers

- Every selectable piece of text is a `MarkdownSelectableLeaf`, registered by its `PathInBlock` in the `MarkdownSelectionLeafScope` of its `SelectableMarkdownBlock`. A leaf answers its own geometry in its box coordinates and local offsets: `rectsFor`, `offsetAt`, `lineRangeAt`, an optional `clipRect` (the viewport of a horizontally scrolling code block or table), and its origin in the block.
- Leaf kinds: text leaves (`MarkdownTextLeafGeometry`, reading the live `RenderParagraph` when the runs render as one rich text and pretext otherwise), and placeholder leaves (`MarkdownPlaceholderLeafGeometry`) for images, thematic breaks, standalone line breaks, and custom code block builders, which select as a whole.
- Paragraphs, headings, code blocks, definition lists, and image captions are one leaf at `[0]`. Quotes, details, lists, footnotes, and tables use `MarkdownContainerSelectionGeometry`, which only orders leaves and reads `MarkdownSelectionSlot` boxes (child blocks, list rows, list content). Containers do not measure text themselves and keep no per-child `GlobalKey`s.
- Container rules: in a gap between stacked children, split at the gap midpoint (within 24px of horizontal overlap); otherwise use the nearest child's start or end. On a list item, the marker selects the item start and the marker rect spans the marker extent, aligned to the first line of the item's first child. A leading paragraph or heading takes its marker along in line selection. A table resolves to the nearest non-empty cell, and its selection unit is the whole cell.
- Leaf paths must match `StructuredBlockSelection`: quote child `[..., i]`, details summary `[..., 0]` and children `[..., i + 1]`, list marker `[..., item, 0]` and item children `[..., item, c + 1]`, table cell `[..., row, column]`.

### Decorated blocks and overlays

- Blocks with their own visual chrome, such as quotes, code blocks, and tables, need selection overlays painted in the foreground when the decoration would otherwise hide the highlight.

### Links and images

- Link taps and selection interact in subtle ways. Immediate collapsed selection on pointer-down can dispose tap recognizers before `onTap` fires.
- Standalone linked images like `[![alt](src)](href)` should be normalized into `ImageBlock` with link metadata rather than degrading to inline-image text behavior.
- Default image handling supports network images, local file images through the IO-only helper, and asset fallback paths.

### Footnotes and list-like structures

- Footnotes are rendered through ordered-list-style layout/selection machinery, not as one flattened text blob.
- Parser-side footnote backreference anchors should be stripped before building visible footnote blocks.
- Tight list, definition list, and footnote container parsing must preserve rich inline content by merging consecutive inline AST nodes into a single paragraph block where appropriate.

## High-Risk Change Areas

- `src/render/selection/markdown_selection_geometry.dart` and `markdown_selectable_leaf.dart`: small geometry changes can break hit testing, copy semantics, nested selection, or link tapping.
- `markdown_document_parser.dart`: parser shape changes often require matching updates in rendering, serializer logic, and regression tests.
- `plain_text_serializer.dart`: changing output shape affects copy/paste, select-all, and many selection assertions.
- `pretext_text_block.dart`: selection height/offset bugs often originate here even when the visible issue appears in quotes or lists.

## Expected Validation

- Run targeted widget tests for the behavior you changed.
- For package-level regression coverage, use `flutter test test/mixin_markdown_widget_test.dart` from `packages/mixin_markdown_widget/`.
- For incremental parsing performance comparisons, use `flutter test benchmark/incremental_append_benchmark.dart`.
- If the issue is visual or interaction-heavy, verify with the `example/` app in addition to tests.

## When Making Changes

- Update tests with the behavior change instead of relying on manual verification only.
- Prefer minimal changes in parser, serializer, and selection geometry; these pieces are tightly coupled.
- Preserve existing public behavior unless the request explicitly asks for a semantic change.
- When fixing selection bugs, check all three layers together:
  - rendered geometry
  - hit-testing / text offset resolution
  - plain-text serialization of the resulting selection

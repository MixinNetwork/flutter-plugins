# mixin_markdown_widget

[![Pub](https://img.shields.io/pub/v/mixin_markdown_widget.svg)](https://pub.dev/packages/mixin_markdown_widget)

`mixin_markdown_widget` is a high-performance, desktop-first Flutter Markdown reader package. It focuses on a high-quality reading surface, highly customizable block-based rendering, model-driven text selection, and controller APIs optimized for streaming updates (like LLM responses).

## Key Features

- **Streaming Ready:** `MarkdownController` with `appendChunk` and `commitStream` supports append-only incremental parsing for smooth LLM output rendering.
- **Custom Selection Engine:** Built-in model-driven selection (`MarkdownSelectionController`) supporting double-click word selection, triple-click block selection, table cell range selection, and predictable plain-text clipboard export.
- **Rich Syntax Support:** Supports CommonMark, GFM task lists, tables, footnotes, definition lists, math (TeX), and common inline HTML tags.
- **Highly Customizable Rendering:**
  - Override specific block rendering using `codeBlockBuilder` and `bulletBuilder`.
  - Customize image rendering with `imageBuilder` and link handling with `onTapLink`.
  - Disable default scroll view (ListView) using `useColumn: true` for easy integration into existing custom scrollable layouts.
- **Theming:** `MarkdownThemeData` allows deep customization of text styles, spacing, colors, and block decorations (e.g., hiding heading dividers via `showHeading1Divider`).

## Usage

### Basic Rendering

```dart
import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MarkdownWidget(
      data: '# Hello\n\nThis is **Markdown**.',
      // Customize theme
      theme: MarkdownThemeData.fallback(context).copyWith(
        showHeading1Divider: false, // Hide H1 underlines
      ),
      // Set to true if you are wrapping this in your own ScrollView
      useColumn: false, 
    );
  }
}
```

### Customizing Blocks

You can easily override the default rendering for specific blocks:

```dart
MarkdownWidget(
  data: data,
  // Custom code block rendering
  codeBlockBuilder: (context, code, language, theme) {
    return CustomCodeBlockView(code: code, language: language);
  },
  // Custom list marker rendering
  bulletBuilder: (context, index, isOrdered, orderedStart, taskState, theme) {
    if (taskState != null) return CustomCheckbox(state: taskState);
    if (isOrdered) return Text('${orderedStart! + index}.');
    return const Icon(Icons.circle, size: 8);
  },
)
```

### Generic Selection Area

`MixinSelectionArea` can wrap non-Markdown widget trees. Text-like children opt in
with `MixinSelectableText`, or with `MixinSelectable` when a custom text widget
needs to provide its own hit-test and selection geometry.

```dart
MixinSelectionArea(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: const [
      MixinSelectableText('Selectable custom text'),
      SizedBox(height: 8),
      MixinSelectableText('Drag selection can cross widgets'),
    ],
  ),
)
```

### Streaming / Incremental Updates

For streaming or incremental updates, keep a controller and append chunks as they arrive. `appendChunk` reparses only the unstable trailing block instead of the full document, ensuring high performance.

```dart
final controller = MarkdownController(data: '# Streamed output');

// As data arrives from network/LLM:
controller.appendChunk('\n\nNew content arrived.');

// When stream finishes:
controller.commitStream();
```

See the `/example` directory for a fully runnable desktop demo.

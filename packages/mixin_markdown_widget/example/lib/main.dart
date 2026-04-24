import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

import 'ai_chat_demo.dart';

enum _DemoThemePreset {
  ocean,
  warm,
  tight,
}

enum _DemoLayoutMode {
  split,
  previewOnly,
}

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0B7A75),
      ),
      home: const MarkdownDemoPage(),
    );
  }
}

class MarkdownDemoPage extends StatefulWidget {
  const MarkdownDemoPage({super.key});

  @override
  State<MarkdownDemoPage> createState() => _MarkdownDemoPageState();
}

class _MarkdownDemoPageState extends State<MarkdownDemoPage> {
  late final MarkdownController _controller;
  late final MarkdownSelectionController _selectionController;
  late final TextEditingController _editorController;
  var _themePreset = _DemoThemePreset.ocean;
  var _layoutMode = _DemoLayoutMode.split;
  var _chunkIndex = 0;
  var _isApplyingProgrammaticEdit = false;

  static const _initialMarkdown = r'''
# Mixin Markdown Widget Showcase

Welcome to the comprehensive demo of **mixin_markdown_widget**. This document is designed to push the parser and renderer to their limits, ensuring robust selection, beautiful geometry, and full feature coverage.

> **Note:** You can edit this text on the left, and it will render instantly on the right. Try selecting text across different blocks to see our advanced path-based smooth selection highlights!

---

## 1. Typography & Inline Styles

This widget supports all standard inline syntax:
* *Italicized text* 
* **Bold emphasis** 
* ***Bold and italic***
* ~~Strikethrough~~
* `inline code snippets`
* Link to [Flutter](https://flutter.dev), and an auto-link: <https://github.com>

Here is a block with mixed inline math: Einstein's famous equation is \( E = mc^2 \), while the quadratic formula is \( x = \frac{-b \pm \sqrt{b^2 -4ac}}{2a} \). 
Notice how selection seamlessly wraps around inline blocks without layout jumps.

And don't forget about footnotes! Here is a reference to a footnote.[^1] And here is another.[^2]

## 2. Lists, Tasks, & Nesting

Markdown isn't complete without lists. And lists inside lists. And quotes inside lists!

### Standard Lists

*   **Fruit**
    *   Apple
    *   Banana
        *   Cavendish
        *   Plantain
*   **Vegetables**
    1.  Carrot
    2.  Broccoli

### Task Lists (Checkboxes)

- [x] Write the core widget logic
- [x] Implement selection handles & gestures
- [ ] Implement robust horizontal scroll boundaries
- [ ] Add real-time streaming parser support
  - [x] Design token chunking
  - [ ] Connect socket layer

### Lists containing advanced blocks

1.  **Code implementation:**
    Here is a quick way to compute a sum in JavaScript:
    
    ```javascript
    function sum(a, b) {
      return a + b;
    }
    console.log(sum(5, 10)); // 15
    ```

2.  **Mathematical definitions:**
    And here is the sum expressed mathematically:
    
    $$
    \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
    $$
    
    > Blockquotes can also live gracefully inside list items. The selection background will adapt to the indentation perfectly.

## 3. Deeply Nested Blockquotes

We tested the nested layout extensively to ensure borders, padding, and text selections don't break even under extreme nesting.

> Level 1: The outer quote.
> > Level 2: The inner quote.
> > > Level 3: Deep quote containing a math block!
> > > 
> > > $$
> > > \int_a^b f(x) dx = F(b) - F(a)
> > > $$
> > > 
> > > And some inline `code` for good measure.
> > 
> > Back to Level 2.
> 
> Back to Level 1.

## 4. Complex Tables

Tables support varying alignments, complex cell contents, and inline styles.

| Feature | Description | Status |
| :--- | :---: | ---: |
| **Parsing** | Fast incremental markdown parsing | ✅ |
| **Selection** | Seamless multi-block text selection | ✅ |
| **Math** | Full LaTeX parsing & rendering (\( \alpha^2 \)) | ✅ |
| **Code** | Syntax highlighting with *re_highlight* | 🚀 Built |

### Wide table for horizontal scrolling

The table below is intentionally wider than the preview pane. In split mode, it should trigger horizontal scrolling so you can inspect every column without shrinking the content.

| Release train | Rendering pipeline | Selection engine | Clipboard export | Incremental parser tail window | Nested quote layout | Syntax highlighter | Platform notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026.04 desktop preview | Pretext paragraph and block renderer | Path-based structured range selection | Plain-text serializer with table-aware export | Append-only reparsing of unstable trailing blocks | Multi-depth quote border and overlay painting | re_highlight with fenced code theming | macOS and Windows tuned for pointer-heavy interactions |
| 2026.04 mobile fallback | Shared markdown block widgets with adaptive spacing | Gesture-driven selection anchors with drag auto-scroll | Whole-document copy and visible-range copy actions | Draft chunk merge before commit to stable document nodes | Nested block measurement through real child subtree geometry | Inline code plus fenced language classification | Android and iOS remain functional but the package is optimized for desktop |
| Experimental branch | Stress-test layout using intentionally long cells_that_do_not_wrap_easily | Table text selection stays separate from cell selection semantics | Serializer preserves row and column ordering in exported plain text | Stable prefix block identity reduces rebuild churn during streaming | Quote selection follows rendered descendants instead of flattened synthetic text | Large code blocks keep decoration and selection overlays in sync | Useful for validating horizontal overflow behavior inside the example app |

## 5. Media & Links

Images are responsive and support border radiuses based on your specific `MarkdownThemeData`. They can also act as image links!

[![Spectacular mountain landscape](https://picsum.photos/id/1011/960/400)](https://picsum.photos)

## 6. The Edge Cases & Formatting

Horizontal rules separate content cleanly:

***

You can also use HTML tags like `<kbd>` depending on your parser config: Press <kbd>Ctrl</kbd> + <kbd>C</kbd> to copy.

Finally, testing seamless text selection bridging an empty paragraph line to a dense block of text!

Line one.

Line two.

```python
def test_edge_case():
    # Notice the selection corners on the empty lines below:
    
    
    print("Empty lines inside code blocks shouldn't break corner heuristics!")
```

## Footnotes

[^1]: This is the first footnote. It provides additional context about the text above without breaking the flow.
[^2]: This is the second footnote. It can also contain inline formulas like \( a^2 + b^2 = c^2 \).

End of showcase. Feel free to break things!
''';

  static const _streamChunks = <String>[
    '''

## Stream chunk 1

This content was appended through `MarkdownController.appendChunk`.
''',
    '''

## Stream chunk 2

| Phase | Focus |
| --- | --- |
| 1 | Widget and theme |
| 2 | Selection and copy |
| 3 | Streaming optimization |
''',
  ];

  @override
  void initState() {
    super.initState();
    _controller = MarkdownController(data: _initialMarkdown);
    _selectionController = MarkdownSelectionController()
      ..attachDocument(_controller.document);
    _editorController = TextEditingController(text: _initialMarkdown)
      ..addListener(_handleEditorChanged);
  }

  @override
  void dispose() {
    _editorController
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _selectionController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = _themePreset == _DemoThemePreset.tight
        ? MarkdownThemeData.tight(context)
        : MarkdownThemeData.fallback(context);
    final markdownTheme = _themePreset == _DemoThemePreset.warm
        ? baseTheme.copyWith(
            maxContentWidth: 860,
            quoteBackgroundColor: const Color(0xFFFFF5E0),
            quoteBorderColor: const Color(0xFFD79B36),
            codeBlockBackgroundColor: const Color(0xFFF3E7D2),
            tableHeaderBackgroundColor: const Color(0xFFE8D6B3),
            tableRowBackgroundColor: const Color(0xFFFFFBF3),
            selectionColor: const Color(0x66D79B36),
          )
        : baseTheme.copyWith(maxContentWidth: 920);

    return Scaffold(
      appBar: AppBar(
        title: const Text('mixin_markdown_widget'),
        actions: <Widget>[
          IconButton(
            tooltip: 'AI Chat Demo',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AIChatDemoPage(),
                ),
              );
            },
            icon: const Icon(Icons.chat_outlined),
          ),
          IconButton(
            key: const Key('toggle-editor-visibility'),
            tooltip: _layoutMode == _DemoLayoutMode.split
                ? 'Hide editor'
                : 'Show editor',
            onPressed: () {
              setState(() {
                _layoutMode = _layoutMode == _DemoLayoutMode.split
                    ? _DemoLayoutMode.previewOnly
                    : _DemoLayoutMode.split;
              });
            },
            icon: Icon(
              _layoutMode == _DemoLayoutMode.split
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          PopupMenuButton<_DemoThemePreset>(
            tooltip: 'Switch preview theme',
            initialValue: _themePreset,
            icon: const Icon(Icons.palette_outlined),
            onSelected: (value) {
              setState(() {
                _themePreset = value;
              });
            },
            itemBuilder: (context) => const <PopupMenuEntry<_DemoThemePreset>>[
              PopupMenuItem<_DemoThemePreset>(
                value: _DemoThemePreset.ocean,
                child: Text('Ocean theme (default)'),
              ),
              PopupMenuItem<_DemoThemePreset>(
                value: _DemoThemePreset.warm,
                child: Text('Warm theme (loose)'),
              ),
              PopupMenuItem<_DemoThemePreset>(
                value: _DemoThemePreset.tight,
                child: Text('Tight theme (compact)'),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: _appendChunk,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Append chunk'),
          ),
          IconButton(
            tooltip: 'Copy plain text',
            onPressed: _copyPlainText,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Select all model text',
            onPressed: _selectAllModelText,
            icon: const Icon(Icons.select_all_rounded),
          ),
          AnimatedBuilder(
            animation: _selectionController,
            builder: (context, _) => IconButton(
              tooltip: 'Copy selected model text',
              onPressed: _selectionController.hasSelection
                  ? _copySelectedModelText
                  : null,
              icon: const Icon(Icons.content_copy_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Commit stream draft',
            onPressed:
                _controller.streamingState.hasDraft ? _commitStream : null,
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: 'Reset content',
            onPressed: _resetDocument,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 960;
          final editorPanel = _PaneShell(
            title: 'Editor',
            subtitle: 'Write any Markdown you want. The preview updates live.',
            child: TextField(
              key: const Key('markdown-editor'),
              controller: _editorController,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Menlo',
                  ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Type Markdown here...',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          );
          final previewPanel = _PaneShell(
            title: 'Preview',
            subtitleBuilder: (context) => AnimatedBuilder(
              animation: _selectionController,
              builder: (context, _) => Text(
                _previewSubtitle(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            child: MarkdownWidget(
              key: const Key('markdown-preview'),
              controller: _controller,
              selectionController: _selectionController,
              theme: markdownTheme,
              onTapLink: (destination, _, __) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Link tapped: $destination')),
                );
              },
              contextMenuBuilder: (context, controller, buttonItems, anchors) {
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: anchors,
                  buttonItems: [
                    ...buttonItems,
                    ContextMenuButtonItem(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Custom menu action!')),
                        );
                      },
                      label: '🎉 Custom',
                    ),
                  ],
                );
              },
            ),
          );

          return Padding(
            padding: const EdgeInsets.all(20),
            child: _layoutMode == _DemoLayoutMode.previewOnly
                ? previewPanel
                : isWide
                    ? Row(
                        children: <Widget>[
                          Expanded(child: editorPanel),
                          const SizedBox(width: 20),
                          Expanded(child: previewPanel),
                        ],
                      )
                    : Column(
                        children: <Widget>[
                          Expanded(child: editorPanel),
                          const SizedBox(height: 20),
                          Expanded(child: previewPanel),
                        ],
                      ),
          );
        },
      ),
    );
  }

  void _handleEditorChanged() {
    if (_isApplyingProgrammaticEdit) {
      return;
    }
    _controller.setData(_editorController.text);
    _selectionController.attachDocument(_controller.document);
    _selectionController.clear();
    if (_chunkIndex != 0) {
      setState(() {
        _chunkIndex = 0;
      });
    }
  }

  void _appendChunk() {
    if (_chunkIndex >= _streamChunks.length) {
      return;
    }
    final chunk = _streamChunks[_chunkIndex];
    final nextText = '${_editorController.text}$chunk';
    _controller.appendChunk(chunk);
    _selectionController.attachDocument(_controller.document);
    _selectionController.clear();
    _isApplyingProgrammaticEdit = true;
    _editorController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    _isApplyingProgrammaticEdit = false;
    setState(() {
      _chunkIndex += 1;
    });
  }

  void _commitStream() {
    _controller.commitStream();
    _selectionController.attachDocument(_controller.document);
    setState(() {});
  }

  void _copyPlainText() {
    _controller.copyPlainTextToClipboard();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied plain text to clipboard')),
    );
  }

  void _selectAllModelText() {
    _selectionController.attachDocument(_controller.document);
    _selectionController.selectAll();
    setState(() {});
  }

  void _copySelectedModelText() {
    _selectionController.copySelectionToClipboard();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied selected model text')),
    );
  }

  void _resetDocument() {
    _controller.setData(_initialMarkdown);
    _selectionController.attachDocument(_controller.document);
    _selectionController.clear();
    _isApplyingProgrammaticEdit = true;
    _editorController.value = TextEditingValue(
      text: _initialMarkdown,
      selection: TextSelection.collapsed(offset: _initialMarkdown.length),
    );
    _isApplyingProgrammaticEdit = false;
    setState(() {
      _chunkIndex = 0;
    });
  }

  String _previewSubtitle() {
    final streamingState = _controller.streamingState;
    final stateLabel = streamingState.hasDraft
        ? 'Streaming: ${streamingState.committedBlocks.length} committed + 1 draft block.'
        : 'Streaming: ${streamingState.committedBlocks.length} committed blocks.';
    final selectionLabel = _selectionController.hasSelection
        ? 'Model selection: ${_selectionController.selectedPlainText.length} chars.'
        : 'Model selection: none.';
    if (_layoutMode == _DemoLayoutMode.previewOnly) {
      return 'Preview-only mode. Current theme: ${_themeLabel(_themePreset)}. $stateLabel $selectionLabel';
    }
    return 'Current theme: ${_themeLabel(_themePreset)}. Links surface through the host app. $stateLabel $selectionLabel';
  }

  String _themeLabel(_DemoThemePreset preset) {
    switch (preset) {
      case _DemoThemePreset.ocean:
        return 'Ocean';
      case _DemoThemePreset.warm:
        return 'Warm';
      case _DemoThemePreset.tight:
        return 'Tight';
    }
  }
}

class _PaneShell extends StatelessWidget {
  const _PaneShell({
    required this.title,
    required this.child,
    this.subtitle,
    this.subtitleBuilder,
  });

  final String title;
  final Widget child;
  final String? subtitle;
  final WidgetBuilder? subtitleBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            if (subtitleBuilder != null)
              subtitleBuilder!(context)
            else if (subtitle != null)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

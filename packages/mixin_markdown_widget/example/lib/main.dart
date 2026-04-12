import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

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

This widget supports all standard inline syntax, including *italicized text*, **bold emphasis**, ~~strikethrough~~, and `inline code snippets`. 
You can mix them up: ***bold italics*** or **bold with `code`**.

Here is a block with mixed inline math: Einstein's famous equation is \( E = mc^2 \), while the quadratic formula is \( x = \frac{-b \pm \sqrt{b^2 -4ac}}{2a} \). 
Notice how selection seamlessly wraps around inline blocks without layout jumps.

## 2. Lists & Nesting

Markdown isn't complete without lists. And lists inside lists. And quotes inside lists!

*   **Fruit**
    *   Apple
    *   Banana
        *   Cavendish
        *   Plantain
*   **Vegetables**
    1.  Carrot
    2.  Broccoli

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

## 5. Media & Links

Links are fully clickable and interactive: [Visit the Flutter website](https://flutter.dev).

Images are responsive and support border radiuses based on your specific `MarkdownThemeData`.

![Spectacular mountain landscape](https://picsum.photos/id/1011/960/400)

## 6. The Edge Cases

Finally, testing seamless text selection bridging an empty paragraph line to a dense block of text!

Line one.

Line two.

```python
def test_edge_case():
    # Notice the selection corners on the empty lines below:
    
    
    print("Empty lines inside code blocks shouldn't break corner heuristics!")
```

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
      ..attachDocument(_controller.document)
      ..addListener(_handleSelectionChanged);
    _editorController = TextEditingController(text: _initialMarkdown)
      ..addListener(_handleEditorChanged);
  }

  @override
  void dispose() {
    _editorController
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _selectionController
      ..removeListener(_handleSelectionChanged)
      ..dispose();
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
          IconButton(
            tooltip: 'Copy selected model text',
            onPressed: _selectionController.hasSelection
                ? _copySelectedModelText
                : null,
            icon: const Icon(Icons.content_copy_outlined),
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
            subtitle: _previewSubtitle(),
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

  void _handleSelectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

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
            color: colorScheme.shadow.withOpacity(0.05),
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
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

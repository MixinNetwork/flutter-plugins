import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

enum _DemoThemePreset {
  ocean,
  warm,
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

  static const _initialMarkdown = '''
# mixin_markdown_widget

This example lets you **edit Markdown on the left** and inspect the live preview on the right.

> The current version focuses on a strong reading surface first: theming, tables, code blocks, images, and controller-driven updates.

## How to use this demo

1. Edit the source in the left editor.
2. Watch the preview update immediately.
3. Use the theme button in the app bar to switch the reading surface.
4. Use the append action to simulate streamed output.

## Included blocks

- Headings and paragraphs
- Block quotes and lists
- Fenced code blocks
- Tables
- Images
- Horizontal rules

## Sample code

```dart
final controller = MarkdownController(data: '# Hello');
controller.appendChunk('\n\nNew data streamed in.');
```

## Sample table

| Capability | Status |
| --- | --- |
| Theme data | Ready |
| Stream append | Ready |
| Incremental parser | Planned |

---

![Demo image](https://picsum.photos/960/360)

Visit [GitHub](https://github.com/MixinNetwork/flutter-plugins) for the monorepo.
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
    final baseTheme = MarkdownThemeData.fallback(context);
    final markdownTheme = _themePreset == _DemoThemePreset.warm
        ? baseTheme.copyWith(
            maxContentWidth: 860,
            bodyStyle: baseTheme.bodyStyle.copyWith(height: 1.8),
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
                child: Text('Ocean theme'),
              ),
              PopupMenuItem<_DemoThemePreset>(
                value: _DemoThemePreset.warm,
                child: Text('Warm theme'),
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
                    height: 1.55,
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

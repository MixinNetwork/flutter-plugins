import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

class CompositeSelectionDemoPage extends StatefulWidget {
  const CompositeSelectionDemoPage({super.key});

  @override
  State<CompositeSelectionDemoPage> createState() =>
      _CompositeSelectionDemoPageState();
}

class _CompositeSelectionDemoPageState
    extends State<CompositeSelectionDemoPage> {
  final MarkdownSelectionController _selectionController =
      MarkdownSelectionController();
  final ScrollController _scrollController = ScrollController();

  static const _openingMarkdown = '''
## AI reply assembled from multiple widgets

I found the relevant context in the conversation history. The answer is split into Markdown chunks, with tool-call widgets rendered between them.
''';

  static const _middleMarkdown = '''
The retrieval result points to a product decision rather than a rendering bug:

- AI replies can contain multiple Markdown fragments.
- Tool-call output is rendered by the host app.
- Users still expect one continuous drag selection.
''';

  static const _closingMarkdown = '''
### Summary

`MixinSelectionArea` owns one composite selection document. Nested `MarkdownWidget` instances and custom widgets opt into the same model, so copy and drag selection can cross widget boundaries.
''';

  static const _gitStatusOutput = '''
```console
\$ git status --short

 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
 M packages/mixin_markdown_widget/example/lib/composite_selection_demo.dart
```
''';

  static const _analyzeOutput = '''
```console
\$ flutter analyze example/lib/composite_selection_demo.dart

Analyzing composite_selection_demo.dart...
No issues found! (ran in 1.3s)
```
''';

  @override
  void dispose() {
    _selectionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectAll() {
    _selectionController.selectAll();
  }

  void _copySelected() {
    _selectionController.copySelectionToClipboard();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied selected composite text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final markdownTheme = MarkdownThemeData.fallback(context).copyWith(
      padding: EdgeInsets.zero,
      maxContentWidth: double.infinity,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Composite Selection Demo'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Select all composite text',
            onPressed: _selectAll,
            icon: const Icon(Icons.select_all_rounded),
          ),
          AnimatedBuilder(
            animation: _selectionController,
            builder: (context, _) => IconButton(
              tooltip: 'Copy selected composite text',
              onPressed:
                  _selectionController.hasSelection ? _copySelected : null,
              icon: const Icon(Icons.content_copy_outlined),
            ),
          ),
        ],
      ),
      body: MixinSelectionArea(
        controller: _selectionController,
        scrollController: _scrollController,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.view_stream_outlined,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Markdown + tool calls in one selection scope',
                            style: textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _selectionController,
                      builder: (context, _) {
                        final selectedLength =
                            _selectionController.selectedPlainText.length;
                        return Text(
                          selectedLength == 0
                              ? 'Selection: none'
                              : 'Selection: $selectedLength chars',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: MarkdownTheme(
                          data: markdownTheme,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const <Widget>[
                              MarkdownWidget(
                                data: _openingMarkdown,
                                useColumn: true,
                              ),
                              SizedBox(height: 14),
                              _ToolCallBlock(
                                id: 'git-status',
                                summary:
                                    'Explored 2 files, searched once, ran 1 command',
                                command: 'git status --short',
                                resultMarkdown: _gitStatusOutput,
                              ),
                              SizedBox(height: 14),
                              MarkdownWidget(
                                data: _middleMarkdown,
                                useColumn: true,
                              ),
                              SizedBox(height: 14),
                              _ToolCallBlock(
                                id: 'flutter-analyze',
                                summary:
                                    'Read 1 file, resolved dependencies, ran 1 command',
                                command:
                                    'flutter analyze example/lib/composite_selection_demo.dart',
                                resultMarkdown: _analyzeOutput,
                              ),
                              SizedBox(height: 14),
                              _LineWithTwoSelectable(),
                              MarkdownWidget(
                                data: _closingMarkdown,
                                useColumn: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineWithTwoSelectable extends StatelessWidget {
  const _LineWithTwoSelectable();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: MixinSelectableRow(
            selectionId: 'line-with-two-selectable',
            spacing: 6,
            children: const <Widget>[
              MixinSelectableText(
                'left',
              ),
              Icon(Icons.arrow_forward_rounded, size: 16),
              MixinSelectableText(
                'right',
              ),
            ],
          ),
        ));
  }
}

class _ToolCallBlock extends StatefulWidget {
  const _ToolCallBlock({
    required this.id,
    required this.summary,
    required this.command,
    required this.resultMarkdown,
  });

  final String id;
  final String summary;
  final String command;
  final String resultMarkdown;

  @override
  State<_ToolCallBlock> createState() => _ToolCallBlockState();
}

class _ToolCallBlockState extends State<_ToolCallBlock>
    with TickerProviderStateMixin {
  bool _isToolCallExpanded = false;
  bool _isCommandExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => setState(
                () => _isToolCallExpanded = !_isToolCallExpanded,
              ),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.travel_explore_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MixinSelectableText(
                        widget.summary,
                        selectionId: '${widget.id}-summary',
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isToolCallExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _isToolCallExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.72),
                          border: Border.all(
                            color: colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              InkWell(
                                onTap: () => setState(
                                  () =>
                                      _isCommandExpanded = !_isCommandExpanded,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.terminal_rounded,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: MixinSelectableText(
                                          'Ran ${widget.command}',
                                          selectionId: '${widget.id}-command',
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      AnimatedRotation(
                                        turns: _isCommandExpanded ? 0.5 : 0,
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: Icon(
                                          Icons.expand_more_rounded,
                                          size: 20,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: _isCommandExpanded
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: 10,
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxHeight: 200,
                                            ),
                                            child: MarkdownWidget(
                                              data: widget.resultMarkdown,
                                              shrinkWrap: true,
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

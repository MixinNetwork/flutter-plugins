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

I found the relevant context in the conversation history. The answer is split
into Markdown chunks, with tool-call widgets rendered between them.
''';

  static const _middleMarkdown = '''
The retrieval result points to a product decision rather than a rendering bug:

- AI replies can contain multiple Markdown fragments.
- Tool-call output is rendered by the host app.
- Users still expect one continuous drag selection.
''';

  static const _closingMarkdown = '''
### Summary

`MixinSelectionArea` owns one composite selection document. Nested
`MarkdownWidget` instances and custom widgets opt into the same model, so copy
and drag selection can cross widget boundaries.
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
                                name: 'search_messages',
                                summary:
                                    'Query: selection scope AI markdown tool calls',
                                result:
                                    'Matched 3 messages across the current chat.',
                              ),
                              SizedBox(height: 14),
                              MarkdownWidget(
                                data: _middleMarkdown,
                                useColumn: true,
                              ),
                              SizedBox(height: 14),
                              _ToolCallBlock(
                                name: 'read_message_context',
                                summary:
                                    'Conversation: engineering notes and prototype feedback',
                                result:
                                    'Returned 5 neighboring messages around the selected hit.',
                              ),
                              SizedBox(height: 14),
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

class _ToolCallBlock extends StatelessWidget {
  const _ToolCallBlock({
    required this.name,
    required this.summary,
    required this.result,
  });

  final String name;
  final String summary;
  final String result;

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
            Row(
              children: <Widget>[
                Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MixinSelectableText(
                    'Tool call: $name',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            MixinSelectableText(
              summary,
              selectionId: '$name-summary',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            MixinSelectableText(
              result,
              selectionId: '$name-result',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'Menlo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

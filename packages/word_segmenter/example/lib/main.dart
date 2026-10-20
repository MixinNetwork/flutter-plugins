import 'package:flutter/material.dart';
import 'package:word_segmenter/word_segmenter.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController(text: '我们今天讨论一下流式输出的性能问题。');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final ranges = wordBoundaries(text);
    return Scaffold(
      appBar: AppBar(title: const Text('Word Segmenter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            maxLines: null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (ranges == null)
            const Text('No word segmenter on this platform.')
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final range in ranges)
                  Chip(label: Text(range.textInside(text))),
              ],
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:string_tokenizer/string_tokenizer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _controller = TextEditingController();
  final _outputs = <String>[];

  @override
  void initState() {
    super.initState();
    _controller.text = '北京欢迎你';
  }

  @override
  Widget build(BuildContext context) {
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  maxLines: 7,
                ),
                spacerSmall,
                TextButton(
                  onPressed: () {
                    final tokens = tokenize(
                      _controller.text,
                      options: [TokenizerUnit.word],
                    );
                    debugPrint('tokens: $tokens');
                    setState(() {
                      _outputs.clear();
                      _outputs.addAll(tokens);
                    });
                  },
                  child: const Text('tokenizer'),
                ),
                spacerSmall,
                if (_outputs.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 8,
                    children: _outputs.map((e) => Text(e)).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

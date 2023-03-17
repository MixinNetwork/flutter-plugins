import 'package:flutter/material.dart';
import 'package:string_tokenizer/string_tokenizer.dart';

void main() {
  runApp(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _outputs = <String>[];

  final _options = <TokenizerUnit>[TokenizerUnit.word];

  @override
  void initState() {
    super.initState();
    _controller.text = '北京欢迎你';
  }

  @override
  Widget build(BuildContext context) {
    const spacerSmall = SizedBox(height: 10);
    return Scaffold(
      appBar: AppBar(
        title: const Text('String Tokenizer'),
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
              Wrap(
                runSpacing: 4,
                spacing: 4,
                children: [
                  for (final unit in TokenizerUnit.values)
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: ChoiceChip(
                        label: Text(unit.name),
                        selected: _options.contains(unit),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _options.add(unit);
                            } else {
                              _options.remove(unit);
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
              spacerSmall,
              TextButton(
                onPressed: () {
                  final tokens = tokenize(
                    _controller.text,
                    options: _options,
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
                  spacing: 8,
                  runSpacing: 4,
                  children: _outputs.map((e) => Text(e)).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

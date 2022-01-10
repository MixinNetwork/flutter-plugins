import 'package:flutter/material.dart';
import 'package:flutter_multi_window/flutter_multi_window.dart';

void main() {
  runApp(const _ExampleApp());
}

class _ExampleApp extends StatefulWidget {
  const _ExampleApp({Key? key}) : super(key: key);

  @override
  State<_ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<_ExampleApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: TextButton(
            onPressed: () async {
              final window = await FlutterMultiWindow.createWindow();
              window
                ..setSize(const Size(1280, 720))
                ..center()
                ..setTitle('Another window')
                ..show();
            },
            child: const Text('Create a new World!'),
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_window/flutter_multi_window.dart';

void main(List<String> args) {
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args[2].isEmpty
        ? const {}
        : jsonDecode(args[2]) as Map<String, dynamic>;
    runApp(_ExampleSubWindow(
      windowController: WindowController.fromWindowId(windowId),
      args: argument,
    ));
  } else {
    runApp(const _ExampleMainWindow());
  }
}

class _ExampleMainWindow extends StatefulWidget {
  const _ExampleMainWindow({Key? key}) : super(key: key);

  @override
  State<_ExampleMainWindow> createState() => _ExampleMainWindowState();
}

class _ExampleMainWindowState extends State<_ExampleMainWindow> {
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
              final window = await FlutterMultiWindow.createWindow(jsonEncode({
                'args1': 'Sub window',
                'args2': 100,
                'args3': true,
                'bussiness': 'bussiness_test',
              }));
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

class _ExampleSubWindow extends StatelessWidget {
  const _ExampleSubWindow({
    Key? key,
    required this.windowController,
    required this.args,
  }) : super(key: key);

  final WindowController windowController;
  final Map? args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: [
              if (args != null)
                Text(
                  'Arguments: ${args.toString()}',
                  style: const TextStyle(fontSize: 20),
                ),
              TextButton(
                onPressed: () async {
                  windowController.close();
                },
                child: const Text('Close this window'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

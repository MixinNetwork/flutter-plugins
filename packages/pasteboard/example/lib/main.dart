import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _console = "";

  Uint8List? bytes;
  String? fileUrl;

  final textController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

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
              TextField(
                controller: textController,
                maxLines: 10,
              ),
              MaterialButton(
                onPressed: () async {
                  final lines =
                      const LineSplitter().convert(textController.text);
                  await Pasteboard.writeFiles(lines);
                },
                child: const Text('copy'),
              ),
              MaterialButton(
                onPressed: () async {
                  final bytes = await Pasteboard.image;

                  setState(() {
                    fileUrl = null;
                    this.bytes = bytes;
                    _console = "bytes: ${bytes?.length}";
                  });
                },
                child: const Text('paste image'),
              ),
              TextButton(
                onPressed: () async {
                  final files = await Pasteboard.files();
                  setState(() {
                    _console = 'files: \n ${files.isEmpty ? 'empty' : ''}';
                    for (final file in files) {
                      _console += '$file ${File(file).existsSync()}\n';
                    }
                  });
                },
                child: const Text("Get files"),
              ),
              SelectableText(' $_console'),
              if (bytes != null) Image.memory(bytes!),
              if (fileUrl != null) Image.file(File(fileUrl!))
            ],
          ),
        ),
      ),
    );
  }
}

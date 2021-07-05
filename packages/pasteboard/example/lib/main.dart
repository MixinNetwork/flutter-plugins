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
  Uint8List? bytes;
  String? fileUrl;

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
              MaterialButton(
                onPressed: () async {
                  await Pasteboard.writeUrl(
                      'file:///Users/YeungKC/Desktop/foo.png');
                },
                child: const Text('copy'),
              ),
              MaterialButton(
                onPressed: () async {
                  final url = await Pasteboard.absoluteUrlString;
                  if (url?.startsWith('file') ?? false) {
                    var tryParse = Uri.tryParse(url!);
                    return setState(() {
                      fileUrl = tryParse!.toFilePath();
                      this.bytes = null;
                    });
                  }

                  final bytes = await Pasteboard.image;

                  setState(() {
                    fileUrl = null;
                    this.bytes = bytes;
                  });
                },
                child: const Text('paste image'),
              ),
              Text('bytes: $bytes', maxLines: 1),
              Text('fileUrl: $fileUrl', maxLines: 1),
              if (bytes != null) Image.memory(bytes!),
              if (fileUrl != null) Image.file(File(fileUrl!))
            ],
          ),
        ),
      ),
    );
  }
}

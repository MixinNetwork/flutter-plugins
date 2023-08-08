import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final path = p.join(Directory.systemTemp.path, 'mixin_logger_test');
  await initLogger(path);
  debugPrint('log path: $path');
  i('test');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Center(
                child: TextButton(
              onPressed: () {
                i('test log: ${DateTime.now()}');
              },
              child: const Text('log'),
            )),
          ),
        ),
      ),
    );
  }
}

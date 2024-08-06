import 'dart:ffi';

import 'package:breakpad_client/breakpad_client.dart' as breakpad_client;
import 'package:flutter/material.dart';

void main() {
  breakpad_client.init_exception_handle("/tmp/crash/");
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
        body: Center(
          child: ElevatedButton(
            child: const Text("crash"),
            onPressed: () {
              final pointer = Pointer.fromAddress(0);
              pointer.cast<Char>().value = 1;
            },
          ),
        ),
      ),
    );
  }
}

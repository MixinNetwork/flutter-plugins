import 'dart:async';

import 'package:bring_window_to_front/bring_window_to_front.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: TextButton(
            child: const Text('delay 2s to bring front'),
            onPressed: () async {
              await Future<void>.delayed(const Duration(seconds: 2));
              bringWindowToFront();
            },
          ),
        ),
      ),
    );
  }
}

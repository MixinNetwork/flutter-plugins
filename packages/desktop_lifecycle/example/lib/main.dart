import 'package:desktop_lifecycle/desktop_lifecycle.dart';
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
        body: const Column(
          children: [
            FocusLifecycleState(),
          ],
        ),
      ),
    );
  }
}

class FocusLifecycleState extends StatelessWidget {
  const FocusLifecycleState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: DesktopLifecycle.instance.isActive,
        builder: (context, child) {
          final active = DesktopLifecycle.instance.isActive.value;
          return Text('active: ${active ? "active" : "inactive"}');
        });
  }
}

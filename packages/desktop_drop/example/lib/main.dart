import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<Uri> _list = [];

  bool _dragging = false;

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
          child: DropTarget(
            onDragDone: (urls) {
              setState(() {
                _list.addAll(urls);
              });
            },
            onDragEntered: () {
              setState(() {
                _dragging = true;
              });
            },
            onDragExited: () {
              setState(() {
                _dragging = false;
              });
            },
            child: Container(
              height: 200,
              width: 200,
              color: _dragging ? Colors.blue.withOpacity(0.4) : Colors.black26,
              child: _list.isEmpty
                  ? const Center(child: Text("Drop here"))
                  : Text(_list.join("\n")),
            ),
          ),
        ),
      ),
    );
  }
}

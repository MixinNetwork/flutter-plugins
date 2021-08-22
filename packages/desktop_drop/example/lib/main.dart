import 'package:desktop_drop/desktop_drop.dart';
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
        body: Wrap(
          direction: Axis.horizontal,
          runSpacing: 8,
          spacing: 8,
          children: const [
            ExmapleDragTarget(),
            ExmapleDragTarget(),
            ExmapleDragTarget(),
            ExmapleDragTarget(),
            ExmapleDragTarget(),
            ExmapleDragTarget(),
          ],
        ),
      ),
    );
  }
}

class ExmapleDragTarget extends StatefulWidget {
  const ExmapleDragTarget({Key? key}) : super(key: key);

  @override
  _ExmapleDragTargetState createState() => _ExmapleDragTargetState();
}

class _ExmapleDragTargetState extends State<ExmapleDragTarget> {
  final List<Uri> _list = [];

  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
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
    );
  }
}

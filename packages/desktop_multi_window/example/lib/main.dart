import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:desktop_lifecycle/desktop_lifecycle.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_window_example/event_widget.dart';

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
        body: Column(
          children: [
            TextButton(
              onPressed: () async {
                final window =
                    await DesktopMultiWindow.createWindow(jsonEncode({
                  'args1': 'Sub window',
                  'args2': 100,
                  'args3': true,
                  'business': 'business_test',
                }));
                window
                  ..setFrame(const Offset(0, 0) & const Size(1280, 720))
                  ..center()
                  ..setTitle('Another window')
                  ..resizable(false)
                  ..show();
              },
              child: const Text('Create a new World!'),
            ),
            TextButton(
              child: const Text('Send event to all sub windows'),
              onPressed: () async {
                final subWindowIds =
                    await DesktopMultiWindow.getAllSubWindowIds();
                for (final windowId in subWindowIds) {
                  DesktopMultiWindow.invokeMethod(
                    windowId,
                    'broadcast',
                    'Broadcast from main window',
                  );
                }
              },
            ),
            Expanded(
              child: EventWidget(controller: WindowController.fromWindowId(0)),
            )
          ],
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
        body: Column(
          children: [
            if (args != null)
              Text(
                'Arguments: ${args.toString()}',
                style: const TextStyle(fontSize: 20),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: DesktopLifecycle.instance.isActive,
              builder: (context, active, child) {
                if (active) {
                  return const Text('Window Active');
                } else {
                  return const Text('Window Inactive');
                }
              },
            ),
            TextButton(
              onPressed: () async {
                windowController.close();
              },
              child: const Text('Close this window'),
            ),
            Expanded(child: EventWidget(controller: windowController)),
          ],
        ),
      ),
    );
  }
}

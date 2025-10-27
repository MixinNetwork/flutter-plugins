import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_window_example/extensions/window_controller.dart';
import 'package:mixin_logger/mixin_logger.dart';

import '../windows/argumet.dart';

class WindowList extends StatefulWidget {
  const WindowList({super.key});

  @override
  State<WindowList> createState() => _WindowListState();
}

class _WindowListState extends State<WindowList> {
  var _controllers = <WindowController>[];
  var _windowArguments = <WindowArguments>[];

  StreamSubscription<void>? _windowsChangedSubscription;

  @override
  void initState() {
    super.initState();
    _refreshWindows();
    _windowsChangedSubscription = onWindowsChanged.listen((_) {
      i('Windows changed event received1');
      _refreshWindows();
    });
  }

  @override
  void dispose() {
    _windowsChangedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshWindows() async {
    _controllers = await WindowController.getAll();
    setState(() {
      _windowArguments = _controllers
          .map((e) => WindowArguments.fromArguments(e.arguments))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: _refreshWindows,
          child: const Text('Refresh Windows'),
        ),
        for (var i = 0; i < _controllers.length; i++)
          ListTile(
              title: Text('Window ID: ${_controllers[i].windowId}'),
              subtitle: Text('Arguments: ${_windowArguments[i]}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      onPressed: () {
                        _controllers[i].center();
                      },
                      icon: const Icon(Icons.center_focus_strong)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await _controllers[i].close();
                    },
                  ),
                ],
              )),
      ],
    );
  }
}

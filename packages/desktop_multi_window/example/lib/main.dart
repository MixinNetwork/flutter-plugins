import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_lifecycle/desktop_lifecycle.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_multi_window_example/event_widget.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args[2].isEmpty ? const {} : jsonDecode(args[2]) as Map<String, dynamic>;
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

class _ExampleMainWindowState extends State<_ExampleMainWindow> with WindowEvents {
  TextEditingController xPositionController = TextEditingController();
  TextEditingController yPositionController = TextEditingController();
  TextEditingController widthController = TextEditingController();
  TextEditingController heightController = TextEditingController();

  int? _selectedWindowId;
  List<int> _windowIds = [];

  Offset _position = const Offset(0, 0);
  Size _size = const Size(0, 0);

  late final AppLifecycleListener? _appLifecycleListener;

  @override
  void initState() {
    if (Platform.isMacOS) {
      _appLifecycleListener = AppLifecycleListener(onStateChange: _handleStateChange);
    }
    super.initState();
    WindowController.main().addListener(this);
    _updateWindowIds();
  }

  void _handleStateChange(AppLifecycleState state) {
    // workaround applies for all sub-windows
    if (Platform.isMacOS && state == AppLifecycleState.hidden) {
      SchedulerBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      _appLifecycleListener?.dispose();
    }
    super.dispose();
    WindowController.main().removeListener(this);
  }

  Future<void> _updateWindowIds() async {
    // Get all sub-window IDs
    final List<int> subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
    setState(() {
      _windowIds = subWindowIds;
      if (_windowIds.isNotEmpty) {
        _selectedWindowId ??= _windowIds.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // final options = WindowOptions(
    //   macos: MacOSWindowOptions.nspanel(
    //     title: 'Sub Window',
    //     backgroundColor: Colors.transparent,
    //     level: MacOSWindowLevel.floating,
    //     styleMask: {MacOSWindowStyleMask.borderless, MacOSWindowStyleMask.nonactivatingPanel, MacOSWindowStyleMask.utility},
    //     isOpaque: false,
    //     hasShadow: false,
    //   ),
    // );

    final options = WindowOptions(
      macos: MacOSWindowOptions.nswindow(
        title: 'Sub Window',
        backgroundColor: Colors.transparent,
        level: MacOSWindowLevel.floating,
        isOpaque: false,
        hasShadow: false,
      ),
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final window = await DesktopMultiWindow.createWindow(
                    jsonEncode({
                      'args1': 'Sub window',
                      'args2': 100,
                      'args3': true,
                      'business': 'business_test',
                    }),
                    options,
                  );
                  window
                    ..setFrame(const Offset(0, 0) & const Size(1280, 720))
                    ..center()
                    ..setTitle('Another window')
                    ..show();
                  _updateWindowIds();
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Window'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            TextButton(
              child: const Text('Send event to all sub windows'),
              onPressed: () async {
                final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
                for (final windowId in subWindowIds) {
                  DesktopMultiWindow.invokeMethod(
                    windowId,
                    'broadcast',
                    'Broadcast from main window',
                  );
                }
              },
            ),
            TextButton(
              onPressed: () async {
                await WindowController.main().hide();
              },
              child: const Text('Hide this window'),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Window: '),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: DropdownButton<int>(
                      value: _selectedWindowId,
                      items: _windowIds.map((int id) {
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(id == 0 ? 'Main Window' : 'Window $id'),
                        );
                      }).toList(),
                      onTap: () {
                        // Update window list before showing dropdown
                        _updateWindowIds();
                      },
                      onChanged: (int? newValue) {
                        setState(() {
                          _selectedWindowId = newValue;
                        });
                      },
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (_selectedWindowId != null) {
                        await WindowController.fromWindowId(_selectedWindowId!).show();
                      }
                    },
                    child: const Text('Show this window'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              width: 400,
              child: Row(
                children: [
                  Row(
                    children: [
                      Text('X: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: xPositionController),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Y: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: yPositionController),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Width: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: widthController),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Height: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: heightController),
                      ),
                    ],
                  ),
                  TextButton(
                      onPressed: () async {
                        final position = Offset(double.parse(xPositionController.text), double.parse(yPositionController.text));
                        final size = Size(double.parse(widthController.text), double.parse(heightController.text));
                        await WindowController.main().setFrame(position & size);
                        setState(() {
                          _position = position;
                          _size = size;
                        });
                      },
                      child: const Text('Set frame')),
                ],
              ),
            ),
            Text('Position: $_position'),
            Text('Size: $_size'),
            Expanded(
              child: EventWidget(controller: WindowController.fromWindowId(0)),
            )
          ],
        ),
      ),
    );
  }

  @override
  void onWindowMove() {
    WindowController.main().getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
  }

  @override
  void onWindowMoved() {
    WindowController.main().getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
  }

  @override
  void onWindowResize() {
    WindowController.main().getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }

  @override
  void onWindowResized() {
    WindowController.main().getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }
}

class _ExampleSubWindow extends StatefulWidget {
  const _ExampleSubWindow({
    Key? key,
    required this.windowController,
    required this.args,
  }) : super(key: key);

  final WindowController windowController;
  final Map? args;

  @override
  State<_ExampleSubWindow> createState() => _ExampleSubWindowState();
}

class _ExampleSubWindowState extends State<_ExampleSubWindow> with WindowEvents {
  TextEditingController xPositionController = TextEditingController();
  TextEditingController yPositionController = TextEditingController();
  TextEditingController widthController = TextEditingController();
  TextEditingController heightController = TextEditingController();
  Offset _position = const Offset(0, 0);
  Size _size = const Size(0, 0);

  late final AppLifecycleListener? _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _appLifecycleListener = AppLifecycleListener(onStateChange: _handleStateChange);
    }
    widget.windowController.addListener(this);
  }

  void _handleStateChange(AppLifecycleState state) {
    // workaround applies for all sub-windows
    if (Platform.isMacOS && state == AppLifecycleState.hidden) {
      SchedulerBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      _appLifecycleListener?.dispose();
    }
    super.dispose();
    widget.windowController.removeListener(this);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            if (widget.args != null)
              Text(
                'Arguments: ${widget.args.toString()}',
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
                widget.windowController.close();
              },
              child: const Text('Close this window'),
            ),
            TextButton(
              onPressed: () async {
                widget.windowController.hide();
              },
              child: const Text('Hide this window'),
            ),
            TextButton(
              onPressed: () async {
                await WindowController.main().show();
              },
              child: const Text('Show main window'),
            ),
            SizedBox(
              height: 40,
              width: 400,
              child: Row(
                children: [
                  Row(
                    children: [
                      Text('X: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: xPositionController),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Y: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: yPositionController),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Width: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: widthController),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Height: '),
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: TextField(controller: heightController),
                      ),
                    ],
                  ),
                  TextButton(
                      onPressed: () async {
                        final position = Offset(double.parse(xPositionController.text), double.parse(yPositionController.text));
                        final size = Size(double.parse(widthController.text), double.parse(heightController.text));
                        await widget.windowController.setFrame(position & size);
                        setState(() {
                          _position = position;
                          _size = size;
                        });
                      },
                      child: const Text('Set frame')),
                ],
              ),
            ),
            Text('Position: $_position'),
            Text('Size: $_size'),
            Expanded(child: EventWidget(controller: widget.windowController)),
          ],
        ),
      ),
    );
  }

  @override
  void onWindowMove() {
    widget.windowController.getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
  }

  @override
  void onWindowMoved() {
    widget.windowController.getPosition().then((position) {
      setState(() {
        _position = position;
      });
    });
  }

  @override
  void onWindowResize() {
    widget.windowController.getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }

  @override
  void onWindowResized() {
    widget.windowController.getSize().then((size) {
      setState(() {
        _size = size;
      });
    });
  }
}

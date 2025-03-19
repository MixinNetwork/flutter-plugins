import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_lifecycle/desktop_lifecycle.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_multi_window_example/event_widget.dart';

import 'window_events_widget.dart';

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

class _ExampleMainWindowState extends State<_ExampleMainWindow> {
  int? _selectedWindowId;
  List<int> _windowIds = [];

  late final AppLifecycleListener? _appLifecycleListener;

  @override
  void initState() {
    if (Platform.isMacOS) {
      _appLifecycleListener = AppLifecycleListener(onStateChange: _handleStateChange);
    }
    super.initState();
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
        level: MacOsWindowLevel.floating,
        isOpaque: false,
        hasShadow: false,
      ),
      windows: const WindowsWindowOptions(
        style: WindowsWindowStyle.WS_OVERLAPPEDWINDOW,
        exStyle: WindowsExtendedWindowStyle.WS_EX_APPWINDOW,
        width: 1280,
        height: 720,
        backgroundColor: Colors.transparent,
      ),
    );

    return MaterialApp(
      color: Colors.transparent,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Row(
              children: [
                WindowEventsWidget(controller: WindowController.main()),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
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
                          await _updateWindowIds();
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      child: ElevatedButton.icon(
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
                        icon: const Icon(Icons.send),
                        label: const Text('Send event to all sub windows'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Window: '),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: DropdownButton<int>(
                              value: _windowIds.contains(_selectedWindowId) ? _selectedWindowId : null,
                              items: _windowIds.map((int id) {
                                return DropdownMenuItem<int>(
                                  value: id,
                                  child: Text(id == 0 ? 'Main Window' : 'Window $id'),
                                );
                              }).toList(),
                              onTap: () async {
                                // Update window list before showing dropdown
                                await _updateWindowIds();
                              },
                              onChanged: (int? newValue) {
                                if (newValue == null) {
                                  return;
                                }
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
                  ],
                ),
              ],
            ),
            Expanded(
              child: EventWidget(controller: WindowController.main()),
            )
          ],
        ),
      ),
    );
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

class _ExampleSubWindowState extends State<_ExampleSubWindow> {
  late final AppLifecycleListener? _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _appLifecycleListener = AppLifecycleListener(onStateChange: _handleStateChange);
    }
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
                await WindowController.main().show();
              },
              child: const Text('Show main window'),
            ),
            WindowEventsWidget(controller: widget.windowController),
            Expanded(child: EventWidget(controller: widget.windowController)),
          ],
        ),
      ),
    );
  }
}

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_window_example/extensions/window_controller.dart';
import 'package:mixin_logger/mixin_logger.dart';

import '../widgets/window_list.dart';
import 'argumet.dart';

class ExampleMainWindow extends StatefulWidget {
  const ExampleMainWindow({Key? key}) : super(key: key);

  @override
  State<ExampleMainWindow> createState() => _ExampleMainWindowState();
}

class _ExampleMainWindowState extends State<ExampleMainWindow> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app'), actions: const [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(),
          ),
        ]),
        body: SingleChildScrollView(
          child: Column(
            children: [
              TextButton(
                onPressed: () async {
                  final controller = await WindowController.create(
                    WindowConfiguration(
                      hiddenAtLaunch: true,
                      arguments: const VideoPlayerWindowArguments(
                        videoUrl: '',
                      ).toArguments(),
                    ),
                  );
                  d(
                    'Created video player window: ${controller.windowId} ${controller.arguments}',
                  );
                },
                child: const Text('Launch video player window'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      // check existing windows
                      final controllers = WindowController.getAll();
                      for (var controller in await controllers) {
                        final args =
                            WindowArguments.fromArguments(controller.arguments);
                        if (args.businessId ==
                            WindowArguments.businessIdSample) {
                          await controller.center();
                          await controller.show();
                          return;
                        }
                      }

                      final controller = await WindowController.create(
                        WindowConfiguration(
                          hiddenAtLaunch: true,
                          arguments:
                              const SampleWindowArguments().toArguments(),
                        ),
                      );
                      d(
                        'Created sample window: ${controller.windowId} ${controller.arguments}',
                      );
                    },
                    child: const Text('Sample window (single instance)'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final controller = await WindowController.create(
                        WindowConfiguration(
                          hiddenAtLaunch: true,
                          arguments:
                              const SampleWindowArguments().toArguments(),
                        ),
                      );
                      d(
                        'Created sample window: ${controller.windowId} ${controller.arguments}',
                      );
                    },
                    child: const Text('Sample window (multi instance)'),
                  ),
                  TextButton(
                    onPressed: () async {
                      for (int i = 0; i < 15; i++) {
                        await WindowController.create(
                          WindowConfiguration(
                            hiddenAtLaunch: true,
                            arguments:
                                const SampleWindowArguments().toArguments(),
                          ),
                        );
                      }
                    },
                    child: const Text('Batch sample window'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final controllers = WindowController.getAll();
                      for (var controller in await controllers) {
                        final args =
                            WindowArguments.fromArguments(controller.arguments);
                        if (args.businessId ==
                            WindowArguments.businessIdSample) {
                          await controller.close();
                        }
                      }
                    },
                    child: const Text('Close all sample windows'),
                  ),
                ],
              ),
              TextButton(
                onPressed: () async {
                  const channel =
                      WindowMethodChannel('example_video_player_window');
                  channel.setMethodCallHandler((call) async {
                    d('Main window received method call: ${call.method} ${call.arguments}');
                  });
                  final result = await channel.invokeMethod('play');
                  d('Invoked play method on video player window, result: $result');
                },
                child: const Text('Play'),
              ),
              const WindowList(),
            ],
          ),
        ),
      ),
    );
  }
}

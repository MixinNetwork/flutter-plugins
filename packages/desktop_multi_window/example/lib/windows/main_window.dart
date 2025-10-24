import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
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
                      hiddenAtLaunch: false,
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
              TextButton(
                onPressed: () {
                  const channel =
                      WindowMethodChannel('example_video_player_window');
                  channel.invokeMethod('play');
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

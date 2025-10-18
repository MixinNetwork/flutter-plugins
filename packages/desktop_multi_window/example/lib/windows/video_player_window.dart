import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class VideoPlayerWindow extends StatelessWidget {
  const VideoPlayerWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Video Player Window')),
        body: Center(
          child: TextButton(
            onPressed: () {
              windowManager.center();
            },
            child: const Text('Center'),
          ),
        ),
      ),
    );
  }
}

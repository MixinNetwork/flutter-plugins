import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:window_manager/window_manager.dart';

import 'windows/argumet.dart';
import 'windows/main_window.dart';
import 'windows/video_player_window.dart';

Future<void> main(List<String> args) async {
  i('App started with arguments: $args');
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();
  final arguments = WindowArguments.fromArguments(windowController.arguments);
  i('Window arguments: $arguments');
  switch (arguments.businessId) {
    case WindowArguments.businessIdMain:
      runApp(const ExampleMainWindow());
    case WindowArguments.businessIdVideoPlayer:
      await windowManager.setTitle("Video Player");
      await windowManager.setSize(const Size(800, 600));
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.center();
      runApp(const VideoPlayerWindow());
  }
  await windowManager.show();
}

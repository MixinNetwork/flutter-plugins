import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:mixin_logger/mixin_logger.dart';
import 'package:window_manager/window_manager.dart';

import 'extensions/window_controller.dart';
import 'windows/argumet.dart';
import 'windows/main_window.dart';
import 'windows/sample_window.dart';
import 'windows/video_player_window.dart';
import 'package:fvp/fvp.dart' as fvp;

Future<void> main(List<String> args) async {
  i('App started with arguments: $args');
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final windowController = await WindowController.fromCurrentEngine();
  windowController.doCustomInitialize();
  final arguments = WindowArguments.fromArguments(windowController.arguments);
  i('Window arguments: $arguments');
  switch (arguments.businessId) {
    case WindowArguments.businessIdMain:
      runApp(const ExampleMainWindow());
    case WindowArguments.businessIdVideoPlayer:
      fvp.registerWith();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      runApp(const VideoPlayerWindow());

    case WindowArguments.businessIdSample:
      WindowOptions windowOptions = const WindowOptions(
        size: Size(600, 400),
        center: true,
        backgroundColor: Colors.transparent,
        windowButtonVisibility: false,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      runApp(const SampleWindow());
  }
}

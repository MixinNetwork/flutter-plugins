import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'demo_app.dart';
import 'demo_page_server.dart';
import 'demo_state.dart';
import 'demo_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = Platform.isWindows
      ? p.join((await getApplicationSupportDirectory()).path, 'webview_profile')
      : 'webview_window_WebView2';
  final state =
      DemoState(await DemoPageServer.start(), userDataFolder: profile);
  runWidget(ValueListenableBuilder<bool>(
    valueListenable: state.darkMode,
    child: DemoApp(state: state),
    builder: (context, dark, child) => WebviewWindowApp(
      titleBar: WebviewTitleBarConfiguration(
        height: 44,
        theme: state.theme,
        builder: (context, webview, navigation) => DemoTitleBar(
          webview: webview,
          state: navigation,
        ),
      ),
      child: child!,
    ),
  ));
}

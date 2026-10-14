import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'demo_app.dart';
import 'demo_page_server.dart';
import 'demo_state.dart';
import 'demo_title_bar.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Each titlebar starts this entrypoint in its own engine. Only the main app
  // should start the local server and own browser windows.
  if (runWebViewTitleBarWidget(args, builder: (_) => const DemoTitleBar())) {
    return;
  }
  final profile = Platform.isWindows
      ? p.join((await getApplicationSupportDirectory()).path, 'webview_profile')
      : 'webview_window_WebView2';
  runApp(DemoApp(
    state: DemoState(await DemoPageServer.start(), userDataFolder: profile),
  ));
}

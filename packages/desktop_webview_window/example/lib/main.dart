import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'demo_app.dart';
import 'demo_page_server.dart';
import 'demo_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = Platform.isWindows
      ? p.join((await getApplicationSupportDirectory()).path, 'webview_profile')
      : 'webview_window_WebView2';
  final state =
      DemoState(await DemoPageServer.start(), userDataFolder: profile);
  runApp(DemoApp(state: state));
}

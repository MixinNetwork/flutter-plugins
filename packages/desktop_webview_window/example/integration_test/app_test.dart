import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:integration_test/integration_test.dart';

import 'src/macos_shared_engine_scenarios.dart' as macos;
import 'src/windows_webview_scenarios.dart' as windows;

// One package entrypoint, including the dedicated macOS toolbar engine.
void main([List<String> args = const []]) {
  if (Platform.isMacOS &&
      runWebViewTitleBarWidget(
        args,
        builder: macos.buildSharedEngineTestToolbar,
      )) {
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    macos.registerSharedEngineTests();
  } else if (Platform.isWindows) {
    windows.registerWindowsWebviewTests();
  } else {
    throw UnsupportedError(
      'Native integration coverage requires macOS or Windows',
    );
  }
}

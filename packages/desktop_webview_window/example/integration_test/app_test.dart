import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:integration_test/integration_test.dart';

import 'src/macos_webview_scenarios.dart' as macos;
import 'src/test_title_bar.dart';
import 'src/windows_webview_scenarios.dart' as windows;

void main([List<String> args = const []]) {
  if (runWebViewTitleBarWidget(args, builder: (_) => const TestTitleBar())) {
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    macos.registerMacOSWebviewTests();
  } else if (Platform.isWindows) {
    windows.registerWindowsWebviewTests();
  } else {
    throw UnsupportedError(
        'No integration scenarios for ${Platform.operatingSystem}');
  }
}

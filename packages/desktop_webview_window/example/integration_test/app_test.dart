import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/macos_shared_engine_scenarios.dart' as macos;
import 'src/windows_webview_scenarios.dart' as windows;

// One entrypoint; all windows run on the test application's engine.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
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

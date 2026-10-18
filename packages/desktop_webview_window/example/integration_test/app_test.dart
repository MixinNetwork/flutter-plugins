import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'src/bridge_scenarios.dart' as bridge;
import 'src/background_scenarios.dart' as background;
import 'src/composer_scenarios.dart' as composer;
import 'src/windows_webview_scenarios.dart' as windows;

// One entrypoint for every platform.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  bridge.registerBridgeTests();
  background.registerBackgroundTests();
  // Every example runner installs the test composer.
  composer.registerComposerTests();
  if (Platform.isWindows) windows.registerWindowsWebviewTests();
}

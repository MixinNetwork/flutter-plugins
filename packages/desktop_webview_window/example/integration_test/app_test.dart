import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'src/bridge_scenarios.dart' as bridge;
import 'src/background_scenarios.dart' as background;
import 'src/composer_scenarios.dart' as composer;
import 'src/page_ui_scenarios.dart' as page_ui;
import 'src/windows_webview_scenarios.dart' as windows;
import 'src/regression_scenarios.dart' as regression;

// One entrypoint for every platform.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  if (const bool.fromEnvironment('DWW_ISSUE_RETEST')) {
    regression.registerRegressionTests();
    // Standalone release builds cannot use flutter test's debug connection.
    binding.allTestsPassed.future.then((passed) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      exit(passed ? 0 : 1);
    });
    return;
  }
  bridge.registerBridgeTests();
  background.registerBackgroundTests();
  page_ui.registerPageUiTests();
  // Every example runner installs the test composer.
  composer.registerComposerTests();
  regression.registerRegressionTests();
  if (Platform.isWindows) windows.registerWindowsWebviewTests();
}

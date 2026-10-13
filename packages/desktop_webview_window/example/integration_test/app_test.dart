import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/macos_shared_engine_scenarios.dart' as macos;
import 'src/windows_webview_scenarios.dart' as windows;
import 'src/title_bar_theme_scenarios.dart' as themes;

// One entrypoint; all windows run on the test application's engine.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Automated scenarios add/remove native views. Physical hover packets can
  // refer to an already removed view and crash LiveTestWidgetsFlutterBinding's
  // finder dispatcher. Synthetic tester input still runs normally.
  setUp(() => binding.deviceEventDispatcher = null);
  themes.registerTitleBarThemeTests();
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

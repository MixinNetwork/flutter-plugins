import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:integration_test/integration_test.dart';
import 'package:flutter/foundation.dart' show BindingBase;
import 'package:flutter_test/flutter_test.dart';

import 'src/macos_shared_engine_scenarios.dart' as macos;
import 'src/windows_webview_scenarios.dart' as windows;
import 'src/title_bar_theme_scenarios.dart' as themes;
import 'src/windowing_host_scenarios.dart' as windowing;

// Flutter's test dispatcher uses engine ID 1. Native SDK windowing requires
// the actual running engine; keep that distinction inside this test binding.
class _NativePlatformDispatcher extends TestPlatformDispatcher {
  _NativePlatformDispatcher()
      : super(platformDispatcher: PlatformDispatcher.instance);

  @override
  int? get engineId => PlatformDispatcher.instance.engineId;
}

class _NativeIntegrationBinding extends IntegrationTestWidgetsFlutterBinding {
  late final _dispatcher = _NativePlatformDispatcher();

  @override
  TestPlatformDispatcher get platformDispatcher => _dispatcher;
}

// One entrypoint; all windows run on the test application's engine.
void main() {
  final binding = BindingBase.debugBindingType() == null
      ? _NativeIntegrationBinding()
      : IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Automated scenarios add/remove native views. Physical hover packets can
  // refer to an already removed view and crash LiveTestWidgetsFlutterBinding's
  // finder dispatcher. Synthetic tester input still runs normally.
  setUp(() => binding.deviceEventDispatcher = null);
  if (!Platform.isLinux) themes.registerTitleBarThemeTests();
  windowing.registerWindowingHostTests();
  if (Platform.isMacOS) {
    macos.registerSharedEngineTests();
  } else if (Platform.isWindows) {
    windows.registerWindowsWebviewTests();
  } else if (!Platform.isLinux ||
      !const bool.fromEnvironment('WEBVIEW_TEST_WINDOWING')) {
    throw UnsupportedError(
      'Linux integration requires WEBVIEW_TEST_WINDOWING=true',
    );
  }
}

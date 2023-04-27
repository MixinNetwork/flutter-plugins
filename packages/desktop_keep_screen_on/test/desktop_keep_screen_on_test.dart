import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_keep_screen_on/desktop_keep_screen_on.dart';
import 'package:desktop_keep_screen_on/src/desktop_keep_screen_on_platform_interface.dart';
import 'package:desktop_keep_screen_on/src/desktop_keep_screen_on_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDesktopKeepScreenOnPlatform
    with MockPlatformInterfaceMixin
    implements DesktopKeepScreenOnPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DesktopKeepScreenOnPlatform initialPlatform = DesktopKeepScreenOnPlatform.instance;

  test('$MethodChannelDesktopKeepScreenOn is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDesktopKeepScreenOn>());
  });

  test('getPlatformVersion', () async {
    DesktopKeepScreenOn desktopKeepScreenOnPlugin = DesktopKeepScreenOn();
    MockDesktopKeepScreenOnPlatform fakePlatform = MockDesktopKeepScreenOnPlatform();
    DesktopKeepScreenOnPlatform.instance = fakePlatform;

    expect(await desktopKeepScreenOnPlugin.getPlatformVersion(), '42');
  });
}

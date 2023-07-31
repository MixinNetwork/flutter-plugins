import 'src/desktop_keep_screen_on_platform_interface.dart';

export 'src/desktop_keep_screen_on_linux.dart';

class DesktopKeepScreenOn {
  static Future<void> setPreventSleep(bool preventSleep) {
    return DesktopKeepScreenOnPlatform.instance.setPreventSleep(preventSleep);
  }
}

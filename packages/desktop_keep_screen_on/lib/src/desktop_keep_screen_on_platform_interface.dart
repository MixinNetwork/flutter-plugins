import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'desktop_keep_screen_on_method_channel.dart';

abstract class DesktopKeepScreenOnPlatform extends PlatformInterface {
  /// Constructs a DesktopKeepScreenOnPlatform.
  DesktopKeepScreenOnPlatform() : super(token: _token);

  static final Object _token = Object();

  static DesktopKeepScreenOnPlatform _instance =
      MethodChannelDesktopKeepScreenOn();

  /// The default instance of [DesktopKeepScreenOnPlatform] to use.
  ///
  /// Defaults to [MethodChannelDesktopKeepScreenOn].
  static DesktopKeepScreenOnPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DesktopKeepScreenOnPlatform] when
  /// they register themselves.
  static set instance(DesktopKeepScreenOnPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> setPreventSleep(bool preventSleep) {
    throw UnimplementedError('setPreventSleep() has not been implemented.');
  }
}

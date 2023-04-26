import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_keep_screen_on_platform_interface.dart';

/// An implementation of [DesktopKeepScreenOnPlatform] that uses method channels.
class MethodChannelDesktopKeepScreenOn extends DesktopKeepScreenOnPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('desktop_keep_screen_on');

  @override
  Future<void> setPreventSleep(bool preventSleep) {
    return methodChannel.invokeMethod<void>('setPreventSleep', preventSleep);
  }
}

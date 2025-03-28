import 'package:universal_platform/universal_platform.dart';

class Platform {
  static bool get isLinux => UniversalPlatform.isLinux;

  static bool get isWindows => UniversalPlatform.isWindows;

  static bool get isWeb => UniversalPlatform.isWeb;

  static bool get isAndroid => UniversalPlatform.isAndroid;
}

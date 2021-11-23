import 'dart:io' as io;

class Platform {
  static bool get isLinux => io.Platform.isLinux;

  static bool get isWindows => io.Platform.isWindows;

  static bool get isWeb => false;

  static bool get isAndroid => io.Platform.isAndroid;
}

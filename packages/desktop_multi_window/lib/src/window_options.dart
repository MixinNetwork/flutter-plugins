import 'macos/window_options.dart';
import 'windows/window_options.dart';

class WindowOptions {
  final WindowsWindowOptions windows;
  final MacOSWindowOptions macos;
  WindowOptions({this.windows = const WindowsWindowOptions(), this.macos = const MacOSWindowOptions()});

  Map<String, dynamic> toJson() {
    return {
      'windows': windows.toJson(),
      'macos': macos.toJson(),
    };
  }
}

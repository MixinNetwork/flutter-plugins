import 'windows/window_options.dart';

class WindowOptions {
  final WindowsWindowOptions windows;
  WindowOptions({this.windows = const WindowsWindowOptions()});

  Map<String, dynamic> toJson() {
    return {
      'windows': windows.toJson(),
    };
  }
}

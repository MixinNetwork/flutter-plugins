import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Darwin module carries the shared composer header unchanged', () {
    // SwiftPM and CocoaPods only see headers inside the Darwin source tree.
    final shared =
        File('src/include/desktop_webview_window/webview_window_composer.h');
    final darwin = File('macos/desktop_webview_window/Sources/'
        'desktop_webview_window_composer/include/webview_window_composer.h');
    expect(darwin.readAsStringSync(), shared.readAsStringSync());
  });
}

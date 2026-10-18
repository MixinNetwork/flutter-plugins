import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'src/browser_runtime.dart';
import 'src/create_configuration.dart';
import 'src/js_bridge.dart';
import 'src/webview.dart';
import 'src/webview_impl.dart';

export 'src/cookie.dart';
export 'src/create_configuration.dart';
export 'src/webview.dart';

class WebviewWindow {
  /// Check if WebView runtime is available on the current devices.
  static Future<bool> isWebviewAvailable() async {
    if (Platform.isWindows) {
      final ret = await attachTransport().invoke<bool>('isWebviewAvailable');
      return ret == true;
    }
    return true;
  }

  /// Creates a browser window. Its layout comes from the native composer the
  /// application installed, or the default composer's native toolbar.
  static Future<Webview> create({CreateConfiguration? configuration}) async {
    configuration ??= CreateConfiguration.platform();
    final arguments = configuration.toMap();
    final bridgeToken = createJavaScriptBridgeToken();
    arguments['javaScriptBridge'] = javaScriptBridgeSource(bridgeToken);
    final transport = attachTransport();
    pendingCreates++;
    try {
      final result =
          await transport.invoke<Map<Object?, Object?>>('create', arguments);
      final id = result?['id'] as int?;
      if (id == null) {
        throw StateError('Native create returned no browser ID');
      }
      final webview = WebviewImpl(id,
          windowHandle: result!['windowHandle'] as int? ?? 0,
          bridgeToken: bridgeToken,
          transport: transport);
      if (result['closed'] == true || closedDuringCreate.remove(id)) {
        webview.onClosed();
      } else {
        browsers[id] = webview;
      }
      return webview;
    } finally {
      pendingCreates--;
      if (pendingCreates == 0) closedDuringCreate.clear();
    }
  }

  /// Clear all cookies and storage. Closes every open browser on Windows and
  /// Linux first.
  static Future<void> clearAll({
    WindowsWebviewOptions windows = const WindowsWebviewOptions(),
  }) async {
    await attachTransport().invoke<void>('clearAll');

    // WebView2 has no profile-independent way to clear a user data folder.
    // https://docs.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder#create-user-data-folders
    if (Platform.isWindows) {
      final folder = windows.userDataFolder;
      final webview2Dir = Directory(p.isAbsolute(folder)
          ? folder
          : p.join(p.dirname(Platform.resolvedExecutable), folder));
      if (await webview2Dir.exists()) {
        for (var i = 0; i <= 4; i++) {
          try {
            await webview2Dir.delete(recursive: true);
            break;
          } catch (e) {
            debugPrint('delete cache failed. retrying.... $e');
          }
          // Wait until closed windows release their file handles.
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'navigation_decider.dart';

/// Dart side of the plugin's method channel.
class NativeTransport {
  NativeTransport._create() {
    _channel.setMethodCallHandler(dispatchEvent);
    if (Platform.isWindows) {
      registerWindowsNavigationDecider(
          (id, url) => onNavigationRequest?.call(id, url) ?? true);
    }
  }

  /// A transport without native code. Subclasses override [invoke]; events
  /// are injected with [dispatchEvent].
  @visibleForTesting
  NativeTransport.testing();

  @visibleForTesting
  static NativeTransport? debugOverride;

  static NativeTransport get instance => debugOverride ?? _native;
  static final _native = NativeTransport._create();

  static const _channel = MethodChannel('desktop_webview_window');

  /// Receives native calls. A returned value is sent back to native code.
  Future<Object?> Function(MethodCall call)? onEvent;

  /// Decides a top-level navigation synchronously. Windows calls it through
  /// FFI; other platforms send `onUrlRequest` through [onEvent].
  bool Function(int id, String url)? onNavigationRequest;

  Future<T?> invoke<T>(String method, [Object? arguments]) =>
      _channel.invokeMethod<T>(method, arguments);

  /// Delivers a native call to [onEvent].
  @visibleForTesting
  Future<Object?> dispatchEvent(MethodCall call) async {
    final handler = onEvent;
    if (handler == null) throw MissingPluginException(call.method);
    return handler(call);
  }
}

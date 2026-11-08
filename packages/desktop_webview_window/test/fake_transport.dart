import 'package:desktop_webview_window/src/native_transport.dart';
import 'package:flutter/services.dart';

typedef FakeHandler = Future<Object?> Function(MethodCall call);

/// Records channel calls without native code.
class FakeTransport extends NativeTransport {
  FakeTransport() : super.testing();

  FakeHandler? native;

  @override
  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    final handler = native;
    if (handler == null) throw MissingPluginException(method);
    return await handler(MethodCall(method, arguments)) as T?;
  }

  /// Delivers a native event and returns its reply.
  Future<Object?> send(String method, [Object? arguments]) =>
      dispatchEvent(MethodCall(method, arguments));
}

FakeTransport get fakeTransport => NativeTransport.instance as FakeTransport;

/// Installs a fresh fake for the next test.
FakeTransport installFakeTransport() {
  final fake = FakeTransport();
  NativeTransport.debugOverride = fake;
  return fake;
}

Future<Object?> sendBrowserEvent(String method, Map<String, Object?> args) =>
    fakeTransport.send(method, args);

/// A create reply for browser [id].
Map<String, Object?> created(int id, {bool closed = false}) => {
      'id': id,
      'windowHandle': closed ? 0 : 0x1000 + id,
      if (closed) 'closed': true,
    };

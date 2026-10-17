import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui' as ui;

typedef _DecideNative = Int32 Function(Int64, Pointer<Uint8>, Int32);
typedef _RegisterNative = Int64 Function(
    Pointer<Void>, Int64, Pointer<NativeFunction<_DecideNative>>, Int32);
typedef _Register = int Function(
    Pointer<Void>, int, Pointer<NativeFunction<_DecideNative>>, int);
typedef _CompleteNative = Int32 Function(Int64, Int64, Int32);
typedef _Complete = int Function(int, int, int);

/// Windows navigation decisions. WebView2's NavigationStarting has no
/// deferral, so native code asks Dart synchronously: directly when Dart runs on
/// the platform thread, otherwise through [ReceivePort] while the platform
/// thread waits.
///
/// Registered once for the isolate; a restarted isolate replaces it.
void registerWindowsNavigationDecider(
    bool Function(int browser, String url) decide) {
  final library = DynamicLibrary.open('desktop_webview_window_plugin.dll');
  final register = library
      .lookupFunction<_RegisterNative, _Register>('dww_navigation_register');
  final complete = library
      .lookupFunction<_CompleteNative, _Complete>('dww_navigation_complete');

  final callback = NativeCallable<_DecideNative>.isolateLocal(
    (int browser, Pointer<Uint8> url, int length) => decide(
            browser, utf8.decode(url.asTypedList(length), allowMalformed: true))
        ? 1
        : 0,
    exceptionalReturn: 1,
  );
  late final int generation;
  final port = ReceivePort()
    ..listen((dynamic message) {
      final data = message as List;
      if (data[0] != generation) return;
      final allow = decide(data[2] as int, data[3] as String);
      complete(generation, data[1] as int, allow ? 1 : 0);
    });
  generation = register(
    NativeApi.initializeApiDLData,
    port.sendPort.nativePort,
    callback.nativeFunction,
    ui.isRunningOnPlatformThread ? 1 : 0,
  );
  if (generation == 0) {
    port.close();
    callback.close();
    throw StateError(
        'desktop_webview_window could not initialize navigation decisions');
  }
  // The callback and port live as long as the isolate.
}

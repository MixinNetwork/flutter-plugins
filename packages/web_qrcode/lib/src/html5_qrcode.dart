@JS()
library html5_qrcode;

import 'dart:async';
import 'dart:js';

import 'package:flutter/cupertino.dart';
import 'package:js/js.dart';

@JS()
class Promise<T> {
  external Promise(
      void Function(void Function(T result) resolve, Function reject) executor);

  external Promise then(void Function(T result) onFulfilled,
      [Function onRejected]);
}

@JS()
class CameraDevice {
  external String? get id;

  external String? get label;

  external CameraDevice(String? id, String? label);
}

typedef QrcodeSuccessCallback = void Function(
  String decodedText,
  dynamic result,
);

@JS()
class Html5Qrcode {
  external Html5Qrcode(String elementId, [dynamic config]);

  external bool get isScanning;

  external void start(
    dynamic cameraIdOrConfig,
    dynamic configuration,
    QrcodeSuccessCallback successCallback,
  );

  external void render(QrcodeSuccessCallback successCallback);

  external void clear();

  external Promise stop();
}

extension PromissToFuture<T> on Promise<T> {
  Future<T> toFuture() {
    return promiseToFuture(this);
  }
}

/// Converts a JavaScript Promise to a Dart [Future].
///
/// ```dart
/// @JS()
/// external Promise<num> get threePromise; // Resolves to 3
///
/// final Future<num> threeFuture = promiseToFuture(threePromise);
///
/// final three = await threeFuture; // == 3
/// ```
Future<T> promiseToFuture<T>(Promise promise) {
  final completer = Completer<T>();
  promise.then(
    allowInterop((it) => completer.complete(it)),
    allowInterop(completer.completeError),
  );
  return completer.future;
}

@JS('Html5Qrcode.getCameras')
external Promise _cameras();

Future<List<String>> getCameras() async {
  final ret = await promiseToFuture(_cameras());
  assert(ret is List);
  final cameras = (ret as List).cast<CameraDevice>();
  debugPrint('cameras: ${cameras.map((e) => 'e: ${e.id}')}');
  return cameras.map((e) => '${e.id}: ${e.label}').toList();
}

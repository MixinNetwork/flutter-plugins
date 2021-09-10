import 'dart:async';
import 'dart:js';
import 'dart:js_util';

import 'package:flutter/cupertino.dart';

import 'src/html5_qrcode.dart';

export 'src/html5_qrcode.dart' show getCameras;

typedef QrCodeScanSuccessCallback = void Function(String data);

/// [error] error message or anything else description.
typedef CameraNotAvaliableCallback = void Function(dynamic error);

class QrCodeReader extends StatefulWidget {
  const QrCodeReader({
    Key? key,
    this.successCallback,
    this.cameraNotAvaliableCallback,
  }) : super(key: key);

  final QrCodeScanSuccessCallback? successCallback;
  final CameraNotAvaliableCallback? cameraNotAvaliableCallback;

  @override
  State<QrCodeReader> createState() => QrCodeReaderState();
}

class QrCodeReaderState extends State<QrCodeReader> {
  Html5Qrcode? _html5qrcode;

  Future<void> _startScanner(String elementId) async {
    if (_html5qrcode != null) {
      return;
    }

    try {
      final cameras = await getCameras();
      if (cameras.isEmpty) {
        widget.cameraNotAvaliableCallback
            ?.call('devices didn not have cameras.');
        return;
      }
    } catch (e) {
      widget.cameraNotAvaliableCallback?.call(e);
      return;
    }

    _html5qrcode = Html5Qrcode(
        elementId,
        {
          'formatsToSupport': [0]
        }.toJsObj())
      ..start(
        {
          'facingMode': 'environment',
        }.toJsObj(),
        {
          'fps': 10,
          'qrbox': 240,
          'aspectRatio': 1.7777778,
        }.toJsObj(),
        allowInterop((decodedText, result) {
          widget.successCallback?.call(decodedText);
        }),
      );
  }

  Future<void> stopScanner() async {
    final html5qrcode = _html5qrcode;
    if (html5qrcode == null) {
      return;
    }
    _html5qrcode = null;
    await html5qrcode.stop().toFuture();
    html5qrcode.clear();
  }

  @override
  void deactivate() {
    stopScanner();
    super.deactivate();
  }

  @override
  void dispose() {
    assert(
      _html5qrcode == null,
      "To avoid compatibility issues in html5-qrcode and flutter web, "
      "you need stop scanner before remove QrCodeReader from widget tree.",
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: 'qrcode_reader',
      onPlatformViewCreated: (int viewId) {
        _startScanner('qrreader_$viewId');
      },
    );
  }
}

extension MapToJsObj on Map<String, dynamic> {
  dynamic toJsObj() {
    var object = newObject();
    forEach((k, v) {
      var key = k;
      var value = v;
      setProperty(object, key, value);
    });
    return object;
  }
}

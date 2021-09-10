import 'dart:async';
import 'dart:js';
import 'dart:js_util';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'src/html5_qrcode.dart';

class FlutterQrcode {
  static const MethodChannel _channel = MethodChannel('flutter_qrcode');

  static Future<List<String>> get cameras async {
    final List<dynamic> cameras = await _channel.invokeMethod('getCameras');
    return cameras.cast();
  }

  static Future<void> startScanner() async {
    await _channel.invokeMethod('startScanner');
  }
}

typedef QrCodeScanSuccessCallback = void Function(String data);

class QrCodeReader extends StatefulWidget {
  const QrCodeReader({
    Key? key,
    this.successCallback,
  }) : super(key: key);

  final QrCodeScanSuccessCallback? successCallback;

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
      debugPrint('cameras: $cameras');
    } catch (e) {
      // TODO no cameras available.
      debugPrint('cameras: $e');
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

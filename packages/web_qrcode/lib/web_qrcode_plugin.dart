import 'dart:async';
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/html5_qrcode.dart';

/// A web implementation of the FlutterQrcode plugin.
class WebQrcodePlugin {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'flutter_qrcode',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = WebQrcodePlugin();
    channel.setMethodCallHandler((call) async {
      try {
        return await pluginInstance.handleMethodCall(call);
      } catch (e, s) {
        debugPrint("error: $e $s");
      }
    });

    // html.document.body!.append(
    //   html.ScriptElement()
    //     ..src = 'assets/packages/flutter_qrcode/assets/html5-qrcode.min.js'
    //     ..type = 'application/javascript'
    //     // ..defer = true,
    // );

    // ignore: UNDEFINED_PREFIXED_NAME
    ui.platformViewRegistry.registerViewFactory(
      'qrcode_reader',
      (int viewId) {
        final container = html.DivElement()
          ..style.width = '100%'
          ..style.height = '100%';
        container.append(html.DivElement()
          ..id = 'qrreader_$viewId'
          ..style.position = 'absolute'
          ..style.top = '50%'
          ..style.transform = 'translate(0, -50%)'
          ..style.width = '100%'
          ..style.height = 'auto');
        return container;
      },
    );
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getCameras':
        final ret = await getCameras();
        return ret;

      case 'startScanner':

      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              'flutter_qrcode for web doesn\'t implement \'${call.method}\'',
        );
    }
  }
}

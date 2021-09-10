import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// A web implementation of the FlutterQrcode plugin.
class WebQrcodePlugin {
  static void registerWith(Registrar registrar) {
    // html.document.body!.append(
    //   html.ScriptElement()
    //     ..src = 'assets/packages/web_qrcode/assets/html5-qrcode.min.js'
    //     ..type = 'application/javascript'
    //     ..defer = true,
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

}

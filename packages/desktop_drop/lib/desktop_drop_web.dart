import 'dart:async';
// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window, Url;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/drop_item.dart';

/// A web implementation of the DesktopDrop plugin.
class DesktopDropWeb {
  final MethodChannel channel;

  DesktopDropWeb._private(this.channel);

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'desktop_drop',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = DesktopDropWeb._private(channel);
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
    pluginInstance._registerEvents();
  }

  void _registerEvents() {
    html.window.onDrop.listen((event) {
      event.preventDefault();

      final results = <WebDropItem>[];

      try {
        final items = event.dataTransfer.files;
        if (items != null) {
          for (final item in items) {
            results.add(
              WebDropItem(
                uri: html.Url.createObjectUrl(item),
                name: item.name,
                size: item.size,
                type: item.type,
                relativePath: item.relativePath,
                lastModified: item.lastModified != null
                    ? DateTime.fromMillisecondsSinceEpoch(item.lastModified!)
                    : item.lastModifiedDate,
              ),
            );
          }
        }
      } catch (e, s) {
        debugPrint('desktop_drop_web: $e $s');
      } finally {
        channel.invokeMethod(
          "performOperation_web",
          results.map((e) => e.toJson()).toList(),
        );
      }
    });

    html.window.onDragEnter.listen((event) {
      event.preventDefault();
      channel.invokeMethod('entered', [
        event.client.x.toDouble(),
        event.client.y.toDouble(),
      ]);
    });

    html.window.onDragOver.listen((event) {
      event.preventDefault();
      channel.invokeMethod('updated', [
        event.client.x.toDouble(),
        event.client.y.toDouble(),
      ]);
    });

    html.window.onDragLeave.listen((event) {
      event.preventDefault();
      channel.invokeMethod('exited', [
        event.client.x.toDouble(),
        event.client.y.toDouble(),
      ]);
    });
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    throw PlatformException(
      code: 'Unimplemented',
      details: 'desktop_drop for web doesn\'t implement \'${call.method}\'',
    );
  }
}

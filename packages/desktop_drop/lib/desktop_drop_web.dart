import 'dart:async';
import 'dart:html' as html show window, Url, DataTransfer;

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

  html.DataTransfer? _dataTransfer;

  void _registerEvents() {
    html.window.onDragEnter.listen(
      (event) {
        event.preventDefault();
        _dataTransfer = event.dataTransfer;
        channel.invokeMethod('entered', [
          event.client.x.toDouble(),
          event.client.y.toDouble(),
        ]);
      },
    );

    html.window.onDragOver.listen(
      (event) {
        event.preventDefault();
        _dataTransfer = event.dataTransfer;
        channel.invokeMethod('updated', [
          event.client.x.toDouble(),
          event.client.y.toDouble(),
        ]);
      },
    );

    html.window.onDrop.listen(
      (event) {
        event.preventDefault();
        _dataTransfer = null;
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
      },
    );

    html.window.onDragLeave.listen(
      (event) {
        event.preventDefault();
        _dataTransfer = null;
        channel.invokeMethod('exited', [
          event.client.x.toDouble(),
          event.client.y.toDouble(),
        ]);
      },
    );
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'updateDroppableStatus':
        final enable = call.arguments as bool;
        final current = _dataTransfer?.dropEffect;
        final newValue = enable ? 'copy' : 'move';
        if (current !=  newValue) {
          _dataTransfer?.dropEffect = newValue;
        }
        return;
      default:
        break;
    }

    throw PlatformException(
      code: 'Unimplemented',
      details: 'desktop_drop for web doesn\'t implement \'${call.method}\'',
    );
  }
}

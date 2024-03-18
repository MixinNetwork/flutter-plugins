import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mime/mime.dart';

import 'src/web_drop_item.dart';

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

  Future<WebDropItem> _entryToWebDropItem(dynamic entry) async {
    if (entry.isDirectory == true) {
      final reader = js_util.callMethod(entry, 'createReader', []);
      final entriesCompleter = Completer<List>();
      final metadataCompleter = Completer();
      entry.getMetadata((value) {
        metadataCompleter.complete(value);
      }, (error) {
        metadataCompleter.completeError(error);
      });
      final metaData = await metadataCompleter.future;
      reader.readEntries((values) {
        entriesCompleter.complete(List.from(values));
      }, (error) {
        entriesCompleter.completeError(error);
      });
      final entries = await entriesCompleter.future;
      final modificationTime = js_util.dartify(metaData.modificationTime);
      final children = await Future.wait(
        entries.map((e) => _entryToWebDropItem(e)),
      )
        ..removeWhere(
            (element) => element.name == '.DS_Store' && element.type == '');
      return WebDropItem(
        uri: html.Url.createObjectUrlFromBlob(html.Blob([], 'directory')),
        name: entry.name ?? '',
        size: metaData.size ?? 0,
        lastModified: modificationTime != null && modificationTime is DateTime
            ? modificationTime
            : DateTime.now(),
        relativePath: entry.fullPath,
        type: 'directory',
        children: children,
      );
    }
    final fileCompleter = Completer<html.File>();
    entry.file((file) {
      fileCompleter.complete(file);
    }, (error) {
      fileCompleter.completeError(error);
    });
    final file = await fileCompleter.future;
    return WebDropItem(
      uri: html.Url.createObjectUrl(file),
      children: [],
      name: file.name,
      size: file.size,
      type: file.type,
      relativePath: file.relativePath,
      lastModified: file.lastModified != null
          ? DateTime.fromMillisecondsSinceEpoch(file.lastModified!)
          : file.lastModifiedDate,
    );
  }

  String _getMimeType(String text) {
    final pattern = RegExp(r'^data:([^;]+);');
    return pattern.firstMatch(text)?.group(1) ?? 'text/plain';
  }

  void _registerEvents() {
    html.window.onDrop.listen((event) {
      event.preventDefault();

      final items = event.dataTransfer.items;
      Future.wait(List.generate(items?.length ?? 0, (index) {
        final item = items![index];
        if (item.kind == 'file') {
          final entry = item.getAsEntry();
          return _entryToWebDropItem(entry);
        }
        if (item.kind == 'string' && item.type == 'text/uri-list') {
          final data = event.dataTransfer.getData(item.type!);
          final mime = _getMimeType(data);
          return Future.value(
            WebDropItem(
              uri: data,
              name: 'file.${extensionFromMime(mime)}',
              type: mime,
              data: base64Decode(data.split(';base64,')[1]),
              size: 0,
              relativePath: '',
              lastModified: DateTime.now(),
              children: [],
            ),
          );
        }
        // other types such as text/html
        return Future.value(null);
      })).then((webItems) {
        channel.invokeMethod(
          "performOperation_web",
          webItems.whereType<WebDropItem>().map((e) => e.toJson()).toList(),
        );
      }).catchError((e, s) {
        debugPrint('desktop_drop_web: $e $s');
      });
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

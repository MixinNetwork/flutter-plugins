import 'dart:async';

import 'package:web/web.dart' as web;
import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

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

  Future<WebDropItem> _entryToWebDropItem(web.FileSystemEntry entry) async {
    if (entry.isDirectory == true) {
      entry = entry as web.FileSystemDirectoryEntry;
      final web.FileSystemDirectoryReader reader = entry.createReader();
      Completer entriesCompleter = Completer<List<dynamic>>();
      entriesCallBack(JSArray<web.FileSystemEntry> sub) {
        entriesCompleter.complete(sub.toDart);
      }

      reader.readEntries(entriesCallBack.toJS);

      final List<dynamic> entries = await entriesCompleter.future;

      final children = await Future.wait(
        entries.map((e) => _entryToWebDropItem(e)),
      )
        ..removeWhere(
            (element) => element.name == '.DS_Store' && element.type == '');

      return WebDropItem(
        uri: web.URL.createObjectURL(web.Blob().slice(0, 0, 'directory')),
        name: entry.name,
        size: 0,
        lastModified: DateTime.now(),
        relativePath: entry.fullPath,
        type: 'directory',
        children: children,
      );
    }

    entry = entry as web.FileSystemFileEntry;

    Completer fileCompleter = Completer<web.File>();

    fileCallBack(web.File file) {
      fileCompleter.complete(file);
    }

    entry.file(fileCallBack.toJS);

    final web.File file = await fileCompleter.future;

    return WebDropItem(
      uri: web.URL.createObjectURL(file),
      name: file.name,
      size: file.size,
      lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
      relativePath: entry.fullPath,
      type: file.type,
      children: [],
    );

  }

  void _registerEvents() {
    web.window.ondrop = ((web.DragEvent event) {
      event.preventDefault();

      final items = event.dataTransfer!.items;

      Future.wait(List.generate(items.length, (index) {
        final item = items[index];
        final entry = item.webkitGetAsEntry()!;
        return _entryToWebDropItem(entry);
      })).then((webItems) {
        channel.invokeMethod(
          "performOperation_web",
          webItems.map((e) => e.toJson()).toList(),
        );
      }).catchError((e, s) {
        debugPrint('desktop_drop_web: $e $s');
      });
    }.toJS);

    web.window.ondragenter = ((web.DragEvent event) {
      event.preventDefault();
      channel.invokeMethod('entered', [
        event.clientX.toDouble(),
        event.clientY.toDouble(),
      ]);
    }.toJS);

    web.window.ondragover = ((web.DragEvent event) {
      event.preventDefault();
      channel.invokeMethod('updated', [
        event.clientX.toDouble(),
        event.clientY.toDouble(),
      ]);
    }.toJS);

    web.window.ondragleave = ((web.DragEvent event) {
      event.preventDefault();
      channel.invokeMethod('exited', [
        event.clientX.toDouble(),
        event.clientY.toDouble(),
      ]);
    }.toJS);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    throw PlatformException(
      code: 'Unimplemented',
      details: 'desktop_drop for web doesn\'t implement \'${call.method}\'',
    );
  }
}

extension DataTransferItemListExt on web.DataTransferItemList {
  external web.DataTransferItem operator [](int index);
}

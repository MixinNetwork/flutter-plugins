import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/drop_coordinator.dart';
import 'src/drop_offer.dart';
import 'src/web_drop_item.dart';

// DOM listeners outlive Dart statics during a browser hot restart. Keep raw JS
// references so a new registration can remove the previous runtime's callbacks.
@JS('__desktopDropListeners')
external JSObject? get _registeredListeners;
@JS('__desktopDropListeners')
external set _registeredListeners(JSObject? value);

/// Browser drag decisions run within the DOM event, before preventDefault and
/// dropEffect are returned to the browser. File reads happen after acceptance.
class DesktopDropWeb {
  static DesktopDropWeb? _instance;
  // Targets can survive re-registration, so feedback IDs must keep increasing.
  static int _session = 0, _request = 0;
  final _listeners = <String, JSFunction>{};
  int? _hoverView;

  static void registerWith(Registrar registrar) {
    _instance?._dispose();
    _instance = DesktopDropWeb().._registerEvents();
  }

  // The FileSystemDirectoryReader.readEntries() Web API returns at most 100
  // entries per call by spec. To retrieve all children of a directory, the
  // caller must call readEntries() repeatedly until it returns an empty batch.
  // Calling it only once silently truncates directories with >100 files.
  // See: https://wicg.github.io/entries-api/#dom-filesystemdirectoryreader-readentries
  Future<List<dynamic>> _readAllEntries(
    web.FileSystemDirectoryReader reader,
  ) async {
    final allEntries = <dynamic>[];
    while (true) {
      final completer = Completer<List<dynamic>>();
      reader.readEntries(
        (JSArray<web.FileSystemEntry> batch) {
          completer.complete(batch.toDart);
        }.toJS,
        ((web.DOMException error) => completer.completeError(
          StateError(error.message),
        )).toJS,
      );
      final batch = await completer.future;
      if (batch.isEmpty) break;
      allEntries.addAll(batch);
    }
    return allEntries;
  }

  Future<WebDropItem> _entryToWebDropItem(web.FileSystemEntry entry) async {
    if (entry.isDirectory == true) {
      entry = entry as web.FileSystemDirectoryEntry;
      final web.FileSystemDirectoryReader reader = entry.createReader();

      final List<dynamic> entries = await _readAllEntries(reader);

      final children =
          await Future.wait(entries.map((e) => _entryToWebDropItem(e)))
            ..removeWhere(
              (element) => element.name == '.DS_Store' && element.type == '',
            );

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

    entry.file(
      fileCallBack.toJS,
      ((web.DOMException error) => fileCompleter.completeError(
        StateError(error.message),
      )).toJS,
    );

    final web.File file = await fileCompleter.future;

    return _fileToWebDropItem(file, relativePath: entry.fullPath);
  }

  /// Builds a [WebDropItem] straight from a [web.File].
  ///
  /// Used for drag sources that expose a file but no FileSystemEntry, such as
  /// the browser's own downloads menu. Those items have no path relative to a
  /// dropped folder, so [relativePath] is null.
  WebDropItem _fileToWebDropItem(web.File file, {String? relativePath}) {
    return WebDropItem(
      uri: web.URL.createObjectURL(file),
      name: file.name,
      size: file.size,
      lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
      relativePath: relativePath,
      type: file.type,
      children: [],
    );
  }

  Map<String, Object?> _offer(
    web.DataTransfer data, {
    required bool finalDrop,
  }) {
    final types = <String>{};
    final files = <Map<String, Object?>>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      if (item.kind == 'file') {
        types.add('file');
        final file = item.getAsFile();
        final entry = finalDrop ? item.webkitGetAsEntry() : null;
        files.add({
          'name': file?.name ?? entry?.name ?? '',
          'mimeType': item.type,
          if (entry != null) 'isDirectory': entry.isDirectory,
        });
      } else if (item.type == 'text/plain') {
        types.add('text');
      } else if (item.type == 'text/uri-list') {
        types.add('url');
      }
    }
    // In protected mode getData is empty even though types are advertised.
    final urls = finalDrop
        ? data
              .getData('text/uri-list')
              .split(RegExp(r'[\r\n]+'))
              .where((line) => line.isNotEmpty && !line.startsWith('#'))
              .where((line) => Uri.tryParse(line)?.hasScheme == true)
              .toList()
        : <String>[];
    return {
      'types': types.toList(),
      'files': files,
      'urls': urls,
      'text': finalDrop && types.contains('text')
          ? data.getData('text/plain')
          : null,
      'isComplete': finalDrop,
    };
  }

  (int, Offset)? _location(web.DragEvent event) {
    // The nearest host in the DOM path owns the event, including when views
    // overlap or nest. Rectangle order does not describe DOM hit testing.
    for (final node in event.composedPath().toDart) {
      for (final view in ui.PlatformDispatcher.instance.views) {
        final host =
            ui_web.views.getHostElement(view.viewId) as web.HTMLElement?;
        if (host == null || node != host) continue;
        final rect = host.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return null;
        // CSS transforms can scale the host independently of devicePixelRatio.
        return (
          view.viewId,
          Offset(
            (event.clientX - rect.left) * host.clientWidth / rect.width,
            (event.clientY - rect.top) * host.clientHeight / rect.height,
          ),
        );
      }
    }
    return null;
  }

  void _exit() {
    if (_hoverView case final int view) {
      DropCoordinator.instance.platformEvent({
        'event': 'exit',
        'view': view,
        'session': _session,
      });
    }
    _hoverView = null;
  }

  void _handle(web.DragEvent event) {
    final location = _location(event);
    final data = event.dataTransfer;
    if (location == null || data == null) {
      _exit();
      return;
    }
    final (view, position) = location;
    if (event.type == 'dragleave') {
      // Moving between descendants is not leaving the Flutter view.
      final host = ui_web.views.getHostElement(view) as web.HTMLElement?;
      final related = event.relatedTarget;
      if (related != null &&
          host != null &&
          host.contains(related as web.Node)) {
        return;
      }
      _exit();
      return;
    }
    if (_hoverView != view) {
      _exit();
      _session++;
      _hoverView = view;
    }
    final finalDrop = event.type == 'drop';
    final offer = _offer(data, finalDrop: finalDrop);
    final coordinator = DropCoordinator.instance;
    final target = coordinator.decide(view, DropOffer.fromMap(offer), position);
    event.preventDefault();
    data.dropEffect = target > 0 ? 'copy' : 'none';
    final args = <Object?, Object?>{
      'view': view,
      'session': _session,
      'request': ++_request,
      'phase': finalDrop ? 2 : 1,
      'target': target,
      'x': position.dx,
      'y': position.dy,
      'offer': offer,
    };
    coordinator.platformEvent({...args, 'event': 'feedback'});
    if (!finalDrop) return;
    _hoverView = null;
    if (target == 0) return;
    // Capture entries/files while the data store is readable. After this DOM
    // callback it becomes protected again. Keep the committed target/position.
    final pending = <Future<WebDropItem?>>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      if (item.kind != 'file') continue;
      final entry = item.webkitGetAsEntry();
      final file = entry == null ? item.getAsFile() : null;
      pending.add(
        entry != null
            ? _entryToWebDropItem(entry)
            : Future.value(file == null ? null : _fileToWebDropItem(file)),
      );
    }
    unawaited(
      Future.wait(pending)
          .then((items) {
            final materialized = {
              ...offer,
              'files': items
                  .whereType<WebDropItem>()
                  .map((item) => item.toJson())
                  .toList(),
            };
            coordinator.platformEvent({
              ...args,
              'event': 'drop',
              'offer': materialized,
            });
          })
          .catchError((Object error, StackTrace stack) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'desktop_drop',
                context: ErrorDescription('while reading a browser drop'),
              ),
            );
          }),
    );
  }

  void _registerEvents() {
    final previous = _registeredListeners;
    final registered = JSObject();
    for (final type in ['dragenter', 'dragover', 'dragleave', 'drop']) {
      final old = previous?.getProperty<JSFunction?>(type.toJS);
      if (old != null) web.window.removeEventListener(type, old);
      final listener = ((web.Event event) => _handle(
        event as web.DragEvent,
      )).toJS;
      _listeners[type] = listener;
      registered.setProperty(type.toJS, listener);
      web.window.addEventListener(type, listener);
    }
    _registeredListeners = registered;
  }

  void _dispose() {
    _exit();
    for (final entry in _listeners.entries) {
      web.window.removeEventListener(entry.key, entry.value);
    }
  }
}

extension DataTransferItemListExt on web.DataTransferItemList {
  external web.DataTransferItem operator [](int index);
}

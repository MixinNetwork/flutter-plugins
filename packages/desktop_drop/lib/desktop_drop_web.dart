import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:cross_file/cross_file.dart';
import 'package:cross_file_web/cross_file_web.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/drop_coordinator.dart';
import 'src/drop_offer.dart';
import 'src/drop_item.dart';
import 'src/drop_target.dart';
import 'src/virtual_directory.dart';

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
  static int _session = 0;
  final _listeners = <String, JSFunction>{};
  int? _hoverView;
  DropOffer? _hoverOffer;

  static void registerWith(Registrar registrar) {
    _instance?._dispose();
    _instance = DesktopDropWeb().._registerEvents();
  }

  // The FileSystemDirectoryReader.readEntries() Web API returns at most 100
  // entries per call by spec. To retrieve all children of a directory, the
  // caller must call readEntries() repeatedly until it returns an empty batch.
  // Calling it only once silently truncates directories with >100 files.
  // See: https://wicg.github.io/entries-api/#dom-filesystemdirectoryreader-readentries
  Future<List<web.FileSystemEntry>> _readAllEntries(
    web.FileSystemDirectoryReader reader,
  ) async {
    final allEntries = <web.FileSystemEntry>[];
    while (true) {
      final completer = Completer<List<web.FileSystemEntry>>();
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

  Future<DropItem> _entryToDropItem(
    web.FileSystemEntry entry,
    void Function(XEntity) retain,
  ) async {
    if (entry.isDirectory) {
      final directory = entry as web.FileSystemDirectoryEntry;
      final resource = virtualDirectory(entry.name, () async* {
        final entries = await _readAllEntries(directory.createReader());
        for (final entry in entries) {
          yield switch (await _entryToDropItem(entry, retain)) {
            DropFileItem(:final file) => file,
            DropDirectoryItem(:final directory) => directory,
            DropStringItem() => throw StateError('Not a directory entry'),
          };
        }
      });
      retain(resource);
      return DropDirectoryItem(name: entry.name, directory: resource);
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

    return _fileToDropItem(file, retain);
  }

  DropFileItem _fileToDropItem(web.File file, void Function(XEntity) retain) {
    final resource = ScopedStorageXFile.fromCreationParams(
      WebScopedStorageXFileCreationParams.fromBlob(file),
    );
    retain(resource);
    return DropFileItem(
      file: resource,
      name: file.name,
      mimeType: file.type.isEmpty ? null : file.type,
    );
  }

  Future<void> _disposeResource(XEntity entity) async {
    if (entity is ScopedStorageXFile) await entity.dispose();
    if (entity is ScopedStorageXDirectory) await entity.dispose();
  }

  DropOffer _offer(web.DataTransfer data, {required bool finalDrop}) {
    final strings = <DropItemPreview>[];
    final files = <DropItemPreview>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      if (item.kind == 'file') {
        final file = item.getAsFile();
        final entry = finalDrop ? item.webkitGetAsEntry() : null;
        files.add(
          DropItemPreview(
            kind: entry?.isDirectory == true
                ? DropItemKind.directory
                : DropItemKind.file,
            name: file?.name ?? entry?.name ?? '',
            mimeType: item.type,
          ),
        );
      } else if (item.kind == 'string') {
        strings.add(
          DropItemPreview(
            kind: DropItemKind.string,
            mimeType: item.type,
            value: finalDrop ? data.getData(item.type) : null,
          ),
        );
      }
    }
    return DropOffer(
      allowedOperations: switch (data.effectAllowed) {
        'copy' => {DropOperation.copy},
        'move' => {DropOperation.move},
        'link' => {DropOperation.link},
        'copyMove' => {DropOperation.copy, DropOperation.move},
        'copyLink' => {DropOperation.copy, DropOperation.link},
        'linkMove' => {DropOperation.link, DropOperation.move},
        // The HTML standard treats uninitialized as allowing all operations.
        'all' || 'uninitialized' => {
          DropOperation.copy,
          DropOperation.move,
          DropOperation.link,
        },
        _ => <DropOperation>{},
      },
      items: [...files, ...strings],
      isComplete: finalDrop,
    );
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
      DropCoordinator.instance.exit(view, _session);
    }
    _hoverView = null;
    _hoverOffer = null;
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
    final offer = finalDrop
        ? _offer(data, finalDrop: true)
        : _hoverOffer ?? _offer(data, finalDrop: false);
    _hoverOffer = offer;
    final coordinator = DropCoordinator.instance;
    final selection = coordinator.decide(view, offer, position);
    final target = selection.target;
    event.preventDefault();
    data.dropEffect = selection.operation == DropOperation.reject
        ? 'none'
        : selection.operation.name;
    if (!finalDrop) {
      coordinator.feedback(view, _session, selection, offer, position);
      return;
    }
    final details = coordinator.details(view, selection, offer, position);
    coordinator.exit(view);
    _hoverView = null;
    _hoverOffer = null;
    if (details == null) return;
    final resources = <XEntity>[];
    var active = true;
    void retain(XEntity entity) {
      if (!active) {
        unawaited(_disposeResource(entity));
        throw StateError('Dropped source has expired');
      }
      resources.add(entity);
    }

    // Capture entries/files while the data store is readable. After this DOM
    // callback it becomes protected again. Keep the committed target/position.
    final pending = <Future<DropItem?>>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      if (item.kind == 'string') {
        pending.add(
          Future.value(
            DropStringItem(mimeType: item.type, value: data.getData(item.type)),
          ),
        );
        continue;
      }
      if (item.kind != 'file') continue;
      final entry = item.webkitGetAsEntry();
      final file = entry == null ? item.getAsFile() : null;
      pending.add(
        entry != null
            ? _entryToDropItem(entry, retain)
            : Future.value(file == null ? null : _fileToDropItem(file, retain)),
      );
    }
    unawaited(
      Future.wait(pending)
          .then((items) async {
            await coordinator.drop(
              view,
              target,
              DropEvent(
                offer: offer,
                localPosition: details.localPosition,
                globalPosition: details.globalPosition,
                operation: selection.operation,
                items: items.whereType<DropItem>().toList(),
              ),
            );
          })
          .whenComplete(() async {
            active = false;
            try {
              await Future.wait(resources.map(_disposeResource));
            } finally {
              resources.clear();
            }
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
      if (old != null) {
        web.window.removeEventListener(type, old);
        web.window.removeEventListener(type, old, true.toJS);
      }
      final listener = ((web.Event event) => _handle(
        event as web.DragEvent,
      )).toJS;
      _listeners[type] = listener;
      registered.setProperty(type.toJS, listener);
      web.window.addEventListener(type, listener, true.toJS);
    }
    _registeredListeners = registered;
  }

  void _dispose() {
    _exit();
    for (final entry in _listeners.entries) {
      web.window.removeEventListener(entry.key, entry.value, true.toJS);
    }
  }
}

extension DataTransferItemListExt on web.DataTransferItemList {
  external web.DataTransferItem operator [](int index);
}

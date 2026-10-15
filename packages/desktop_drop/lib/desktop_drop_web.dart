import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/drop_coordinator.dart';
import 'src/drop_offer.dart';
import 'src/drop_item.dart';
import 'src/file_reader_web.dart' as reader;

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

  Future<DropItem> _entryToDropItem(web.FileSystemEntry entry) async {
    if (entry.isDirectory == true) {
      entry = entry as web.FileSystemDirectoryEntry;
      final web.FileSystemDirectoryReader reader = entry.createReader();

      final List<dynamic> entries = await _readAllEntries(reader);

      final children =
          await Future.wait(entries.map((e) => _entryToDropItem(e)))
            ..removeWhere(
              (element) =>
                  element.name == '.DS_Store' && element.mimeType == '',
            );

      return DropItemDirectory(
        web.URL.createObjectURL(web.Blob()),
        children,
        name: entry.name,
        length: 0,
        mimeType: 'directory',
        lastModified: DateTime.now(),
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

    return _fileToDropItem(file);
  }

  DropItemFile _fileToDropItem(web.File file) => _BrowserDropFile(
    file,
    name: file.name,
    modified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
  );

  List<Uri> _imageUris(web.DataTransfer data) {
    final candidates = <String>{};
    final html = data.getData('text/html');
    if (html.isNotEmpty) {
      // Template contents are inert: parsing must not load source images.
      final template =
          web.document.createElement('template') as web.HTMLTemplateElement;
      template.innerHTML = html.toJS;
      final images = template.content.querySelectorAll('img[src]');
      for (var i = 0; i < images.length; i++) {
        final source = (images.item(i) as web.Element).getAttribute('src');
        if (source != null) candidates.add(source);
      }
    }
    for (final line
        in data.getData('text/uri-list').split(RegExp(r'[\r\n]+'))) {
      if (line.startsWith('data:image/')) candidates.add(line);
    }
    return candidates
        .map(Uri.tryParse)
        .whereType<Uri>()
        .where(
          (uri) =>
              uri.scheme == 'http' ||
              uri.scheme == 'https' ||
              uri.scheme == 'blob' ||
              (uri.scheme == 'data' && uri.data!.mimeType.startsWith('image/')),
        )
        .toList();
  }

  String _imageName(Uri uri) {
    if (uri.scheme != 'data' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last.isNotEmpty) {
      return uri.pathSegments.last;
    }
    final type = uri.data?.mimeType.split('/').last ?? 'png';
    return 'image.${type == 'svg+xml' ? 'svg' : type}';
  }

  Future<DropItem?> _readImage(Uri uri) async {
    final controller = web.AbortController();
    try {
      if (uri.scheme == 'data') {
        final data = uri.data!;
        return _BrowserDropFile(
          web.Blob(
            [data.contentAsBytes().toJS].toJS,
            web.BlobPropertyBag(type: data.mimeType),
          ),
          name: _imageName(uri),
        );
      }
      return await (() async {
        final response = await web.window
            .fetch(
              uri.toString().toJS,
              web.RequestInit(signal: controller.signal, credentials: 'omit'),
            )
            .toDart;
        if (!response.ok) throw StateError('HTTP ${response.status}');
        final blob = await response.blob().toDart;
        if (!blob.type.startsWith('image/')) {
          throw StateError('Source did not provide an image');
        }
        return _BrowserDropFile(blob, name: _imageName(uri));
      })().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          controller.abort();
          throw TimeoutException('Timed out reading dragged image');
        },
      );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'desktop_drop',
          context: ErrorDescription(
            'while reading a dragged image; its URL remains available in DropDoneDetails.urls',
          ),
        ),
      );
      return null;
    }
  }

  Map<String, Object?> _offer(
    web.DataTransfer data, {
    required bool finalDrop,
  }) {
    final types = <String>{};
    final files = <Map<String, Object?>>[];
    var hasHtml = false;
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
      } else if (item.type == 'text/html') {
        hasHtml = true;
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
    if (files.isEmpty) {
      if (finalDrop) {
        for (final uri in _imageUris(data)) {
          types.addAll(['file', 'url']);
          final source = uri.toString();
          if (!urls.contains(source)) urls.add(source);
          files.add({
            'name': _imageName(uri),
            'imageUrl': source,
            'mimeType': uri.scheme == 'data' ? uri.data!.mimeType : null,
          });
        }
      } else if (hasHtml || types.contains('url')) {
        // Protected-mode metadata cannot distinguish an image URL from a link.
        types.add('file');
      }
    }
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
    final pending = <Future<DropItem?>>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      if (item.kind != 'file') continue;
      final entry = item.webkitGetAsEntry();
      final file = entry == null ? item.getAsFile() : null;
      pending.add(
        entry != null
            ? _entryToDropItem(entry)
            : Future.value(file == null ? null : _fileToDropItem(file)),
      );
    }
    if (pending.isEmpty) {
      for (final file in offer['files'] as List<Map<String, Object?>>) {
        if (file['imageUrl'] case final String source) {
          pending.add(_readImage(Uri.parse(source)));
        }
      }
    }
    unawaited(
      Future.wait(pending)
          .then((items) {
            final materialized = {
              ...offer,
              'files': items
                  .whereType<DropItem>()
                  .map(
                    (item) => {
                      'path': item.path,
                      'name': item.name,
                      'mimeType': item.mimeType,
                      'isDirectory': item is DropItemDirectory,
                    },
                  )
                  .toList(),
            };
            coordinator.platformEvent({
              ...args,
              'event': 'drop',
              'items': items.whereType<DropItem>().toList(),
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

/// Owns the source Blob even if an application revokes the display URL.
class _BrowserDropFile extends DropItemFile {
  _BrowserDropFile(this.blob, {required String name, DateTime? modified})
    : super(
        web.URL.createObjectURL(blob),
        name: name,
        mimeType: blob.type,
        length: blob.size,
        lastModified: modified ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
  final web.Blob blob;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      reader.readBlob(blob, start, end);
  @override
  Future<void> saveTo(String destination) =>
      reader.downloadBlob(blob, destination);
}

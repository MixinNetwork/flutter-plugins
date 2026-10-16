@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:cross_file_web/cross_file_web.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_drop/desktop_drop_web.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

@JS('Object.defineProperty')
external JSObject _defineProperty(
  JSObject object,
  JSString key,
  JSObject descriptor,
);

web.DataTransfer transfer({String allowed = 'all'}) {
  final data = web.DataTransfer();
  // Synthetic events do not have a browser-managed drag source. Supply its
  // allowed operations explicitly rather than relying on protected setters.
  for (final entry in {
    'effectAllowed': allowed,
    'dropEffect': 'none',
  }.entries) {
    _defineProperty(
      data,
      entry.key.toJS,
      {'value': entry.value, 'writable': true}.jsify() as JSObject,
    );
  }
  return data;
}

@JS('DataTransferItem.prototype')
external JSObject get _itemPrototype;

void useEntry(JSObject entry) {
  final original = _itemPrototype.getProperty<JSAny?>('webkitGetAsEntry'.toJS);
  _itemPrototype.setProperty('webkitGetAsEntry'.toJS, (() => entry).toJS);
  addTearDown(
    () => _itemPrototype.setProperty('webkitGetAsEntry'.toJS, original),
  );
}

void send(String type, web.DataTransfer data, Offset position) {
  (ui_web.views.getHostElement(0) as web.HTMLElement).dispatchEvent(
    web.DragEvent(
      type,
      web.DragEventInit(
        dataTransfer: data,
        clientX: position.dx.round(),
        clientY: position.dy.round(),
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
}

String stringValue(DropEvent event, String mimeType) => event.items
    .whereType<DropStringItem>()
    .singleWhere((item) => item.mimeType == mimeType)
    .value;

Future<Offset> mount(
  WidgetTester tester, {
  required bool Function(DropEventDetails) accepts,
  DropOperation operation = DropOperation.copy,
  required FutureOr<void> Function(DropEvent) done,
  void Function(DropEventDetails)? entered,
  void Function(DropEventDetails)? exited,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: DropTarget(
          onDropDecision: (details) =>
              accepts(details) ? operation : DropOperation.reject,
          onDrop: done,
          onDragEntered: entered,
          onDragExited: exited,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    ),
  );
  await tester.pump();
  final host =
      ui_web.views.getHostElement(tester.view.viewId) as web.HTMLElement;
  host.style.width = '800px';
  host.style.height = '600px';
  final rect = host.getBoundingClientRect();
  expect(rect.width, greaterThan(0));
  final point = tester.getCenter(find.byType(DropTarget));
  return point + Offset(rect.left, rect.top);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    CrossFileWeb.registerWith(webPluginRegistrar);
    DesktopDropWeb.registerWith(webPluginRegistrar);
  });

  for (final operation in [
    DropOperation.copy,
    DropOperation.move,
    DropOperation.link,
  ]) {
    testWidgets(
      'browser negotiates ${operation.name} within source operations',
      (tester) async {
        DropEvent? done;
        final point = await mount(
          tester,
          accepts: (_) => true,
          operation: operation,
          done: (details) => done = details,
        );
        final data = transfer(allowed: operation.name)
          ..setData('text/plain', 'hello');
        send('dragover', data, point);
        expect(data.dropEffect, operation.name);
        send('drop', data, point);
        await tester.pump();
        expect(done!.operation, operation);
        expect(done!.allowedOperations, {operation});
        expect(stringValue(done!, 'text/plain'), 'hello');
      },
    );
  }

  testWidgets(
    'unsupported browser operation is rejected without copy fallback',
    (tester) async {
      var drops = 0;
      final point = await mount(
        tester,
        accepts: (_) => true,
        operation: DropOperation.move,
        done: (_) => drops++,
      );
      final data = transfer(allowed: 'copy')..setData('text/plain', 'hello');
      send('dragover', data, point);
      expect(data.dropEffect, 'none');
      send('drop', data, point);
      await tester.pump();
      expect(drops, 0);
    },
  );

  testWidgets('browser files stream complete contents during async onDrop', (
    tester,
  ) async {
    final done = Completer<DropEvent>();
    final finish = Completer<void>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: (event) async {
        done.complete(event);
        await finish.future;
      },
    );
    final bytes = Uint8List(2 * 1024 * 1024 + 3)
      ..fillRange(0, 2 * 1024 * 1024 + 3, 42);
    final data = transfer();
    data.items.add(web.File([bytes.toJS].toJS, 'large.bin'));
    send('drop', data, point);
    await tester.pump();
    await tester.runAsync(() async {
      final file = (await done.future.timeout(const Duration(seconds: 5))).items
          .whereType<DropFileItem>()
          .single
          .file;
      final chunks = await file.openRead().toList();
      // Chunk boundaries are owned by the browser's Blob stream.
      expect(chunks.expand((chunk) => chunk).toList(), bytes);
      expect(await file.openRead(1, 4).expand((chunk) => chunk).toList(), [
        42,
        42,
        42,
      ]);
      await expectLater(file.openRead(0, 0).toList(), throwsRangeError);
    });
    finish.complete();
    await tester.pump();
  });

  testWidgets(
    'URL, HTML, and custom string formats pass through without creating files',
    (tester) async {
      final done = Completer<DropEvent>();
      final offers = <DropOffer>[];
      final point = await mount(
        tester,
        accepts: (event) {
          offers.add(event.offer);
          return event.offer.items.any(
            (item) => item.kind == DropItemKind.string,
          );
        },
        done: done.complete,
      );
      const source = 'data:image/png;base64,cG5n';
      final data = transfer()
        ..setData('text/uri-list', source)
        ..setData('text/html', '<img src="$source">')
        ..setData('application/x-example', 'custom');
      send('dragenter', data, point);
      expect(offers.last.items.every((item) => item.value == null), true);
      expect(
        offers.last.items.any((item) => item.kind == DropItemKind.file),
        false,
      );
      send('drop', data, point);
      await tester.pump();
      final event = await done.future;
      expect(event.items.whereType<DropFileItem>(), isEmpty);
      expect(stringValue(event, 'text/uri-list'), source);
      expect(stringValue(event, 'text/html'), '<img src="$source">');
      expect(stringValue(event, 'application/x-example'), 'custom');
    },
  );

  testWidgets('remote HTML resources are not fetched', (tester) async {
    var requests = 0;
    final original = web.window.getProperty<JSFunction>('fetch'.toJS);
    JSAny? blockedFetch(JSAny? resource, JSAny? options) {
      requests++;
      throw StateError('The drop plugin must not fetch URLs');
    }

    web.window.setProperty('fetch'.toJS, blockedFetch.toJS);
    addTearDown(() => web.window.setProperty('fetch'.toJS, original));
    final done = Completer<DropEvent>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: done.complete,
    );
    final data = transfer()
      ..setData('text/html', '<img src="https://example.com/image.png">')
      ..setData('text/uri-list', 'https://example.com/image.png');
    send('drop', data, point);
    await tester.pump();
    final event = await done.future;
    expect(requests, 0);
    expect(event.items.whereType<DropFileItem>(), isEmpty);
    expect(
      stringValue(event, 'text/uri-list'),
      'https://example.com/image.png',
    );
  });

  testWidgets(
    'capture listeners prevent file navigation even when a descendant stops bubbling',
    (tester) async {
      final done = Completer<DropEvent>();
      final point = await mount(
        tester,
        accepts: (_) => true,
        done: done.complete,
      );
      final host =
          ui_web.views.getHostElement(tester.view.viewId) as web.HTMLElement;
      final blocker = ((web.Event event) => event.stopPropagation()).toJS;
      host.addEventListener('drop', blocker);
      addTearDown(() => host.removeEventListener('drop', blocker));
      final data = transfer()..setData('text/plain', 'hello');
      final event = web.DragEvent(
        'drop',
        web.DragEventInit(
          dataTransfer: data,
          clientX: point.dx.round(),
          clientY: point.dy.round(),
          bubbles: true,
          cancelable: true,
        ),
      );
      host.dispatchEvent(event);
      await tester.pump();
      expect(event.defaultPrevented, true);
      expect(stringValue(await done.future, 'text/plain'), 'hello');
    },
  );

  for (final (name, type, expectedMime) in [
    ('photo.png', 'image/png', 'image/png'),
    ('photo.avif', '', 'image/avif'),
  ]) {
    testWidgets(
      'file $name retains MIME, getAsFile fallback and string representations',
      (tester) async {
        final done = Completer<DropEvent>();
        final finish = Completer<void>();
        final point = await mount(
          tester,
          accepts: (d) => d.offer.items.any(
            (item) =>
                item.kind == DropItemKind.file && item.mimeType == expectedMime,
          ),
          done: (event) async {
            done.complete(event);
            await finish.future;
          },
        );
        final data = transfer()
          ..setData('text/uri-list', 'https://example.com/photo.png')
          ..setData('text/html', '<img src="https://example.com/photo.png">');
        data.items.add(
          web.File(['png'.toJS].toJS, name, web.FilePropertyBag(type: type)),
        );
        send('drop', data, point);
        await tester.pump();
        await tester.runAsync(() async {
          final event = await done.future.timeout(const Duration(seconds: 5));
          final file = event.items.whereType<DropFileItem>().single;
          expect(file.name, name);
          expect(file.mimeType, expectedMime);
          expect(await file.file.readAsString(), 'png');
          expect(
            stringValue(event, 'text/uri-list'),
            'https://example.com/photo.png',
          );
          expect(event.globalPosition, point);
        });
        finish.complete();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'text and URL values are available for the final synchronous decision',
    (tester) async {
      final done = Completer<DropEvent>();
      final offers = <DropOffer>[];
      final point = await mount(
        tester,
        accepts: (d) {
          offers.add(d.offer);
          return !d.offer.isComplete ||
              d.offer.items.any(
                (item) =>
                    item.mimeType == 'text/plain' && item.value == 'hello',
              );
        },
        done: done.complete,
      );
      final data = transfer()
        ..setData('text/plain', 'hello')
        ..setData('text/uri-list', '# comment\r\nhttps://example.com\r\n');
      send('dragenter', data, point);
      expect(offers.last.isComplete, false);
      expect(offers.last.items.every((item) => item.value == null), true);
      expect(
        offers.last.items.map((item) => item.mimeType),
        containsAll(['text/plain', 'text/uri-list']),
      );
      send('drop', data, point);
      await tester.pump();
      await tester.runAsync(() async {
        final event = await done.future.timeout(const Duration(seconds: 5));
        expect(stringValue(event, 'text/plain'), 'hello');
        expect(event.items.whereType<DropFileItem>(), isEmpty);
        expect(
          stringValue(event, 'text/uri-list'),
          '# comment\r\nhttps://example.com\r\n',
        );
        expect(offers.last.isComplete, true);
      });
    },
  );

  testWidgets('state changes while dragging reject drop and clear hover', (
    tester,
  ) async {
    var allowed = true, hovering = false, drops = 0;
    final point = await mount(
      tester,
      accepts: (_) => allowed,
      done: (_) => drops++,
      entered: (_) => hovering = true,
      exited: (_) => hovering = false,
    );
    final data = transfer()..setData('text/plain', 'hello');
    send('dragenter', data, point);
    expect(hovering, true);
    allowed = false;
    send('drop', data, point);
    await tester.pump();
    expect(hovering, false);
    expect(drops, 0);
  });

  testWidgets('accepted empty-file drop clears hover even without dragleave', (
    tester,
  ) async {
    var hovering = false;
    final done = Completer<DropEvent>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: done.complete,
      entered: (_) => hovering = true,
      exited: (_) => hovering = false,
    );
    final data = transfer()..setData('text/plain', 'hello');
    send('dragenter', data, point);
    expect(hovering, true);
    send('drop', data, point);
    await tester.pump();
    await tester.runAsync(() async {
      expect(
        (await done.future.timeout(const Duration(seconds: 5))).items
            .whereType<DropFileItem>(),
        isEmpty,
      );
    });
    expect(hovering, false);
  });
  testWidgets('directory reads consume every batch beyond 100 entries', (
    tester,
  ) async {
    final done = Completer<DropEvent>();
    final finish = Completer<void>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: (event) async {
        done.complete(event);
        await finish.future;
      },
    );
    final entries = List.generate(251, (index) {
      final file = web.File(['$index'.toJS].toJS, '$index.txt');
      return <String, Object?>{
            'name': '$index.txt',
            'fullPath': '/folder/$index.txt',
            'isDirectory': false,
            'isFile': true,
            'file': ((JSFunction success, JSFunction? error) {
              success.callAsFunction(null, file);
            }).toJS,
          }.jsify()
          as JSObject;
    });
    var batches = 0;
    final root =
        <String, Object?>{
              'name': 'folder',
              'fullPath': '/folder',
              'isDirectory': true,
              'isFile': false,
              'createReader': (() {
                var position = 0;
                return <String, Object?>{
                  'readEntries': ((JSFunction success, JSFunction? error) {
                    batches++;
                    final end = (position + 100).clamp(0, entries.length);
                    final batch = entries.sublist(position, end).toJS;
                    position = end;
                    success.callAsFunction(null, batch);
                  }).toJS,
                }.jsify();
              }).toJS,
            }.jsify()
            as JSObject;
    final data = transfer();
    data.items.add(web.File(<JSAny>[].toJS, 'folder'));
    useEntry(root);
    send('drop', data, point);
    await tester.pump();
    expect(done.isCompleted, true);
    final event = await done.future;
    final directory = event.items.single as DropDirectoryItem;
    expect(batches, 0);
    await tester.runAsync(() async {
      final children = await directory.directory.list().toList();
      expect(children.length, 251);
      expect(await (children.last as XFile).name(), '250.txt');
      expect(batches, 4);
      expect(await (children.last as XFile).readAsString(), '250');
      expect(await directory.directory.list().length, 251);
      expect(batches, 8);
    });
    finish.complete();
    await tester.pump();
  });

  testWidgets('asynchronous file reads retain the committed drop position', (
    tester,
  ) async {
    final done = Completer<DropEvent>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: done.complete,
    );
    JSFunction? finish;
    final entry =
        <String, Object?>{
              'name': 'slow.txt',
              'fullPath': '/slow.txt',
              'isDirectory': false,
              'isFile': true,
              'file': ((JSFunction success, JSFunction? error) {
                finish = success;
              }).toJS,
            }.jsify()
            as JSObject;
    final data = transfer();
    final file = web.File(['contents'.toJS].toJS, 'slow.txt');
    data.items.add(file);
    useEntry(entry);
    send('drop', data, point);
    await tester.pump();
    expect(done.isCompleted, false);
    send('dragenter', data, point + const Offset(40, 40));
    finish!.callAsFunction(null, file);
    await tester.pump();
    expect(done.isCompleted, true);
    expect((await done.future).globalPosition, point);
  });
  testWidgets(
    're-registering keeps other DOM listeners and delivers only once',
    (tester) async {
      var drops = 0;
      var otherEvents = 0;
      final point = await mount(
        tester,
        accepts: (_) => true,
        done: (_) => drops++,
      );
      final other = ((web.Event event) => otherEvents++).toJS;
      web.window.addEventListener('drop', other);
      addTearDown(() => web.window.removeEventListener('drop', other));
      DesktopDropWeb.registerWith(webPluginRegistrar);
      DesktopDropWeb.registerWith(webPluginRegistrar);
      final data = transfer()..setData('text/plain', 'hello');
      send('drop', data, point);
      await tester.pump();
      expect(drops, 1);
      expect(otherEvents, 1);
    },
  );
}

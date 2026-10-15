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

Future<Offset> mount(
  WidgetTester tester, {
  required bool Function(DropEventDetails) accepts,
  required void Function(DropDoneDetails) done,
  void Function(DropEventDetails)? entered,
  void Function(DropEventDetails)? exited,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: DropTarget(
          onWillAccept: accepts,
          onDragDone: done,
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

  testWidgets(
    'retained browser files survive URL revocation and stream complete contents',
    (tester) async {
      final done = Completer<DropDoneDetails>();
      final point = await mount(
        tester,
        accepts: (_) => true,
        done: done.complete,
      );
      final bytes = Uint8List(2 * 1024 * 1024 + 3)
        ..fillRange(0, 2 * 1024 * 1024 + 3, 42);
      final data = web.DataTransfer();
      data.items.add(web.File([bytes.toJS].toJS, 'large.bin'));
      send('drop', data, point);
      await tester.pump();
      await tester.runAsync(() async {
        final file = (await done.future.timeout(const Duration(seconds: 5)))
            .files
            .single;
        web.URL.revokeObjectURL(file.path);
        final chunks = await file.openRead().toList();
        // Chunk boundaries are owned by the browser's Blob stream.
        expect(chunks.expand((chunk) => chunk).toList(), bytes);
        expect(await file.openRead(1, 4).expand((chunk) => chunk).toList(), [
          42,
          42,
          42,
        ]);
        expect(await file.openRead(0, 0).toList(), isEmpty);
      });
    },
  );

  testWidgets('data image URLs are materialized only after final acceptance', (
    tester,
  ) async {
    final done = Completer<DropDoneDetails>();
    final point = await mount(
      tester,
      accepts: (details) => details.offer.types.contains(DropType.file),
      done: done.complete,
    );
    const source = 'data:image/png;base64,cG5n';
    final data = web.DataTransfer()
      ..setData('text/uri-list', source)
      ..setData('text/html', '<img src="$source">');
    send('dragenter', data, point);
    expect(done.isCompleted, false);
    send('drop', data, point);
    await tester.pump();
    expect(done.isCompleted, true);
    await tester.runAsync(() async {
      final drop = await done.future.timeout(const Duration(seconds: 5));
      expect(drop.files.single.name, 'image.png');
      expect(await drop.files.single.readAsString(), 'png');
      expect(drop.urls, contains(Uri.parse(source)));
      web.URL.revokeObjectURL(drop.files.single.path);
    });
  });

  testWidgets(
    'capture listeners prevent file navigation even when a descendant stops bubbling',
    (tester) async {
      final done = Completer<DropDoneDetails>();
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
      final data = web.DataTransfer()..setData('text/plain', 'hello');
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
      expect((await done.future).text, 'hello');
    },
  );

  testWidgets(
    'file plus string representations retains getAsFile fallback and bytes',
    (tester) async {
      final done = Completer<DropDoneDetails>();
      final point = await mount(
        tester,
        accepts: (d) => d.offer.types.contains(DropType.file),
        done: done.complete,
      );
      final data = web.DataTransfer()
        ..setData('text/uri-list', 'https://example.com/photo.png')
        ..setData('text/html', '<img src="https://example.com/photo.png">');
      data.items.add(
        web.File(
          ['png'.toJS].toJS,
          'photo.png',
          web.FilePropertyBag(type: 'image/png'),
        ),
      );
      send('drop', data, point);
      await tester.pump();
      await tester.runAsync(() async {
        final event = await done.future.timeout(const Duration(seconds: 5));
        final file = event.files.single;
        expect(file.name, 'photo.png');
        expect(file.mimeType, 'image/png');
        expect(await file.readAsString(), 'png');
        expect(event.urls.single.toString(), 'https://example.com/photo.png');
        expect(event.globalPosition, point);
      });
    },
  );

  testWidgets(
    'text and URL values are available for the final synchronous decision',
    (tester) async {
      final done = Completer<DropDoneDetails>();
      final offers = <DropOffer>[];
      final point = await mount(
        tester,
        accepts: (d) {
          offers.add(d.offer);
          return !d.offer.isComplete || d.offer.text == 'hello';
        },
        done: done.complete,
      );
      final data = web.DataTransfer()
        ..setData('text/plain', 'hello')
        ..setData('text/uri-list', '# comment\r\nhttps://example.com\r\n');
      send('dragenter', data, point);
      expect(offers.last.isComplete, false);
      expect(offers.last.text, null);
      expect(offers.last.types, containsAll([DropType.text, DropType.url]));
      send('drop', data, point);
      await tester.pump();
      await tester.runAsync(() async {
        final event = await done.future.timeout(const Duration(seconds: 5));
        expect(event.text, 'hello');
        expect(event.files, isEmpty);
        expect(event.urls.single.toString(), 'https://example.com');
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
    final data = web.DataTransfer()..setData('text/plain', 'hello');
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
    final done = Completer<DropDoneDetails>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: done.complete,
      entered: (_) => hovering = true,
      exited: (_) => hovering = false,
    );
    final data = web.DataTransfer()..setData('text/plain', 'hello');
    send('dragenter', data, point);
    expect(hovering, true);
    send('drop', data, point);
    await tester.pump();
    await tester.runAsync(() async {
      expect(
        (await done.future.timeout(const Duration(seconds: 5))).files,
        isEmpty,
      );
    });
    expect(hovering, false);
  });
  testWidgets('directory reads consume every batch beyond 100 entries', (
    tester,
  ) async {
    final done = Completer<DropDoneDetails>();
    final point = await mount(
      tester,
      accepts: (_) => true,
      done: done.complete,
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
    final data = web.DataTransfer();
    data.items.add(web.File(<JSAny>[].toJS, 'folder'));
    useEntry(root);
    send('drop', data, point);
    await tester.pump();
    expect(done.isCompleted, true);
    final event = await done.future;
    final directory = event.files.single as DropItemDirectory;
    expect(directory.children.length, 251);
    expect(directory.children.last.name, '250.txt');
    expect(batches, 4);
    await tester.runAsync(() async {
      expect(await directory.children.last.readAsString(), '250');
    });
  });

  testWidgets('asynchronous file reads retain the committed drop position', (
    tester,
  ) async {
    final done = Completer<DropDoneDetails>();
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
    final data = web.DataTransfer();
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
      final data = web.DataTransfer()..setData('text/plain', 'hello');
      send('drop', data, point);
      await tester.pump();
      expect(drops, 1);
      expect(otherEvents, 1);
    },
  );
}

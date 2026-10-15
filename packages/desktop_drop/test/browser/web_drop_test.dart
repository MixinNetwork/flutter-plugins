@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_drop/desktop_drop_web.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// Drops [data] on the window, where the web implementation listens, and
/// returns the [DropDoneEvent] that reaches the Dart side.
Future<DropDoneEvent> _drop(
  web.DataTransfer data, {
  Offset position = Offset.zero,
}) {
  final done = Completer<DropDoneEvent>();
  void listener(DropEvent event) {
    if (event is DropDoneEvent && !done.isCompleted) {
      done.complete(event);
    }
  }

  DesktopDrop.instance.addRawDropEventListener(listener);
  addTearDown(() => DesktopDrop.instance.removeRawDropEventListener(listener));
  web.window.dispatchEvent(web.DragEvent(
    'drop',
    web.DragEventInit(
      dataTransfer: data,
      clientX: position.dx.round(),
      clientY: position.dy.round(),
      bubbles: true,
      cancelable: true,
    ),
  ));
  return done.future.timeout(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    DesktopDropWeb.registerWith(webPluginRegistrar);
    DesktopDrop.instance.init();
  });

  test('drops the file of a drag that also carries string items', () async {
    // An image dragged from a web page carries its link and markup as string
    // items next to the file. In a DataTransfer made by script the file item
    // has no FileSystemEntry either, so this also covers getAsFile().
    final data = web.DataTransfer()
      ..setData('text/uri-list', 'https://example.com/photo.png')
      ..setData('text/html', '<img src="https://example.com/photo.png">');
    data.items.add(web.File(
      ['png'.toJS].toJS,
      'photo.png',
      web.FilePropertyBag(type: 'image/png'),
    ));

    final event = await _drop(data);

    final file = event.files.single;
    expect(file.name, 'photo.png');
    expect(file.mimeType, 'image/png');
    expect(await file.readAsString(), 'png');
  });

  test('a drop without a file item is done with no files', () async {
    final data = web.DataTransfer()..setData('text/plain', 'hello');

    final event = await _drop(data);

    expect(event.files, isEmpty);
  });

  testWidgets('a text-only drop clears the target hover state', (tester) async {
    var hovering = false;
    DropDoneDetails? received;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StatefulBuilder(
            builder: (context, setState) => DropTarget(
              onDragEntered: (_) => setState(() => hovering = true),
              onDragExited: (_) => setState(() => hovering = false),
              onDragDone: (details) => received = details,
              child: SizedBox(
                width: 100,
                height: 100,
                child: Text(hovering ? 'Hovering' : 'Idle'),
              ),
            ),
          ),
        ),
      ),
    );
    final position = tester.getCenter(find.byType(DropTarget));
    final data = web.DataTransfer()..setData('text/plain', 'hello');
    web.window.dispatchEvent(
      web.DragEvent(
        'dragenter',
        web.DragEventInit(
          dataTransfer: data,
          clientX: position.dx.round(),
          clientY: position.dy.round(),
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Hovering'), findsOneWidget);

    // Browsers need not send dragleave after drop. Completion must clear it.
    await tester.runAsync(() => _drop(data, position: position));
    await tester.pump();
    expect(received, isNotNull);
    expect(received!.files, isEmpty);
    expect(find.text('Idle'), findsOneWidget);
  });
}

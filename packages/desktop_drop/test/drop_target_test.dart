import 'dart:async';
import 'dart:io';

import 'package:cross_file_io/cross_file_io.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_drop/src/native_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final transport = NativeTransport.testing();
int _session = 0;
int _requestBase = 0;
const offer = <String, Object?>{
  'strings': [
    {'mimeType': 'text/plain', 'value': 'hello'},
  ],
  'files': [],
  'isComplete': true,
};

Future<Object?> platform(String method, Map<String, Object?> args) =>
    transport.onEvent!(MethodCall(method, args));

Future<int> query(Map<String, Object?> args) async =>
    (await platform('query', args) as Map)['target'] as int;

Map<String, Object?> event(
  Offset point, {
  Map<String, Object?> data = offer,
  int target = 0,
  int request = 1,
  int phase = 1,
  int generation = 7,
  DropOperation operation = DropOperation.copy,
}) => {
  'view': 0,
  'generation': generation,
  'session': _session,
  'request': _requestBase + request,
  'phase': phase,
  'target': target,
  'operation': operation.index,
  'x': point.dx,
  'y': point.dy,
  'offer': {
    'allowedOperations': ['copy'],
    ...data,
  },
};

Future<void> mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    CrossFileIO.registerWith();
    NativeTransport.debugOverride = transport;
  });
  setUp(() {
    _session++;
    _requestBase += 1000;
    transport.invokeHandler = (call) async => {'view': 0, 'generation': 7};
  });
  tearDown(() {
    transport.invokeHandler = null;
  });

  testWidgets('cached offers are shared while decisions remain live', (
    tester,
  ) async {
    var accepts = true;
    final inspected = <DropOffer>[];
    DropEventDetails? hover;
    await mount(
      tester,
      DropTarget(
        onDropDecision: (details) {
          inspected.add(details.offer);
          return accepts ? DropOperation.copy : DropOperation.reject;
        },
        onDragEntered: (details) => hover = details,
        onDragUpdated: (details) => hover = details,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    final cached = inspected.single;
    final compact = event(point)..remove('offer');
    compact['operationMask'] = 1;
    expect(await query(compact), target);
    expect(identical(inspected.last, cached), true);
    await platform('feedback', {...compact, 'target': target});
    expect(identical(hover!.offer, cached), true);
    accepts = false;
    expect(await query(compact), 0);
    accepts = true;
    expect(await query({...compact, 'operationMask': 3}), target);
    expect(inspected.last.allowedOperations, {
      DropOperation.copy,
      DropOperation.move,
    });
    await query(
      event(
        point,
        data: {
          ...offer,
          'strings': [
            {'mimeType': 'text/plain', 'value': 'completed'},
          ],
        },
      ),
    );
    await platform('feedback', {
      ...compact,
      'target': target,
      'request': _requestBase + 2,
    });
    expect(hover!.offer.items.single.value, 'completed');
    expect(await query({...compact, 'session': _session + 1}), -1);
  });

  testWidgets('async drop completes after unmount and reuses the view bridge', (
    tester,
  ) async {
    var initializations = 0;
    transport.invokeHandler = (call) async {
      if (call.method == 'initialize') initializations++;
      return {'view': 0, 'generation': 7};
    };
    final started = Completer<void>();
    final finish = Completer<void>();
    Widget target() => DropTarget(
      onDropDecision: (_) => DropOperation.copy,
      onDrop: (_) async {
        started.complete();
        await finish.future;
      },
      child: const SizedBox(width: 200, height: 200),
    );
    await mount(tester, target());
    final before = initializations;
    const point = Offset(400, 300);
    final selected = await query(event(point));
    var replied = false;
    final reply = platform('drop', event(point, target: selected))
      ..then((_) => replied = true);
    await tester.pump();
    expect(started.isCompleted, true);
    expect(replied, false);
    await mount(tester, const SizedBox());
    expect(await query(event(point)), 0);
    await mount(tester, target());
    expect(initializations, before);
    finish.complete();
    await tester.pump();
    expect(await reply, true);
    expect(replied, true);
  });

  testWidgets(
    'different targets inspect content and current state for each query',
    (tester) async {
      var allowed = true;
      final delivered = <String>[];
      await mount(
        tester,
        SizedBox(
          width: 400,
          height: 200,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DropTarget(
                  key: const Key('text'),
                  onDropDecision: (d) =>
                      allowed &&
                          d.offer.items.any(
                            (item) => item.mimeType == 'text/plain',
                          )
                      ? DropOperation.copy
                      : DropOperation.reject,
                  onDrop: (_) => delivered.add('text'),
                  child: const ColoredBox(color: Color(0xFF000001)),
                ),
              ),
              Expanded(
                child: DropTarget(
                  key: const Key('url'),
                  onDropDecision: (d) =>
                      d.offer.items.any(
                        (item) => item.mimeType == 'text/uri-list',
                      )
                      ? DropOperation.copy
                      : DropOperation.reject,
                  onDrop: (_) => delivered.add('url'),
                  child: const ColoredBox(color: Color(0xFF000002)),
                ),
              ),
            ],
          ),
        ),
      );
      final point = tester.getCenter(find.byKey(const Key('text')));
      final target = await query(event(point));
      expect(target, greaterThan(0));
      expect(
        await query(event(tester.getCenter(find.byKey(const Key('url'))))),
        0,
      );
      allowed = false;
      expect(await query(event(point, phase: 2)), 0);
      allowed = true;
      await platform('drop', event(point, target: target));
      expect(delivered, ['text']);
      final url = await query(
        event(
          tester.getCenter(find.byKey(const Key('url'))),
          data: {
            ...offer,
            'strings': [
              {'mimeType': 'text/uri-list', 'value': 'https://example.com'},
            ],
          },
        ),
      );
      expect(url, greaterThan(0));
      expect(url, isNot(target));
    },
  );

  testWidgets('rejecting nested child falls back to accepting parent', (
    tester,
  ) async {
    var childAccepts = false;
    var selected = '';
    await mount(
      tester,
      DropTarget(
        onDropDecision: (_) => DropOperation.copy,
        onDrop: (_) => selected = 'parent',
        child: SizedBox(
          width: 200,
          height: 200,
          child: DropTarget(
            key: const Key('child'),
            onDropDecision: (_) =>
                childAccepts ? DropOperation.copy : DropOperation.reject,
            onDrop: (_) => selected = 'child',
            child: const ColoredBox(color: Color(0xFF000001)),
          ),
        ),
      ),
    );
    final point = tester.getCenter(find.byKey(const Key('child')));
    final parent = await query(event(point));
    await platform('drop', event(point, target: parent));
    expect(selected, 'parent');
    childAccepts = true;
    final child = await query(event(point));
    expect(child, isNot(parent));
    await platform('drop', event(point, target: child));
    expect(selected, 'child');
  });

  testWidgets('opaque overlay blocks a target behind it', (tester) async {
    await mount(
      tester,
      SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DropTarget(
              onDropDecision: (_) => DropOperation.copy,
              child: const SizedBox.expand(),
            ),
            const Listener(
              behavior: HitTestBehavior.opaque,
              child: SizedBox.expand(),
            ),
          ],
        ),
      ),
    );
    expect(await query(event(const Offset(400, 300))), 0);
  });

  testWidgets('hit testing and local coordinates respect transforms', (
    tester,
  ) async {
    Offset? local;
    await mount(
      tester,
      Transform.translate(
        offset: const Offset(80, 30),
        child: DropTarget(
          key: const Key('target'),
          onDropDecision: (d) {
            local = d.localPosition;
            return DropOperation.copy;
          },
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    final point = tester.getCenter(find.byKey(const Key('target')));
    expect(await query(event(point)), greaterThan(0));
    expect(local, const Offset(50, 50));
    expect(await query(event(const Offset(20, 20))), 0);
  });

  testWidgets('feedback exits once on rejection, final drop, and disabling', (
    tester,
  ) async {
    var enters = 0, exits = 0;
    var enabled = true;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return DropTarget(
            enable: enabled,
            onDropDecision: (_) => DropOperation.copy,
            onDragEntered: (_) => enters++,
            onDragExited: (_) => exits++,
            child: const SizedBox(width: 200, height: 200),
          );
        },
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    await platform('feedback', event(point, target: target));
    await platform('feedback', event(point, target: 0, request: 2));
    expect([enters, exits], [1, 1]);
    await platform('feedback', event(point, target: target, request: 3));
    update(() => enabled = false);
    await tester.pump();
    expect([enters, exits], [2, 2]);
    expect(await query(event(point)), 0);
    update(() => enabled = true);
    await tester.pump();
    await platform('feedback', event(point, target: target, request: 4));
    await platform(
      'feedback',
      event(point, target: target, request: 5, phase: 2),
    );
    expect([enters, exits], [3, 3]);
  });

  testWidgets(
    'committed drops are never retargeted after rebuild or disposal',
    (tester) async {
      var delivered = 0;
      await mount(
        tester,
        DropTarget(
          key: const Key('old'),
          onDropDecision: (_) => DropOperation.copy,
          onDrop: (_) => delivered++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      const point = Offset(400, 300);
      final old = await query(event(point));
      await mount(
        tester,
        DropTarget(
          key: const Key('new'),
          onDropDecision: (_) => DropOperation.copy,
          onDrop: (_) => delivered++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      await platform('drop', event(point, target: old));
      final target = await query(event(point));
      await platform('drop', event(point, target: target, generation: 6));
      expect(delivered, 0);
    },
  );

  testWidgets(
    'an exception rejects the candidate and permits parent fallback',
    (tester) async {
      await mount(
        tester,
        DropTarget(
          onDropDecision: (_) => DropOperation.copy,
          child: SizedBox(
            width: 200,
            height: 200,
            child: DropTarget(
              onDropDecision: (_) => throw StateError('bad predicate'),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(await query(event(const Offset(400, 300))), greaterThan(0));
      await tester.pump();
      expect(tester.takeException(), isStateError);
    },
  );

  testWidgets('Linux resolved paths and original URI-list are separate items', (
    tester,
  ) async {
    DropEvent? done;
    await mount(
      tester,
      DropTarget(
        onDropDecision: (_) => DropOperation.copy,
        onDrop: (d) => done = d,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    await platform(
      'drop',
      event(
        point,
        target: target,
        data: {
          'strings': [
            {
              'mimeType': 'text/uri-list',
              'value':
                  '# original\r\nfile:///run/user/1000/doc/report%20one.pdf',
            },
          ],
          'files': [
            {
              'path': '/run/user/1000/doc/report one.pdf',
              'name': 'report one.pdf',
            },
          ],
          'isComplete': true,
        },
      ),
    );
    expect(
      done!.items.whereType<DropFileItem>().single.localPath,
      '/run/user/1000/doc/report one.pdf',
    );
    expect(
      done!.items.whereType<DropStringItem>().single.value,
      '# original\r\nfile:///run/user/1000/doc/report%20one.pdf',
    );
    expect(done!.globalPosition, point);
  });

  testWidgets('selected operations reach hover and committed drop details', (
    tester,
  ) async {
    var chosen = DropOperation.copy;
    DropEventDetails? hover;
    DropEvent? done;
    await mount(
      tester,
      DropTarget(
        onDropDecision: (details) {
          expect(details.operation, DropOperation.reject);
          expect(details.allowedOperations, {
            DropOperation.copy,
            DropOperation.move,
            DropOperation.link,
          });
          return chosen;
        },
        onDragEntered: (details) => hover = details,
        onDragUpdated: (details) => hover = details,
        onDrop: (details) => done = details,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final data = {
      ...offer,
      'allowedOperations': ['copy', 'move', 'link'],
    };
    for (final operation in [
      DropOperation.copy,
      DropOperation.move,
      DropOperation.link,
    ]) {
      chosen = operation;
      final selection =
          await platform('query', event(point, data: data)) as Map;
      final target = selection['target'] as int;
      expect(target, greaterThan(0));
      expect(selection['operation'], operation.index);
      await platform(
        'feedback',
        event(
          point,
          data: data,
          target: target,
          operation: operation,
          request: operation.index,
        ),
      );
      expect(hover!.operation, operation);
      await platform(
        'drop',
        event(point, data: data, target: target, operation: operation),
      );
      expect(done!.operation, operation);
    }
    chosen = DropOperation.reject;
    expect(await platform('query', event(point, data: data)), {
      'target': 0,
      'operation': 0,
    });
  });

  testWidgets(
    'unsupported child operations fall back without being substituted',
    (tester) async {
      var childOperation = DropOperation.move;
      String? received;
      await mount(
        tester,
        DropTarget(
          onDropDecision: (_) => DropOperation.copy,
          onDrop: (_) => received = 'parent',
          child: SizedBox(
            width: 200,
            height: 200,
            child: DropTarget(
              onDropDecision: (_) => childOperation,
              onDrop: (_) => received = 'child',
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      const point = Offset(400, 300);
      final parent = await platform('query', event(point)) as Map;
      expect(parent['operation'], DropOperation.copy.index);
      await platform('drop', event(point, target: parent['target'] as int));
      expect(received, 'parent');
      final moveOffer = {
        ...offer,
        'allowedOperations': ['move'],
      };
      final child =
          await platform('query', event(point, data: moveOffer)) as Map;
      expect(child['operation'], DropOperation.move.index);
      expect(child['target'], isNot(parent['target']));
      await platform(
        'drop',
        event(
          point,
          data: moveOffer,
          target: child['target'] as int,
          operation: DropOperation.move,
        ),
      );
      expect(received, 'child');
      childOperation = DropOperation.link;
      expect(await platform('query', event(point, data: moveOffer)), {
        'target': 0,
        'operation': 0,
      });
    },
  );
  testWidgets('native sources are read on demand and propagate expiry', (
    tester,
  ) async {
    final temporary = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('desktop_drop_');
      await File('${directory.path}/image.png').writeAsBytes([1, 2]);
      return directory;
    }))!;
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final operations = <String>[];
    var contents = Uint8List.fromList([1, 2]);
    var consumed = false;
    var released = false;
    transport.invokeHandler = (call) async {
      if (call.method == 'initialize') return {'view': 0, 'generation': 7};
      expect(call.method, 'readSource');
      final args = call.arguments as Map;
      expect(args['generation'], 7);
      expect(args['session'], _session);
      final operation = args['op'] as String;
      operations.add(operation);
      if (released) throw PlatformException(code: 'source_expired');
      switch (operation) {
        case 'open':
          consumed = false;
          return 42;
        case 'read':
          if (consumed) return Uint8List(0);
          consumed = true;
          return contents;
        case 'close':
          return null;
        case 'resolve':
          expect(args['source'], 1);
          return temporary.path;
      }
      throw StateError('Unexpected source operation: $operation');
    };
    final finish = Completer<void>();
    DropEvent? drop;
    await mount(
      tester,
      DropTarget(
        onDropDecision: (_) => DropOperation.copy,
        onDrop: (event) async {
          drop = event;
          await finish.future;
        },
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    final reply = platform(
      'drop',
      event(
        point,
        target: target,
        data: {
          'files': [
            {'name': 'image.png', 'source': 0},
            {
              'name': 'folder',
              'source': 1,
              'isDirectory': true,
              'resolvePath': true,
            },
          ],
        },
      ),
    );
    await tester.pump();
    expect(operations, isEmpty);
    final file = drop!.items.whereType<DropFileItem>().single;
    expect(file.localPath, isNull);
    expect(await file.file.readAsBytes(), [1, 2]);
    expect(operations, ['open', 'read', 'read', 'close']);
    contents = Uint8List.fromList([3]);
    expect(await file.file.readAsBytes(), [3]);
    final directory = drop!.items.whereType<DropDirectoryItem>().single;
    final children = (await tester.runAsync(
      () => directory.directory.list().toList(),
    ))!;
    expect(operations.last, 'resolve');
    expect(await children.whereType<XFile>().single.name(), 'image.png');
    final resolvedOperations = operations.length;
    expect(await tester.runAsync(() => directory.directory.list().length), 1);
    expect(operations.length, resolvedOperations);
    finish.complete();
    await reply;
    // Model native cleanup when the drop FFI reply arrives.
    released = true;
    await tester.runAsync(() => temporary.delete(recursive: true));
    await expectLater(
      file.file.readAsBytes(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'source_expired',
        ),
      ),
    );
    expect(await tester.runAsync(() => directory.directory.exists()), false);
  });
  testWidgets(
    'native providers, virtual folders, and MIME strings retain their types',
    (tester) async {
      final contents = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([104, 105]),
        Uint8List.fromList([111, 107]),
      ];
      final consumed = <int>{};
      transport.invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': 0, 'generation': 7};
        }
        expect(call.method, 'readSource');
        final args = call.arguments as Map;
        switch (args['op']) {
          case 'open':
            final stream = (args['source'] as int) + 1;
            consumed.remove(stream);
            return stream;
          case 'read':
            final stream = args['stream'] as int;
            return consumed.add(stream) ? contents[stream - 1] : Uint8List(0);
          case 'close':
            return null;
        }
        throw StateError('Unexpected source operation: ${args['op']}');
      };
      final finish = Completer<void>();
      DropEvent? drop;
      await mount(
        tester,
        DropTarget(
          onDropDecision: (_) => DropOperation.copy,
          onDrop: (event) async {
            drop = event;
            await finish.future;
          },
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      const point = Offset(400, 300);
      final target = await query(event(point));
      final reply = platform(
        'drop',
        event(
          point,
          target: target,
          data: {
            'files': [
              {'name': 'image.png', 'mimeType': 'image/png', 'source': 0},
              {'name': 'folder', 'virtualPath': 'folder', 'isDirectory': true},
              {
                'name': 'nested.txt',
                'virtualPath': r'folder\nested.txt',
                'source': 1,
              },
              {
                'name': 'child.txt',
                'virtualPath': r'folder\subfolder\child.txt',
                'source': 2,
              },
            ],
            'strings': [
              {
                'mimeType': 'text/uri-list',
                'value': 'https://example.com/image.png',
              },
              {
                'mimeType': 'text/html',
                'value': '<img src="https://example.com/image.png">',
              },
              {'mimeType': 'application/x-example', 'value': 'custom'},
            ],
          },
        ),
      );
      await tester.pump();
      final file = drop!.items.whereType<DropFileItem>().single;
      expect(
        drop!.offer.items
            .where((item) => item.kind != DropItemKind.string)
            .map((item) => (item.kind, item.name)),
        [(DropItemKind.file, 'image.png'), (DropItemKind.directory, 'folder')],
      );
      expect(file.localPath, isNull);
      expect(file.mimeType, 'image/png');
      expect(await file.file.readAsBytes(), [1, 2, 3]);
      final directory = drop!.items.whereType<DropDirectoryItem>().single;
      expect(directory.localPath, isNull);
      final children = await directory.directory.list().toList();
      expect(await children.whereType<XFile>().single.readAsString(), 'hi');
      final nested = await children
          .whereType<XDirectory>()
          .single
          .list()
          .toList();
      expect(await (nested.single as XFile).name(), 'child.txt');
      expect(await (nested.single as XFile).readAsString(), 'ok');
      expect(
        drop!.items.whereType<DropStringItem>().map((item) => item.mimeType),
        ['text/uri-list', 'text/html', 'application/x-example'],
      );
      expect(() => drop!.items.clear(), throwsUnsupportedError);
      finish.complete();
      await reply;
    },
  );
}

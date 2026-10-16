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
  'operation': operation.index + 1,
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

  testWidgets('defaults accept all advertised kinds using copy', (
    tester,
  ) async {
    DragDetails? preview;
    DropDetails? received;
    await mount(
      tester,
      DropTarget(
        onEnter: (details) => preview = details,
        onDrop: (details) => received = details,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final data = {
      'files': [
        {'name': 'report.txt', 'path': '/tmp/report.txt'},
        {'name': 'folder', 'path': '/tmp/folder', 'isDirectory': true},
      ],
      'strings': [
        {'mimeType': 'text/plain', 'value': 'hello'},
      ],
    };
    final selection = await platform('query', event(point, data: data)) as Map;
    expect(selection['operation'], 1);
    final target = selection['target'] as int;
    expect(target, greaterThan(0));
    await platform('feedback', event(point, data: data, target: target));
    expect(preview!.items.map((item) => item.kind), [
      DropItemKind.file,
      DropItemKind.directory,
      DropItemKind.string,
    ]);
    expect(() => preview!.items.clear(), throwsUnsupportedError);
    await platform('drop', event(point, data: data, target: target));
    expect(received!.operation, DropOperation.copy);
    expect(received!.items, [
      isA<DropFileItem>(),
      isA<DropDirectoryItem>(),
      isA<DropStringItem>(),
    ]);
    expect(() => received!.items.clear(), throwsUnsupportedError);
    expect(
      await platform(
        'query',
        event(
          point,
          data: {
            ...data,
            'allowedOperations': ['move'],
          },
        ),
      ),
      {'target': 0, 'operation': 0},
    );
    expect(await query(event(point, data: {'files': [], 'strings': []})), 0);
  });

  testWidgets('kind filtering gates the predicate without filtering delivery', (
    tester,
  ) async {
    var checks = 0;
    var accepted = true;
    DropDetails? received;
    await mount(
      tester,
      DropTarget(
        acceptedKinds: const {DropItemKind.file},
        onWillAccept: (_) {
          checks++;
          return accepted;
        },
        onDrop: (details) => received = details,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    expect(await query(event(point)), 0);
    expect(checks, 0);
    final data = {
      ...offer,
      'files': [
        {'name': 'report.txt', 'path': '/tmp/report.txt'},
      ],
    };
    expect(
      await query(
        event(
          point,
          data: {
            ...data,
            'allowedOperations': ['move'],
          },
        ),
      ),
      0,
    );
    expect(checks, 0);
    final target = await query(event(point, data: data));
    expect(target, greaterThan(0));
    accepted = false;
    expect(await query(event(point, data: data, phase: 2)), 0);
    accepted = true;
    await platform('drop', event(point, data: data, target: target));
    expect(received!.items.whereType<DropFileItem>(), hasLength(1));
    expect(received!.items.whereType<DropStringItem>().single.value, 'hello');
    await mount(
      tester,
      DropTarget(
        acceptedKinds: const {},
        onDrop: (_) {},
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    expect(await query(event(point, data: data)), 0);
  });

  testWidgets(
    'directory targets accept incomplete previews then check final kind',
    (tester) async {
      await mount(
        tester,
        DropTarget(
          acceptedKinds: const {DropItemKind.directory},
          onDrop: (_) {},
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      const point = Offset(400, 300);
      final data = {
        'files': [
          {'name': 'folder'},
        ],
        'isComplete': false,
      };
      expect(await query(event(point, data: data)), greaterThan(0));
      expect(
        await query(
          event(point, phase: 2, data: {...data, 'isComplete': true}),
        ),
        0,
      );
      expect(
        await query(
          event(
            point,
            phase: 2,
            data: {
              'files': [
                {'name': 'folder', 'isDirectory': true},
              ],
              'isComplete': true,
            },
          ),
        ),
        greaterThan(0),
      );
    },
  );

  testWidgets('drop clears hover once before invoking application processing', (
    tester,
  ) async {
    final callbacks = <String>[];
    await mount(
      tester,
      DropTarget(
        onEnter: (_) => callbacks.add('enter'),
        onLeave: () => callbacks.add('leave'),
        onDrop: (_) => callbacks.add('drop'),
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    await platform('feedback', event(point, target: target));
    await platform('drop', event(point, target: target));
    await platform('exit', event(point));
    expect(callbacks, ['enter', 'leave', 'drop']);
  });

  testWidgets('delayed delivery does not clear a newer drag hover', (
    tester,
  ) async {
    var enters = 0, leaves = 0, drops = 0;
    await mount(
      tester,
      DropTarget(
        onEnter: (_) => enters++,
        onLeave: () => leaves++,
        onDrop: (_) => drops++,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    await platform('feedback', event(point, target: target));
    await platform('feedback', {
      ...event(point, target: target, request: 2),
      'session': _session + 1,
    });
    expect([enters, leaves], [2, 1]);
    await platform('drop', event(point, target: target));
    expect([drops, leaves], [1, 1]);
    await platform('exit', {...event(point), 'session': _session + 1});
    expect(leaves, 2);
  });

  testWidgets('cached offers are shared while decisions remain live', (
    tester,
  ) async {
    var accepts = true;
    final inspected = <DragDetails>[];
    DragDetails? hover;
    await mount(
      tester,
      DropTarget(
        onDrop: (_) {},
        onWillAccept: (details) {
          inspected.add(details);
          return accepts;
        },
        onEnter: (details) => hover = details,
        onMove: (details) => hover = details,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await query(event(point));
    final cached = inspected.single;
    final compact = event(point)..remove('offer');
    compact['operationMask'] = 1;
    expect(await query(compact), target);
    expect(inspected.last.items, cached.items);
    await platform('feedback', {...compact, 'target': target});
    expect(hover!.items, cached.items);
    accepts = false;
    expect(await query(compact), 0);
    accepts = true;
    expect(await query({...compact, 'operationMask': 3}), target);
    expect(inspected.last.items.single.value, 'hello');
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
    expect(hover!.items.single.value, 'completed');
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
                  onWillAccept: (d) =>
                      allowed &&
                      d.items.any((item) => item.mimeType == 'text/plain'),
                  onDrop: (_) => delivered.add('text'),
                  child: const ColoredBox(color: Color(0xFF000001)),
                ),
              ),
              Expanded(
                child: DropTarget(
                  key: const Key('url'),
                  onWillAccept: (d) =>
                      d.items.any((item) => item.mimeType == 'text/uri-list'),
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
        onDrop: (_) => selected = 'parent',
        child: SizedBox(
          width: 200,
          height: 200,
          child: DropTarget(
            key: const Key('child'),
            onWillAccept: (_) => childAccepts,
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
            DropTarget(onDrop: (_) {}, child: const SizedBox.expand()),
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
          onDrop: (_) {},
          key: const Key('target'),
          onWillAccept: (d) {
            local = d.localPosition;
            return true;
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
            onDrop: (_) {},
            enabled: enabled,
            onEnter: (_) => enters++,
            onLeave: () => exits++,
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
          onDrop: (_) {},
          child: SizedBox(
            width: 200,
            height: 200,
            child: DropTarget(
              onDrop: (_) {},
              onWillAccept: (_) => throw StateError('bad predicate'),
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
    DropDetails? done;
    await mount(
      tester,
      DropTarget(
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

  testWidgets('configured operations reach the native reply and drop details', (
    tester,
  ) async {
    DragDetails? hover;
    DropDetails? done;
    const point = Offset(400, 300);
    final data = {
      ...offer,
      'allowedOperations': ['copy', 'move', 'link'],
    };
    for (final operation in DropOperation.values) {
      await mount(
        tester,
        DropTarget(
          operation: operation,
          onEnter: (details) => hover = details,
          onMove: (details) => hover = details,
          onDrop: (details) => done = details,
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      final selection =
          await platform('query', event(point, data: data)) as Map;
      final target = selection['target'] as int;
      expect(target, greaterThan(0));
      expect(selection['operation'], operation.index + 1);
      await platform(
        'feedback',
        event(
          point,
          data: data,
          target: target,
          operation: operation,
          request: operation.index + 10,
        ),
      );
      expect(hover!.items.single.value, 'hello');
      await platform(
        'drop',
        event(point, data: data, target: target, operation: operation),
      );
      expect(done!.operation, operation);
    }
  });

  testWidgets(
    'unsupported child operations fall back without being substituted',
    (tester) async {
      const childOperation = DropOperation.move;
      String? received;
      await mount(
        tester,
        DropTarget(
          onDrop: (_) => received = 'parent',
          child: SizedBox(
            width: 200,
            height: 200,
            child: DropTarget(
              operation: childOperation,
              onDrop: (_) => received = 'child',
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      const point = Offset(400, 300);
      final parent = await platform('query', event(point)) as Map;
      expect(parent['operation'], 1);
      await platform('drop', event(point, target: parent['target'] as int));
      expect(received, 'parent');
      final moveOffer = {
        ...offer,
        'allowedOperations': ['move'],
      };
      final child =
          await platform('query', event(point, data: moveOffer)) as Map;
      expect(child['operation'], 2);
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
      expect(
        await platform(
          'query',
          event(
            point,
            data: {
              ...offer,
              'allowedOperations': ['link'],
            },
          ),
        ),
        {'target': 0, 'operation': 0},
      );
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
    DropDetails? drop;
    await mount(
      tester,
      DropTarget(
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
      DropDetails? drop;
      await mount(
        tester,
        DropTarget(
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

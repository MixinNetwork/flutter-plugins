import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const channel = MethodChannel('desktop_drop');
const offer = <String, Object?>{
  'types': ['text'],
  'text': 'hello',
  'files': [],
  'urls': [],
  'isComplete': true,
};

Future<Object?> platform(String method, Map<String, Object?> args) async {
  final done = Completer<ByteData?>();
  const codec = StandardMethodCodec();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'desktop_drop',
        codec.encodeMethodCall(MethodCall(method, args)),
        done.complete,
      );
  final reply = await done.future;
  return reply == null ? null : codec.decodeEnvelope(reply);
}

Map<String, Object?> event(
  Offset point, {
  Map<String, Object?> data = offer,
  int target = 0,
  int request = 1,
  int phase = 1,
  int generation = 7,
}) => {
  'view': 0,
  'generation': generation,
  'session': 1,
  'request': request,
  'phase': phase,
  'target': target,
  'x': point.dx,
  'y': point.dy,
  'offer': data,
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
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'view': 0, 'generation': 7},
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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
                      allowed && d.offer.types.contains(DropType.text),
                  onDragDone: (_) => delivered.add('text'),
                  child: const ColoredBox(color: Color(0xFF000001)),
                ),
              ),
              Expanded(
                child: DropTarget(
                  key: const Key('url'),
                  onWillAccept: (d) => d.offer.types.contains(DropType.url),
                  onDragDone: (_) => delivered.add('url'),
                  child: const ColoredBox(color: Color(0xFF000002)),
                ),
              ),
            ],
          ),
        ),
      );
      final point = tester.getCenter(find.byKey(const Key('text')));
      final target = await platform('query', event(point)) as int;
      expect(target, greaterThan(0));
      expect(
        await platform(
          'query',
          event(tester.getCenter(find.byKey(const Key('url')))),
        ),
        0,
      );
      allowed = false;
      expect(await platform('query', event(point, phase: 2)), 0);
      allowed = true;
      await platform('drop', event(point, target: target));
      expect(delivered, ['text']);
      final url = await platform(
        'query',
        event(
          tester.getCenter(find.byKey(const Key('url'))),
          data: {
            ...offer,
            'types': ['url'],
            'urls': ['https://example.com'],
          },
        ),
      ) as int;
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
        onWillAccept: (_) => true,
        onDragDone: (_) => selected = 'parent',
        child: SizedBox(
          width: 200,
          height: 200,
          child: DropTarget(
            key: const Key('child'),
            onWillAccept: (_) => childAccepts,
            onDragDone: (_) => selected = 'child',
            child: const ColoredBox(color: Color(0xFF000001)),
          ),
        ),
      ),
    );
    final point = tester.getCenter(find.byKey(const Key('child')));
    final parent = await platform('query', event(point)) as int;
    await platform('drop', event(point, target: parent));
    expect(selected, 'parent');
    childAccepts = true;
    final child = await platform('query', event(point)) as int;
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
              onWillAccept: (_) => true,
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
    expect(await platform('query', event(const Offset(400, 300))), 0);
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
          onWillAccept: (d) {
            local = d.localPosition;
            return true;
          },
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    final point = tester.getCenter(find.byKey(const Key('target')));
    expect(await platform('query', event(point)), greaterThan(0));
    expect(local, const Offset(50, 50));
    expect(await platform('query', event(const Offset(20, 20))), 0);
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
            onWillAccept: (_) => true,
            onDragEntered: (_) => enters++,
            onDragExited: (_) => exits++,
            child: const SizedBox(width: 200, height: 200),
          );
        },
      ),
    );
    const point = Offset(400, 300);
    final target = await platform('query', event(point)) as int;
    await platform('feedback', event(point, target: target));
    await platform('feedback', event(point, target: 0, request: 2));
    expect([enters, exits], [1, 1]);
    await platform('feedback', event(point, target: target, request: 3));
    update(() => enabled = false);
    await tester.pump();
    expect([enters, exits], [2, 2]);
    expect(await platform('query', event(point)), 0);
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
          onWillAccept: (_) => true,
          onDragDone: (_) => delivered++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      const point = Offset(400, 300);
      final old = await platform('query', event(point)) as int;
      await mount(
        tester,
        DropTarget(
          key: const Key('new'),
          onWillAccept: (_) => true,
          onDragDone: (_) => delivered++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );
      await platform('drop', event(point, target: old));
      final target = await platform('query', event(point)) as int;
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
          onWillAccept: (_) => true,
          child: SizedBox(
            width: 200,
            height: 200,
            child: DropTarget(
              onWillAccept: (_) => throw StateError('bad predicate'),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(
        await platform('query', event(const Offset(400, 300))),
        greaterThan(0),
      );
      await tester.pump();
      expect(tester.takeException(), isStateError);
    },
  );

  testWidgets('Linux native paths and original portal key remain available', (
    tester,
  ) async {
    DropDoneDetails? done;
    await mount(
      tester,
      DropTarget(
        onWillAccept: (_) => true,
        onDragDone: (d) => done = d,
        child: const SizedBox(width: 200, height: 200),
      ),
    );
    const point = Offset(400, 300);
    final target = await platform('query', event(point)) as int;
    await platform(
      'drop',
      event(
        point,
        target: target,
        data: {
          'types': ['file'],
          'files': [
            {
              'path': '/run/user/1000/doc/report one.pdf',
              'name': 'report one.pdf',
            },
          ],
          'rawText': 'original-portal-transfer-key',
          'isComplete': true,
        },
      ),
    );
    expect(done!.files.single.path, '/run/user/1000/doc/report one.pdf');
    expect(done!.rawText, 'original-portal-transfer-key');
    expect(done!.globalPosition, point);
  });
}

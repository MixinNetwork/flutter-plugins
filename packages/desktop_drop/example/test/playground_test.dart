import 'package:cross_file_io/cross_file_io.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_drop/src/native_transport.dart';
import 'package:desktop_drop_example/pages/drop_stage.dart';
import 'package:desktop_drop_example/pages/drop_content.dart';
import 'package:desktop_drop_example/common/received_item.dart';
import 'package:desktop_drop_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final transport = NativeTransport.testing();

Future<Object?> native(String method, Map<String, Object?> args) async {
  final result = await transport.onEvent!(MethodCall(method, args));
  return method == 'query' ? (result as Map)['target'] : result;
}

Map<String, Object?> args(
  Offset point,
  String name, {
  String? mimeType,
  bool isComplete = true,
}) => {
  'view': 0,
  'generation': 0,
  'session': 1,
  'request': 1,
  'phase': 2,
  'operation': 1,
  'x': point.dx,
  'y': point.dy,
  'offer': {
    'allowedOperations': ['copy'],
    'isComplete': isComplete,
    'files': [
      {'name': name, 'source': 0, 'mimeType': mimeType},
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    CrossFileIO.registerWith();
    NativeTransport.debugOverride = transport;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    transport.invokeHandler = (call) async =>
        call.method == 'initialize' ? {'view': 0, 'generation': 0} : null;
  });
  tearDown(() => transport.invokeHandler = null);

  for (final size in [const Size(800, 600), const Size(1200, 760)]) {
    testWidgets('targets and results stay side by side at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final parent = tester.getRect(
        find.byKey(const ValueKey('target-Parent')),
      );
      final result = tester.getRect(find.text('Nothing dropped yet'));
      expect(parent.right, lessThan(result.left));
      expect(parent.bottom, lessThanOrEqualTo(size.height));
      expect(find.text('Swap layers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'overlapping siblings obey layer order and read content during drop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final sourceOperations = <String>[];
      var consumed = false;
      transport.invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': 0, 'generation': 0};
        }
        if (call.method == 'readSource') {
          final operation = (call.arguments as Map)['op'] as String;
          sourceOperations.add(operation);
          switch (operation) {
            case 'open':
              consumed = false;
              return 1;
            case 'read':
              if (consumed) return Uint8List(0);
              consumed = true;
              return Uint8List.fromList('Hello drop'.codeUnits);
          }
        }
        return null;
      };
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final a = tester.getRect(find.byKey(const ValueKey('target-Child A')));
      final b = tester.getRect(find.byKey(const ValueKey('target-Child B')));
      final overlap = a.intersect(b).center;
      final parent = await native(
        'query',
        args(a.topRight + const Offset(10, 70), 'notes.txt'),
      ) as int;
      final frontB = await native('query', args(overlap, 'photo.jpg')) as int;
      expect(parent, greaterThan(0));
      expect(frontB, isNot(parent));
      expect(await native('query', args(overlap, 'notes.txt')), parent);
      expect(
        await native(
          'query',
          args(overlap, 'notes.txt', mimeType: 'image/png'),
        ),
        frontB,
      );
      expect(
        await native(
          'query',
          args(overlap, '', mimeType: 'image/png', isComplete: false),
        ),
        frontB,
      );
      expect(
        await native('query', args(overlap, '', isComplete: false)),
        frontB,
      );
      await tester.tap(find.byKey(const ValueKey('swap-layers')));
      await tester.pumpAndSettle();
      final frontA = await native('query', args(overlap, 'notes.txt')) as int;
      expect(frontA, greaterThan(0));
      expect(frontA, isNot(parent));
      expect(await native('query', args(overlap, 'image.png')), parent);
      expect(
        await native(
          'query',
          args(overlap, 'image.png', mimeType: 'text/plain'),
        ),
        frontA,
      );
      expect(
        await native(
          'query',
          args(overlap, '', mimeType: 'text/plain', isComplete: false),
        ),
        frontA,
      );
      await native('drop', {...args(overlap, 'notes.txt'), 'target': frontA});
      await tester.pumpAndSettle();
      expect(find.text('Received by Child A · copy'), findsOneWidget);
      expect(find.text('Hello drop'), findsOneWidget);
      expect(find.text('Preview'), findsNothing);
      expect(find.text('Read bytes'), findsNothing);
      expect(find.text('List contents'), findsNothing);
      expect(sourceOperations, ['open', 'read', 'read', 'close']);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing dropped yet'), findsOneWidget);
      expect(sourceOperations, ['open', 'read', 'read', 'close']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Text and Images consume only their matching representations', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    DropDetails? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DropStage(onDrop: (_, details) => received = details),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final a = tester.getRect(find.byKey(const ValueKey('target-Child A')));
    final b = tester.getRect(find.byKey(const ValueKey('target-Child B')));
    final overlap = a.intersect(b).center;
    final mixed = args(overlap, 'photo.jpg');
    (mixed['offer'] as Map)['strings'] = [
      {'mimeType': 'text/plain', 'value': 'selected text'},
      {'mimeType': 'text/uri-list', 'value': 'https://example.com'},
    ];
    final images = await native('query', mixed);
    await native('drop', {...mixed, 'target': images});
    await tester.pumpAndSettle();
    expect(received!.items, hasLength(1));
    expect(received!.items.single, isA<DropFileItem>());
    expect(received!.items.single.mimeType, 'image/jpeg');
    await tester.tap(find.byKey(const ValueKey('swap-layers')));
    await tester.pumpAndSettle();
    final text = await native('query', mixed);
    await native('drop', {...mixed, 'target': text});
    await tester.pumpAndSettle();
    expect(received!.items, hasLength(1));
    expect((received!.items.single as DropStringItem).value, 'selected text');
    final parent = await native(
      'query',
      args(a.topRight + const Offset(10, 70), 'unknown'),
    );
    expect(await native('query', args(overlap, 'unknown')), parent);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'received directories navigate to cached text without rendering errors',
    (tester) async {
      final file = DropFileItem.fromPath('/unused/deep.txt');
      final nested = DropDirectoryItem(
        directory: XDirectory.fileSystem(path: '/unused/nested'),
        name: 'nested',
      );
      final folder = DropDirectoryItem(
        directory: XDirectory.fileSystem(path: '/unused'),
        name: 'folder',
      );
      final details = DropDetails(
        items: [folder],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
        operation: DropOperation.copy,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DropContent(
              event: details,
              receiver: 'Parent',
              onClear: () {},
              content: {
                folder: ReceivedItem(children: [nested]),
                nested: ReceivedItem(children: [file]),
                file: ReceivedItem(
                  bytes: Uint8List.fromList('nested content'.codeUnits),
                ),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('nested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('deep.txt'));
      await tester.pumpAndSettle();
      expect(find.text('nested content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

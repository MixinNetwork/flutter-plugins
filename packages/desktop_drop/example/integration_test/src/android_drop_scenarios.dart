import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = MethodChannel('desktop_drop_example/test');
const _targetKey = ValueKey('drop-target');
// android.view.DragEvent action constants.
const _dragStarted = 1;
const _dragLocation = 2;
const _drop = 3;
const _dragEnded = 4;
const _dragEntered = 5;

Future<bool> _dispatch(
  int action,
  Offset point, {
  String text = 'hello',
  String kind = 'text',
}) async => (await _host.invokeMethod<bool>('dispatchDrag', {
  'action': action,
  'x': point.dx,
  'y': point.dy,
  'text': text,
  'kind': kind,
}))!;

Future<Offset> _mount(WidgetTester tester, Widget target) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 200, height: 200, child: target)),
    ),
  );
  await tester.pumpAndSettle();
  final point = tester.getCenter(find.byKey(_targetKey));
  // Initialization crosses the native RPC bridge before registering decisions.
  for (var attempt = 0; attempt < 20; attempt++) {
    if (await _dispatch(_dragStarted, point)) return point;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('The native decision bridge did not initialize');
}

void registerAndroidDropTests() {
  testWidgets('Android previews text file MIME and delivers a readable file', (
    tester,
  ) async {
    final received = Completer<String>();
    DragDetails? preview;
    final point = await _mount(
      tester,
      DropTarget(
        key: _targetKey,
        acceptedKinds: const {DropItemKind.file},
        onWillAccept: (details) {
          preview = details;
          return details.items.any(
            (item) =>
                item.kind == DropItemKind.file && item.mimeType == 'text/plain',
          );
        },
        onDrop: (details) async {
          received.complete(
            await details.items
                .whereType<DropFileItem>()
                .single
                .file
                .readAsString(),
          );
        },
        child: const SizedBox.expand(),
      ),
    );
    await _dispatch(_dragStarted, point, kind: 'file');
    await _dispatch(_dragLocation, point, kind: 'file');
    expect(
      preview!.items.any(
        (item) =>
            item.kind == DropItemKind.file && item.mimeType == 'text/plain',
      ),
      true,
    );
    expect(await _dispatch(_drop, point, kind: 'file'), true);
    expect(
      await received.future.timeout(const Duration(seconds: 5)),
      'hello text file',
    );
    await _dispatch(_dragEnded, point, kind: 'file');
  });

  testWidgets('Android advertises image MIME before delivering bytes', (
    tester,
  ) async {
    final received = Completer<List<int>>();
    DragDetails? preview;
    final point = await _mount(
      tester,
      DropTarget(
        key: _targetKey,
        acceptedKinds: const {DropItemKind.file},
        onWillAccept: (details) {
          preview = details;
          return details.items.any((item) => item.mimeType == 'image/png');
        },
        onDrop: (details) async => received.complete(
          await details.items
              .whereType<DropFileItem>()
              .single
              .file
              .readAsBytes(),
        ),
        child: const SizedBox.expand(),
      ),
    );
    await _dispatch(_dragStarted, point, kind: 'image');
    await _dispatch(_dragLocation, point, kind: 'image');
    expect(preview!.items.single.mimeType, 'image/png');
    expect(await _dispatch(_drop, point, kind: 'image'), true);
    expect(
      (await received.future.timeout(const Duration(seconds: 5))).take(8),
      [137, 80, 78, 71, 13, 10, 26, 10],
    );
    await _dispatch(_dragEnded, point, kind: 'image');
  });

  for (final kind in ['directory', 'tree']) {
    testWidgets(
      'Android $kind URIs list immediate and nested readable children',
      (tester) async {
        final received = Completer<List<String>>();
        XDirectory? retained;
        final point = await _mount(
          tester,
          DropTarget(
            key: _targetKey,
            acceptedKinds: const {DropItemKind.directory},
            onDrop: (details) async {
              try {
                final directory = details.items
                    .whereType<DropDirectoryItem>()
                    .single;
                retained = directory.directory;
                expect(directory.name, 'folder');
                expect(directory.localPath, isNull);
                final first = await directory.directory.list().toList();
                expect(first.whereType<XFile>(), hasLength(1));
                expect(first.whereType<XDirectory>(), hasLength(1));
                final nested = await first
                    .whereType<XDirectory>()
                    .single
                    .list()
                    .toList();
                final again = await directory.directory.list().toList();
                expect(
                  again.map((item) => item.uri),
                  first.map((item) => item.uri),
                );
                received.complete([
                  await first.whereType<XFile>().single.readAsString(),
                  await nested.whereType<XFile>().single.readAsString(),
                ]);
              } catch (error, stack) {
                received.completeError(error, stack);
              }
            },
            child: const SizedBox.expand(),
          ),
        );
        await _dispatch(_dragStarted, point, kind: kind);
        await _dispatch(_dragLocation, point, kind: kind);
        expect(await _dispatch(_drop, point, kind: kind), true);
        expect(await received.future.timeout(const Duration(seconds: 5)), [
          'inside directory',
          'nested directory',
        ]);
        await _dispatch(_dragEnded, point, kind: kind);
        await tester.pumpAndSettle();
        await expectLater(
          retained!.list().toList(),
          throwsA(isA<PlatformException>()),
        );
      },
    );
  }

  testWidgets('Android returns false when the final Dart condition rejects', (
    tester,
  ) async {
    final previews = <DragDetails>[];
    var drops = 0;
    final point = await _mount(
      tester,
      DropTarget(
        key: _targetKey,
        acceptedKinds: const {DropItemKind.string},
        onWillAccept: (details) {
          previews.add(details);
          return details.items.any(
            (item) =>
                item.kind == DropItemKind.string &&
                (item.value == null || item.value == 'accept'),
          );
        },
        onDrop: (_) => drops++,
        child: const SizedBox.expand(),
      ),
    );
    await _dispatch(_dragEntered, point);
    await _dispatch(_dragLocation, point);
    expect(
      previews.last.items
          .where((item) => item.kind == DropItemKind.string)
          .every((item) => item.value == null),
      true,
    );
    expect(await _dispatch(_drop, point, text: 'reject'), false);
    await _dispatch(_dragEnded, point);
    await tester.pumpAndSettle();
    expect(previews.last.items.single.value, 'reject');
    expect(drops, 0);
  });

  testWidgets('Android returns acceptance before async processing finishes', (
    tester,
  ) async {
    final started = Completer<DropDetails>();
    final finish = Completer<void>();
    final entered = Completer<void>();
    var hovering = false;
    var completed = false;
    final point = await _mount(
      tester,
      DropTarget(
        key: _targetKey,
        acceptedKinds: const {DropItemKind.string},
        onEnter: (_) {
          hovering = true;
          if (!entered.isCompleted) entered.complete();
        },
        onLeave: () => hovering = false,
        onDrop: (details) async {
          started.complete(details);
          await finish.future;
          completed = true;
        },
        child: const SizedBox.expand(),
      ),
    );
    addTearDown(() {
      if (!finish.isCompleted) finish.complete();
    });
    await _dispatch(_dragEntered, point);
    await _dispatch(_dragLocation, point);
    await entered.future.timeout(const Duration(seconds: 5));
    expect(hovering, true);
    expect(await _dispatch(_drop, point, text: 'accepted'), true);
    final details = await started.future.timeout(const Duration(seconds: 5));
    expect(details.items.whereType<DropStringItem>().single.value, 'accepted');
    expect(details.operation, DropOperation.copy);
    expect(hovering, false);
    expect(completed, false);
    await _dispatch(_dragEnded, point);
    finish.complete();
    await tester.pumpAndSettle();
    expect(completed, true);
  });

  for (final operation in [DropOperation.move, DropOperation.link]) {
    testWidgets('Android rejects unsupported ${operation.name}', (
      tester,
    ) async {
      var drops = 0;
      final point = await _mount(
        tester,
        DropTarget(
          key: _targetKey,
          operation: operation,
          onDrop: (_) => drops++,
          child: const SizedBox.expand(),
        ),
      );
      await _dispatch(_dragEntered, point);
      expect(await _dispatch(_drop, point), false);
      await _dispatch(_dragEnded, point);
      await tester.pumpAndSettle();
      expect(drops, 0);
    });
  }

  testWidgets('Android rejects disabled targets and mismatched final kinds', (
    tester,
  ) async {
    var drops = 0;
    for (final enabled in [false, true]) {
      final point = await _mount(
        tester,
        DropTarget(
          key: _targetKey,
          enabled: enabled,
          acceptedKinds: const {DropItemKind.file},
          onDrop: (_) => drops++,
          child: const SizedBox.expand(),
        ),
      );
      await _dispatch(_dragEntered, point);
      expect(await _dispatch(_drop, point), false);
      await _dispatch(_dragEnded, point);
    }
    expect(drops, 0);
  });

  testWidgets('Android keeps parent fallback for rejecting nested targets', (
    tester,
  ) async {
    final received = Completer<String>();
    final point = await _mount(
      tester,
      DropTarget(
        onDrop: (_) => received.complete('parent'),
        child: DropTarget(
          key: _targetKey,
          onWillAccept: (_) => false,
          onDrop: (_) => received.complete('child'),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await _dispatch(_dragEntered, point);
    expect(await _dispatch(_drop, point), true);
    await _dispatch(_dragEnded, point);
    expect(await received.future.timeout(const Duration(seconds: 5)), 'parent');
  });
}

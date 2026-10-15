import 'dart:async';

import 'package:desktop_drop_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Object?> native(String method, Map<String, Object?> args) async {
  const codec = StandardMethodCodec();
  final response = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'desktop_drop',
        codec.encodeMethodCall(MethodCall(method, args)),
        response.complete,
      );
  final bytes = await response.future;
  return bytes == null ? null : codec.decodeEnvelope(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (call) async => {'view': 0},
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
  });

  for (final size in [
    const Size(320, 568),
    const Size(800, 600),
    const Size(1200, 760),
  ]) {
    testWidgets(
      'playground fits ${size.width} by ${size.height} and remains scrollable',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();
        expect(find.text('Desktop Drop'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('toggle-All files')),
        );
        await tester.tap(find.byKey(const ValueKey('toggle-All files')));
        await tester.pumpAndSettle();
        expect(find.text('Acceptance off'), findsOneWidget);
        if (size.width < 780) {
          await tester.scrollUntilVisible(
            find.text('Drop inspector'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
        } else {
          await tester.ensureVisible(find.text('Drop inspector'));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('large text scales target cards without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real target decisions drive inspector and independent switches',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 760);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final point = tester.getCenter(
        find.byKey(const ValueKey('target-TXT files')),
      );
      final args = <String, Object?>{
        'view': 0,
        'generation': 0,
        'session': 1,
        'request': 1,
        'phase': 2,
        'x': point.dx,
        'y': point.dy,
        'offer': {
          'types': ['file'],
          'files': [
            {'name': 'notes.txt', 'path': '/tmp/notes.txt'},
          ],
          'isComplete': true,
        },
      };
      expect(
        await native('query', {
          ...args,
          'offer': {
            'types': ['file'],
            'files': [],
            'isComplete': false,
          },
        }),
        greaterThan(0),
      );
      expect(
        await native('query', {
          ...args,
          'offer': {
            'types': ['file'],
            'files': [
              {'name': 'photo.png'},
            ],
            'isComplete': true,
          },
        }),
        0,
      );
      final target = await native('query', args) as int;
      expect(target, greaterThan(0));
      await native('feedback', {...args, 'target': target});
      await native('drop', {...args, 'target': target});
      await tester.pumpAndSettle();
      expect(find.text('Drop #1'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('TXT files'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('toggle-TXT files')));
      await tester.pumpAndSettle();
      expect(await native('query', args), 0);
      final all = tester.getCenter(
        find.byKey(const ValueKey('target-All files')),
      );
      expect(
        await native('query', {...args, 'x': all.dx, 'y': all.dy}),
        greaterThan(0),
      );
      await tester.tap(find.byTooltip('Clear last drop'));
      await tester.pumpAndSettle();
      expect(find.text('No drops yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
